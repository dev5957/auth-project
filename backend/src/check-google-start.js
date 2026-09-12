const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const AppError = require('./errors/AppError');
const { startGoogleAuth, PENDING_PHONE_PLACEHOLDER } = require('./services/googleStartService');

const TEST_SECRET = 'google-start-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30441;
const ID_TOKEN = 'google-id-token-must-not-appear-in-logs';

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

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function googleIdentity(overrides = {}) {
  return {
    provider_user_id: 'google-user-123',
    email: 'User@Example.com',
    first_name: 'Ada',
    last_name: 'Lovelace',
    ...overrides,
  };
}

function createMemoryDb({ users = [], tokens = [], verifications = [] } = {}) {
  const state = {
    users: users.map((user) => ({ ...user })),
    tokens: tokens.map((token) => ({ ...token })),
    verifications: verifications.map((row) => ({ ...row })),
    insertedUsers: 0,
  };
  let nextTokenId = state.tokens.reduce((max, token) => Math.max(max, token.id || 0), 0) + 1;

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('FROM USERS') && key.includes("AUTH_PROVIDER = 'GOOGLE'") && key.includes('PROVIDER_USER_ID')) {
      const row = state.users.find(
        (user) => user.auth_provider === 'google' && user.provider_user_id === params[0]
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM USERS') && key.includes('WHERE EMAIL')) {
      const row = state.users.find((user) => user.email === params[0]);
      return {
        rows: row ? [{ auth_provider: row.auth_provider }] : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes('FROM REFRESH_TOKENS') && key.includes('USER_ID')) {
      const rows = state.tokens.filter(
        (token) => token.user_id === params[0] && token.revoked_at == null
      );
      return { rows: rows.map((token) => ({ id: token.id })), rowCount: rows.length };
    }

    if (key.startsWith('INSERT INTO REFRESH_TOKENS')) {
      state.tokens.push({
        id: nextTokenId,
        user_id: params[0],
        token_hash: params[1],
        expires_at: params[2],
        revoked_at: null,
      });
      nextTokenId += 1;
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('INSERT INTO PHONE_VERIFICATIONS')) {
      state.verifications.push({
        verification_token: params[0],
        phone_number: params[1],
        code_hash: params[2],
        expires_at: params[3],
        registration_data: params[4],
      });
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('INSERT INTO USERS')) {
      state.insertedUsers += 1;
      throw new Error('users must not be inserted by google/start');
    }

    if (key.startsWith('UPDATE REFRESH_TOKENS')) {
      return { rows: [], rowCount: 0 };
    }

    throw new Error(`unexpected query: ${sql}`);
  }

  return {
    state,
    query,
    async connect() {
      return {
        query,
        release() {},
      };
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
    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('request timeout'));
    });
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
    GOOGLE_CLIENT_ID: 'google-start-http-client-id',
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

