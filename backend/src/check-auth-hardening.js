const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { generateAccessToken } = require('./services/tokenService');
const { loginLocalUser } = require('./services/loginService');
const { collectAuthConfigErrors } = require('./config/authConfig');
const pool = require('./db');

const TEST_SECRET = 'auth-hardening-test-secret';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30437;

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

function applyJwtTestEnv() {
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.JWT_EXPIRES_IN = '15m';
  process.env.REFRESH_TOKEN_EXPIRES_DAYS = '90';
}

function httpRequest({ port, method, urlPath, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers: {
          ...(data ? { 'Content-Type': 'application/json', 'Content-Length': data.length } : {}),
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

function signToken(overrides = {}, signOptions = {}) {
  return jwt.sign(
    {
      userId: 42,
      login: 'test_user',
      auth_provider: 'local',
      ...overrides,
    },
    TEST_SECRET,
    {
      algorithm: 'HS256',
      expiresIn: '15m',
      issuer: TEST_ISSUER,
      audience: TEST_AUDIENCE,
      jwtid: 'test-jti',
      ...signOptions,
    }
  );
}

async function withCompareSpy(fn) {
  const original = bcrypt.compare;
  let count = 0;
  bcrypt.compare = async (...args) => {
    count += 1;
    return original.apply(bcrypt, args);
  };
  try {
    await fn();
    return count;
  } finally {
    bcrypt.compare = original;
  }
}

async function testLoginTimingPaths() {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousUrl || 'postgres://auth-hardening-test/local';
  applyJwtTestEnv();

  const originalQuery = pool.query;
  const originalConnect = pool.connect;

  try {
    pool.query = async () => ({ rows: [], rowCount: 0 });
    const missingCount = await withCompareSpy(async () => {
      await expectStatus(
        () => loginLocalUser({ login: 'nobody', password: 'wrong-password' }),
        401,
        'Invalid credentials'
      );
    });
    assert(missingCount === 1, `F: expected bcrypt.compare once for missing user, got ${missingCount}`);
    console.log('F OK login inexistant -> 401 Invalid credentials (bcrypt.compare)');

    const passwordHash = await bcrypt.hash('correct-password', 4);
    pool.query = async (sql) => {
      if (String(sql).toUpperCase().includes('FROM USERS')) {
        return {
          rowCount: 1,
          rows: [
            {
              id: 1,
              login: 'test_user',
              email: 'user@example.com',
              auth_provider: 'local',
              password_hash: passwordHash,
              phone_verified: true,
            },
          ],
        };
      }
      throw new Error(`unexpected query: ${sql}`);
    };

    const wrongCount = await withCompareSpy(async () => {
      await expectStatus(
        () => loginLocalUser({ login: 'test_user', password: 'wrong-password' }),
        401,
        'Invalid credentials'
      );
    });
    assert(wrongCount === 1, `G: expected bcrypt.compare once for wrong password, got ${wrongCount}`);
    console.log('G OK mauvais mot de passe -> 401 Invalid credentials (bcrypt.compare)');
  } finally {
    pool.query = originalQuery;
    pool.connect = originalConnect;
    if (!previousUrl) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previousUrl;
    }
  }
}

async function testConfigValidation() {
  const previous = {
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN,
    REFRESH_TOKEN_EXPIRES_DAYS: process.env.REFRESH_TOKEN_EXPIRES_DAYS,
  };

  process.env.JWT_SECRET = '';
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.JWT_EXPIRES_IN = '15m';
  process.env.REFRESH_TOKEN_EXPIRES_DAYS = '90';
  assert(collectAuthConfigErrors().includes('JWT_SECRET is missing'), 'empty JWT_SECRET should be rejected');

  process.env.JWT_SECRET = 'short';
  assert(collectAuthConfigErrors().includes('JWT_SECRET is too short'), 'short JWT_SECRET should be rejected');

  applyJwtTestEnv();
  process.env.JWT_EXPIRES_IN = '0m';
  assert(collectAuthConfigErrors().includes('JWT_EXPIRES_IN is invalid'), 'zero TTL should be rejected');

  applyJwtTestEnv();
  process.env.JWT_EXPIRES_IN = '72h';
  assert(collectAuthConfigErrors().includes('JWT_EXPIRES_IN is invalid'), 'access TTL > 24h should be rejected');

  applyJwtTestEnv();
  process.env.REFRESH_TOKEN_EXPIRES_DAYS = '0';
  assert(
    collectAuthConfigErrors().includes('REFRESH_TOKEN_EXPIRES_DAYS is invalid'),
    'zero refresh days should be rejected'
  );

  Object.entries(previous).forEach(([key, value]) => {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  });
}

async function main() {
  const previousEnv = {
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN,
    REFRESH_TOKEN_EXPIRES_DAYS: process.env.REFRESH_TOKEN_EXPIRES_DAYS,
  };

  applyJwtTestEnv();
  await testConfigValidation();
  applyJwtTestEnv();
  await testLoginTimingPaths();
  applyJwtTestEnv();

  const { child, logs } = startTestServer(TEST_PORT);

  try {
    await waitForLog(logs, 'Server listening', 8000);

    const valid = generateAccessToken({
      id: 42,
      login: 'test_user',
      auth_provider: 'local',
    });
    const decoded = jwt.decode(valid);
    assert(decoded.jti, 'generated JWT must include jti');
    assert(decoded.iss === TEST_ISSUER, 'generated JWT must include iss');
    assert(decoded.aud === TEST_AUDIENCE, 'generated JWT must include aud');
    assert(typeof decoded.exp === 'number', 'generated JWT must include exp');

    const ok = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${valid}` },
    });
    assert(ok.status === 200, `A: expected 200, got ${ok.status} ${ok.raw}`);
    assert(ok.json && ok.json.user && ok.json.user.login === 'test_user', 'A: user payload');
    console.log('A OK JWT valide -> 200');

    const expired = signToken({}, { expiresIn: -10 });
    const expiredRes = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${expired}` },
    });
    assert(expiredRes.status === 401, `B: expected 401, got ${expiredRes.status}`);
    assert(expiredRes.json && expiredRes.json.error === 'Unauthorized', `B: ${expiredRes.raw}`);
    console.log('B OK JWT expiré -> 401 Unauthorized');

    const badIssuer = signToken({}, { issuer: 'other-issuer' });
    const issuerRes = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${badIssuer}` },
    });
    assert(issuerRes.status === 401, `C: expected 401, got ${issuerRes.status}`);
    assert(issuerRes.json && issuerRes.json.error === 'Unauthorized', `C: ${issuerRes.raw}`);
    console.log('C OK JWT mauvais issuer -> 401 Unauthorized');

    const badAudience = signToken({}, { audience: 'other-audience' });
    const audienceRes = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${badAudience}` },
    });
    assert(audienceRes.status === 401, `D: expected 401, got ${audienceRes.status}`);
    assert(audienceRes.json && audienceRes.json.error === 'Unauthorized', `D: ${audienceRes.raw}`);
    console.log('D OK JWT mauvaise audience -> 401 Unauthorized');

    const otherAlg = jwt.sign(
      { userId: 42, login: 'test_user', auth_provider: 'local' },
      TEST_SECRET,
      {
        algorithm: 'HS384',
        expiresIn: '15m',
        issuer: TEST_ISSUER,
        audience: TEST_AUDIENCE,
        jwtid: 'test-jti-hs384',
      }
    );
    const algRes = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${otherAlg}` },
    });
    assert(algRes.status === 401, `E: expected 401, got ${algRes.status}`);
    assert(algRes.json && algRes.json.error === 'Unauthorized', `E: ${algRes.raw}`);
    console.log('E OK JWT algorithme différent -> 401 Unauthorized');

    const noExp = jwt.sign(
      { userId: 42, login: 'test_user', auth_provider: 'local' },
      TEST_SECRET,
      { algorithm: 'HS256', issuer: TEST_ISSUER, audience: TEST_AUDIENCE, jwtid: 'no-exp' }
    );
    const noExpRes = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${noExp}` },
    });
    assert(noExpRes.status === 401, `no exp: expected 401, got ${noExpRes.status}`);

    const hugeBody = JSON.stringify({
      login: 'test_user',
      password: 'wrong-password',
      pad: 'a'.repeat(40 * 1024),
    });
    const huge = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/login',
      body: Buffer.from(hugeBody),
    });
    assert(huge.status === 413, `H: expected 413, got ${huge.status} ${huge.raw}`);
    assert(!huge.raw.includes('stack'), 'H: 413 must not include a stack');
    console.log('H OK body JSON > 32kb -> 413');

    const combinedLogs = logs.join('');
    const forbidden = [valid, expired, TEST_SECRET, 'wrong-password', 'correct-password'];
    for (const secret of forbidden) {
      assert(!combinedLogs.includes(secret), `I: logs leaked ${secret.slice(0, 12)}…`);
    }
    assert(!combinedLogs.includes('JsonWebTokenError'), 'I: logs leaked JWT error name');
    assert(!combinedLogs.includes('TokenExpiredError'), 'I: logs leaked JWT expiry name');
    assert(!/\$2[aby]\$/.test(combinedLogs), 'I: logs leaked bcrypt hash');
    console.log('I OK logs sans JWT, password, hash ni secret');
  } finally {
    await stopServer(child);
    Object.entries(previousEnv).forEach(([key, value]) => {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    });
  }

  console.log('Auth hardening checks succeeded.');
}

main().catch((err) => {
  console.error('Auth hardening checks failed:', err.message);
  process.exitCode = 1;
});
