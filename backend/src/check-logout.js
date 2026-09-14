const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const { generateAccessToken, generateRefreshToken } = require('./services/tokenService');
const { logoutCurrentSession } = require('./services/logoutService');

const TEST_SECRET = 'logout-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30439;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function expectStatus(fn, statusCode, message) {
  try {
    await fn();
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    if (message) {
      assert(err.message === message, `unexpected message: ${err.message}`);
    }
  }
}

function normalizeSql(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function createMemoryDb({ tokens }) {
  const state = {
    tokens: tokens.map((token) => ({ ...token })),
    queries: [],
  };

  const client = {
    async query(sql, params = []) {
      const normalized = normalizeSql(sql);
      state.queries.push({ sql: normalized, params });

      if (normalized === 'BEGIN' || normalized === 'COMMIT' || normalized === 'ROLLBACK') {
        return { rows: [], rowCount: 0 };
      }

      if (normalized.includes('FROM REFRESH_TOKENS') && normalized.includes('TOKEN_HASH')) {
        assert(normalized.includes('FOR UPDATE'), 'logout lookup must lock the row');
        const hash = params[0];
        const row = state.tokens.find((token) => token.token_hash === hash);
        return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
      }

      if (
        normalized.includes('UPDATE REFRESH_TOKENS') &&
        normalized.includes('WHERE ID') &&
        normalized.includes('REVOKED_AT IS NULL')
      ) {
        const token = state.tokens.find((item) => item.id === params[0]);
        if (!token || token.revoked_at != null) {
          return { rows: [], rowCount: 0 };
        }
        token.revoked_at = new Date();
        return { rows: [], rowCount: 1 };
      }

      throw new Error(`unexpected query: ${sql}`);
    },
    release() {},
  };

  return {
    state,
    async connect() {
      return client;
    },
  };
}

function httpRequest({ port, method, urlPath, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers: {
          ...(data
            ? {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
              }
            : {}),
          ...headers,
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try {
            json = JSON.parse(raw);
          } catch (_) {
            json = null;
          }
          resolve({ status: res.statusCode, json, raw });
        });
      }
    );
    req.on('error', reject);
    if (data) {
      req.write(data);
    }
    req.end();
  });
}

function startTestServer(port) {
  const logs = [];
  const env = {
    ...process.env,
    PORT: String(port),
    JWT_SECRET: TEST_SECRET,
    JWT_ISSUER: TEST_ISSUER,
    JWT_AUDIENCE: TEST_AUDIENCE,
    JWT_EXPIRES_IN: '15m',
    REFRESH_TOKEN_EXPIRES_DAYS: '90',
    DEV_LOG_SMS_CODE: 'false',
  };
  delete env.DATABASE_URL;

  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: path.join(__dirname, '..'),
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const onData = (chunk) => {
    logs.push(chunk.toString('utf8'));
  };
  child.stdout.on('data', onData);
  child.stderr.on('data', onData);

  return { child, logs };
}

function waitForLog(logs, pattern, timeoutMs) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      if (logs.join('').includes(pattern)) {
        clearInterval(timer);
        resolve();
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(timer);
        reject(new Error(`server did not start: ${logs.join('')}`));
      }
    }, 50);
  });
}

function stopServer(child) {
  return new Promise((resolve) => {
    const t = setTimeout(() => {
      child.kill('SIGKILL');
      resolve();
    }, 2000);
    child.on('exit', () => {
      clearTimeout(t);
      resolve();
    });
    child.kill('SIGTERM');
  });
}

