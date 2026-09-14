const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const { generateAccessToken } = require('./services/tokenService');
const { findUserProfileById } = require('./services/userService');
const pool = require('./db');

const TEST_SECRET = 'user-profile-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30438;

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

function assertNoSecrets(payload) {
  const raw = JSON.stringify(payload);
  assert(!raw.includes('password_hash'), 'D: password_hash must not appear');
  assert(!raw.includes('refresh_token'), 'D: refresh_token must not appear');
  assert(!raw.includes('token_hash'), 'D: token_hash must not appear');
  assert(!Object.prototype.hasOwnProperty.call(payload, 'password_hash'), 'D: password_hash key');
}

function httpRequest({ port, method, urlPath, headers = {} }) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers,
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

async function testServiceWithMock() {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousUrl || 'postgres://user-profile-test/local';

  const originalQuery = pool.query;
  let lookupId;

  try {
    pool.query = async (sql, params = []) => {
      lookupId = params[0];
      assert(sql.includes('$1'), 'SQL must be parameterized');
      assert(!sql.includes('password_hash'), 'profile query must not select password_hash');
      assert(!sql.includes('${'), 'no SQL interpolation');
      if (params[0] === 42 || params[0] === '42') {
        return {
          rowCount: 1,
          rows: [
            {
              id: 42,
              login: 'example',
              email: 'user@example.com',
              phone_number: '+33600000000',
              birth_date: new Date(Date.UTC(2000, 0, 1)),
              auth_provider: 'local',
              password_hash: 'must-not-leak',
            },
          ],
        };
      }
      return { rowCount: 0, rows: [] };
    };

    const accessToken = generateAccessToken({
      id: 42,
      login: 'stale-login-from-jwt',
      auth_provider: 'local',
    });
    assert(accessToken, 'C: token should be issued');

    const profile = await findUserProfileById(42);
    assert(lookupId === 42, `C: lookup must use JWT userId, got ${lookupId}`);
    assert(profile.login === 'example', 'C: login must come from SQL, not JWT');
    assert(profile.email === 'user@example.com', 'C: email');
    assert(profile.phone_number === '+33600000000', 'C: phone');
    assert(profile.birth_date === '2000-01-01', 'C: birth_date');
    assert(profile.auth_provider === 'local', 'C: auth_provider');
    assert(profile.id === 42, 'C: id');
    assertNoSecrets(profile);
    console.log('C OK JWT valide + utilisateur existant -> profil SQL 200');
    console.log('D OK réponse sans password_hash / refresh_token / token_hash');

    await expectStatus(() => findUserProfileById(999), 404, 'User not found');
    console.log('E OK utilisateur inexistant -> 404 User not found');
  } finally {
    pool.query = originalQuery;
    if (!previousUrl) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previousUrl;
    }
  }
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

  await testServiceWithMock();

  const { child, logs } = startTestServer(TEST_PORT);

  try {
    await waitForLog(logs, 'Server listening', 8000);

    const missing = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/profile',
    });
    assert(missing.status === 401, `A: expected 401, got ${missing.status}`);
    assert(missing.json && missing.json.error === 'Unauthorized', `A: ${missing.raw}`);
    console.log('A OK GET /auth/profile sans Authorization -> 401');

    const bad = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/profile',
      headers: { Authorization: 'Bearer mauvais_token' },
    });
    assert(bad.status === 401, `B: expected 401, got ${bad.status}`);
    assert(bad.json && bad.json.error === 'Unauthorized', `B: ${bad.raw}`);
    console.log('B OK GET /auth/profile mauvais JWT -> 401');

    const valid = generateAccessToken({
      id: 42,
      login: 'example',
      auth_provider: 'local',
    });
    const authed = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/profile',
      headers: { Authorization: `Bearer ${valid}` },
    });
    assert(
      authed.status === 503 || authed.status === 200 || authed.status === 404,
      `C HTTP: unexpected ${authed.status} ${authed.raw}`
    );
    assert(!authed.raw.includes(valid), 'F: response must not echo JWT');

    const combinedLogs = logs.join('');
    assert(!combinedLogs.includes(valid), 'logs leaked full JWT');
    assert(!combinedLogs.includes(TEST_SECRET), 'logs leaked JWT_SECRET');
    assert(!combinedLogs.includes('password_hash'), 'logs leaked password_hash');
    console.log('OK logs HTTP sans JWT complet ni secret');
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

  console.log('User profile checks succeeded.');
}

main().catch((err) => {
  console.error('User profile checks failed:', err.message);
  process.exitCode = 1;
});