async function main() {
  const previous = {
    DATABASE_URL: process.env.DATABASE_URL,
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN,
    GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID,
  };

  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://google-start-test/local';
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.JWT_EXPIRES_IN = '15m';
  process.env.GOOGLE_CLIENT_ID = 'google-start-unit-client-id';

  const identity = googleIdentity();

  await expectStatus(() => startGoogleAuth({}), 400, 'id_token is required');
  await expectStatus(() => startGoogleAuth({ id_token: '' }), 400, 'id_token is required');
  await expectStatus(() => startGoogleAuth({ id_token: '   ' }), 400, 'id_token is required');
  console.log('OK id_token absent -> 400 via verifyGoogleIdToken()');

  await expectStatus(
    () =>
      startGoogleAuth(
        { id_token: ID_TOKEN },
        {
          verifyGoogleIdToken: async () => {
            throw new AppError(401, 'Unauthorized');
          },
        }
      ),
    401,
    'Unauthorized'
  );
  console.log('OK id_token Google invalide -> 401');

  const existingDb = createMemoryDb({
    users: [
      {
        id: 7,
        login: 'ada',
        email: 'user@example.com',
        auth_provider: 'google',
        provider_user_id: 'google-user-123',
      },
    ],
  });
  let seenToken = null;
  const loggedIn = await startGoogleAuth(
    { id_token: ID_TOKEN },
    {
      db: existingDb,
      verifyGoogleIdToken: async (idToken) => {
        seenToken = idToken;
        return identity;
      },
    }
  );
  assert(seenToken === ID_TOKEN, 'existing: verifyGoogleIdToken received id_token');
  assert(loggedIn.message === 'Login successful', 'existing: message');
  assert(typeof loggedIn.access_token === 'string' && loggedIn.access_token.length > 20, 'existing: access_token');
  assert(typeof loggedIn.refresh_token === 'string' && loggedIn.refresh_token.length > 20, 'existing: refresh_token');
  assert(existingDb.state.tokens.length === 1, 'existing: refresh stored');
  assert(existingDb.state.verifications.length === 0, 'existing: no pending oauth row');
  assert(existingDb.state.insertedUsers === 0, 'existing: no users insert');
  console.log('OK compte Google existant -> Login successful + session');

  const newDb = createMemoryDb({ users: [] });
  const pending = await startGoogleAuth(
    { id_token: ID_TOKEN },
    {
      db: newDb,
      verifyGoogleIdToken: async () => identity,
    }
  );
  assert(pending.message === 'Phone verification required', 'new: message');
  assert(typeof pending.oauth_verification_token === 'string' && pending.oauth_verification_token.length === 64, 'new: token');
  assert(pending.email === 'user@example.com', 'new: email normalized');
  assert(!pending.access_token, 'new: must not issue access_token');
  assert(newDb.state.users.length === 0, 'new: no users row');
  assert(newDb.state.verifications.length === 1, 'new: pending verification');
  assert(newDb.state.verifications[0].phone_number === PENDING_PHONE_PLACEHOLDER, 'new: placeholder phone');
  assert(newDb.state.verifications[0].registration_data.provider === 'google', 'new: provider');
  assert(newDb.state.verifications[0].registration_data.provider_user_id === 'google-user-123', 'new: provider_user_id');
  assert(newDb.state.verifications[0].registration_data.email === 'user@example.com', 'new: stored email');
  assert(newDb.state.verifications[0].registration_data.first_name === 'Ada', 'new: first_name');
  assert(newDb.state.verifications[0].registration_data.last_name === 'Lovelace', 'new: last_name');
  console.log('OK nouveau Google -> oauth_verification_token, pas de users');

  const conflictDb = createMemoryDb({
    users: [
      {
        id: 3,
        login: 'local_ada',
        email: 'user@example.com',
        auth_provider: 'local',
        provider_user_id: null,
      },
    ],
  });
  await expectStatus(
    () =>
      startGoogleAuth(
        { id_token: ID_TOKEN },
        {
          db: conflictDb,
          verifyGoogleIdToken: async () => identity,
        }
      ),
    409,
    'Account already exists with another authentication method'
  );
  assert(conflictDb.state.verifications.length === 0, 'conflict: no pending row');
  console.log('OK email local existant -> 409 sans fusion');

  const previousDbUrl = process.env.DATABASE_URL;
  try {
    delete process.env.DATABASE_URL;
    await expectStatus(
      () =>
        startGoogleAuth(
          { id_token: ID_TOKEN },
          {
            verifyGoogleIdToken: async () => identity,
          }
        ),
      503,
      'Database is not configured'
    );
  } finally {
    process.env.DATABASE_URL = previousDbUrl;
  }
  console.log('OK sans DATABASE_URL -> 503');

  const { child, logs } = startTestServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);

    const missing = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/google/start',
      body: {},
    });
    assert(missing.status === 400, `HTTP missing: ${missing.status} ${missing.raw}`);
    assert(missing.json && missing.json.error === 'id_token is required', 'HTTP missing message');

    const invalid = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/google/start',
      body: { id_token: ID_TOKEN },
    });
    assert(invalid.status === 401 || invalid.status === 503, `HTTP invalid: ${invalid.status} ${invalid.raw}`);
    assert(!invalid.raw.includes(ID_TOKEN), 'HTTP response leaked id_token');

    const combinedLogs = logs.join('');
    assert(!combinedLogs.includes(ID_TOKEN), 'HTTP logs leaked id_token');
    console.log('OK HTTP POST /auth/google/start et logs propres');
  } finally {
    await stopServer(child);
    Object.entries(previous).forEach(([key, value]) => {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    });
  }

  console.log('Google start checks succeeded.');
}

main().catch((err) => {
  console.error('Google start checks failed:', err.message);
  process.exitCode = 1;
});