async function testServiceLogout(logs) {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousUrl || 'postgres://logout-test/local';

  const own = generateRefreshToken();
  const other = generateRefreshToken();
  const unknown = generateRefreshToken();

  const db = createMemoryDb({
    tokens: [
      {
        id: 1,
        user_id: 42,
        token_hash: own.token_hash,
        expires_at: new Date(Date.now() + 60_000),
        revoked_at: null,
      },
      {
        id: 2,
        user_id: 99,
        token_hash: other.token_hash,
        expires_at: new Date(Date.now() + 60_000),
        revoked_at: null,
      },
    ],
  });

  try {
    await logoutCurrentSession({ refresh_token: own.token }, 42, db);
    assert(db.state.tokens[0].revoked_at, 'D: revoked_at must be set');
    assert(db.state.tokens[1].revoked_at == null, 'D: other user token must stay active');
    console.log('D OK logout valide -> 200 / revoked_at');

    await expectStatus(
      () => logoutCurrentSession({ refresh_token: own.token }, 42, db),
      401,
      'Unauthorized'
    );
    console.log('E OK deuxieme logout meme token -> 401');

    await expectStatus(
      () => logoutCurrentSession({ refresh_token: other.token }, 42, db),
      401,
      'Unauthorized'
    );
    assert(db.state.tokens[1].revoked_at == null, 'F: must not revoke another user token');
    console.log('F OK token d un autre utilisateur -> 401');

    await expectStatus(
      () => logoutCurrentSession({ refresh_token: unknown.token }, 42, db),
      401,
      'Unauthorized'
    );

    const queryDump = JSON.stringify(db.state.queries);
    assert(!queryDump.includes(own.token), 'G: queries leaked refresh_token');
    assert(!queryDump.includes(other.token), 'G: queries leaked other refresh_token');
    assert(!queryDump.includes(unknown.token), 'G: queries leaked unknown refresh_token');
  } finally {
    if (!previousUrl) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previousUrl;
    }
  }

  return { own, other, unknown };
}

async function main() {
  const previous = {
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN,
  };

  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.JWT_EXPIRES_IN = '15m';

  const captured = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args) => {
    captured.push(args.map(String).join(' '));
    originalLog.apply(console, args);
  };
  console.error = (...args) => {
    captured.push(args.map(String).join(' '));
    originalError.apply(console, args);
  };

  const { child, logs } = startTestServer(TEST_PORT);

  try {
    await waitForLog(logs, 'Server listening', 8000);

    const missingAuth = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/logout',
      body: { refresh_token: 'should-not-matter' },
    });
    assert(missingAuth.status === 401, `A: expected 401, got ${missingAuth.status}`);
    assert(missingAuth.json && missingAuth.json.error === 'Unauthorized', `A: ${missingAuth.raw}`);
    console.log('A OK POST /auth/logout sans Authorization -> 401');

    const badJwt = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/logout',
      headers: { Authorization: 'Bearer mauvais_token' },
      body: { refresh_token: 'should-not-matter' },
    });
    assert(badJwt.status === 401, `B: expected 401, got ${badJwt.status}`);
    assert(badJwt.json && badJwt.json.error === 'Unauthorized', `B: ${badJwt.raw}`);
    console.log('B OK POST /auth/logout mauvais JWT -> 401');

    const accessToken = generateAccessToken({
      id: 42,
      login: 'test_user',
      auth_provider: 'local',
    });

    const missingRefresh = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/logout',
      headers: { Authorization: `Bearer ${accessToken}` },
      body: {},
    });
    assert(missingRefresh.status === 400, `C: expected 400, got ${missingRefresh.status}`);
    assert(
      missingRefresh.json && missingRefresh.json.error === 'Refresh token required',
      `C: ${missingRefresh.raw}`
    );
    console.log('C OK refresh_token absent -> 400');

    const probeToken = generateRefreshToken();
    const probe = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/logout',
      headers: { Authorization: `Bearer ${accessToken}` },
      body: { refresh_token: probeToken.token },
    });
    assert(
      probe.status === 503 || probe.status === 401,
      `probe: unexpected ${probe.status} ${probe.raw}`
    );
    assert(!probe.raw.includes(accessToken), 'G: response echoed JWT');
    assert(!probe.raw.includes(probeToken.token), 'G: response echoed refresh_token');
    assert(!probe.raw.includes(probeToken.token_hash), 'G: response echoed token_hash');

    const secrets = await testServiceLogout(captured);
    const combinedLogs = [...logs, ...captured].join('\n');
    const forbidden = [
      accessToken,
      probeToken.token,
      probeToken.token_hash,
      secrets.own.token,
      secrets.own.token_hash,
      secrets.other.token,
      TEST_SECRET,
    ];
    for (const secret of forbidden) {
      assert(!combinedLogs.includes(secret), `G: logs leaked ${secret}`);
    }
    console.log('G OK logs sans refresh_token, token_hash, JWT ni secret');
  } finally {
    console.log = originalLog;
    console.error = originalError;
    await stopServer(child);
    Object.entries(previous).forEach(([key, value]) => {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    });
  }

  console.log('Logout checks succeeded.');
}

main().catch((err) => {
  console.error('Logout checks failed:', err.message);
  process.exitCode = 1;
});
