const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const express = require('express');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const { parseUserSearchQuery } = require('./validators/userSearchFields');
const { searchUsers } = require('./services/userSearchService');
const { createRateLimiter, USER_SEARCH_RATE_LIMIT } = require('./middleware/rateLimit');
const { requireAuth } = require('./middleware/authMiddleware');
const { search } = require('./controllers/userSearchController');
const pool = require('./db');
const errorHandler = require('./middleware/errorHandler');
const userRoutes = require('./routes/users');
const communityRoutes = require('./routes/communities');

const TEST_SECRET = 'user-search-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30470;
const HTTP_PORT = 30471;
const RATE_PORT = 30472;
const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;

const PRIVATE_FIELDS = [
  'phone_number',
  'email',
  'password_hash',
  'birth_date',
  'auth_provider',
  'provider_user_id',
  'first_name',
  'last_name',
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function expectAppError(fn, statusCode, message) {
  try {
    fn();
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    assert(err.message === message, `unexpected message: ${err.message}`);
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function assertMinimalItems(payload) {
  assert(payload && Array.isArray(payload.items), 'items array required');
  for (const item of payload.items) {
    const keys = Object.keys(item).sort();
    assert(keys.join(',') === 'login,user_id', `unexpected keys ${keys}`);
    assert(item.user_id != null && item.login, 'hit identity');
    const blob = JSON.stringify(item);
    for (const field of PRIVATE_FIELDS) {
      assert(!blob.includes(field), `leaked ${field}`);
    }
  }
}

function createUserMemory() {
  const users = [
    {
      id: 11,
      login: 'joe5',
      phone_number: '+33612345678',
      phone_verified: true,
      email: 'joe5@example.com',
      password_hash: 'hash-must-never-leak',
      birth_date: '2000-01-01',
      auth_provider: 'local',
      provider_user_id: 'prov-11',
      first_name: 'Joe',
      last_name: 'Five',
    },
    {
      id: 12,
      login: 'unverified',
      phone_number: '+33600000000',
      phone_verified: false,
      email: 'uv@example.com',
      password_hash: 'hash-must-never-leak',
      birth_date: '2001-01-01',
      auth_provider: 'local',
      provider_user_id: null,
      first_name: 'No',
      last_name: 'Verify',
    },
  ];
  const queries = [];

  async function query(sql, params = []) {
    const key = sqlKey(sql);
    queries.push({ sql, params, key });

    if (key.includes('FROM USERS') && key.includes('WHERE LOGIN = $1')) {
      assert(!key.includes('ILIKE'), 'login search must be exact');
      assert(params.length === 1, 'login search uses $1');
      const row = users.find((user) => user.login === params[0]);
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [{ id: row.id, login: row.login }], rowCount: 1 };
    }

    if (
      key.includes('FROM USERS') &&
      key.includes('WHERE PHONE_NUMBER = $1') &&
      key.includes('PHONE_VERIFIED = TRUE')
    ) {
      assert(!key.includes('ILIKE'), 'phone search must be exact');
      assert(params.length === 1, 'phone search uses $1');
      const row = users.find(
        (user) => user.phone_number === params[0] && user.phone_verified === true
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [{ id: row.id, login: row.login }], rowCount: 1 };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  return { users, queries, query };
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
          resolve({ status: res.statusCode, json, raw, headers: res.headers });
        });
      }
    );
    req.on('error', reject);
    req.end();
  });
}

function startIndexServer(port) {
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
    DATABASE_URL: '',
  };
  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: path.join(__dirname, '..'),
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const onData = (chunk) => logs.push(chunk.toString('utf8'));
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
    child.on('exit', () => resolve());
    child.kill('SIGTERM');
    setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch (_) {
        // ignore
      }
    }, 1000).unref();
  });
}

function captureLogs(fn) {
  const lines = [];
  const origLog = console.log;
  const origError = console.error;
  const origWarn = console.warn;
  const write = (...args) => {
    lines.push(args.map(String).join(' '));
  };
  console.log = write;
  console.error = write;
  console.warn = write;
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      console.log = origLog;
      console.error = origError;
      console.warn = origWarn;
    })
    .then((result) => ({ result, lines }));
}

async function main() {
  const previous = {
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    DATABASE_URL: process.env.DATABASE_URL,
  };
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://user-search-test/local';

  expectAppError(() => parseUserSearchQuery({}), 400, 'login or phone is required');
  expectAppError(
    () => parseUserSearchQuery({ login: 'a', phone: 'b' }),
    400,
    'login and phone cannot both be set'
  );
  expectAppError(() => parseUserSearchQuery({ login: '   ' }), 400, 'login is required');
  expectAppError(() => parseUserSearchQuery({ login: 'x'.repeat(65) }), 400, 'login is invalid');
  expectAppError(() => parseUserSearchQuery({ phone: '   ' }), 400, 'phone_number is required');
  const loginParsed = parseUserSearchQuery({ login: '  JOE5  ' });
  assert(loginParsed.kind === 'login' && loginParsed.login === 'joe5', 'login normalized');
  const phoneParsed = parseUserSearchQuery({ phone: ' +33 6 12-34-56-78 ' });
  assert(phoneParsed.kind === 'phone' && phoneParsed.phone === '+33612345678', 'phone normalized');
  console.log('A OK validators login/phone exclusive exact');

  assert(USER_SEARCH_RATE_LIMIT.max === 20, 'user search max 20');
  assert(USER_SEARCH_RATE_LIMIT.windowMs === FIFTEEN_MINUTES_MS, 'user search window 15 min');
  console.log('B OK dedicated rate limit 20 / 15 min');

  const db = createUserMemory();
  const foundLogin = await searchUsers({ login: 'JOE5' }, { db });
  assert(foundLogin.items.length === 1, 'login hit');
  assert(foundLogin.items[0].user_id === 11 && foundLogin.items[0].login === 'joe5', 'login identity');
  assertMinimalItems(foundLogin);
  const loginSql = db.queries[db.queries.length - 1];
  assert(loginSql.params[0] === 'joe5', 'login param normalized');
  assert(sqlKey(loginSql.sql).includes('LOGIN = $1'), 'exact login equality');
  assert(!sqlKey(loginSql.sql).includes('ILIKE'), 'no ilike login');

  const missingLogin = await searchUsers({ login: 'unknown' }, { db });
  assert(missingLogin.items.length === 0, 'unknown login empty');

  const partial = await searchUsers({ login: 'joe' }, { db });
  assert(partial.items.length === 0, 'partial login empty');

  const foundPhone = await searchUsers({ phone: '+33 6 12 34 56 78' }, { db });
  assert(foundPhone.items.length === 1 && foundPhone.items[0].login === 'joe5', 'verified phone hit');
  assertMinimalItems(foundPhone);
  const phoneSql = db.queries[db.queries.length - 1];
  assert(phoneSql.params[0] === '+33612345678', 'phone param normalized');
  assert(sqlKey(phoneSql.sql).includes('PHONE_VERIFIED = TRUE'), 'verified filter');
  assert(sqlKey(phoneSql.sql).includes('PHONE_NUMBER = $1'), 'exact phone equality');

  const unverified = await searchUsers({ phone: '+33600000000' }, { db });
  assert(unverified.items.length === 0, 'unverified empty');
  const unknownPhone = await searchUsers({ phone: '+33699999999' }, { db });
  assert(unknownPhone.items.length === 0, 'unknown phone empty');
  console.log('C OK service exact login/phone, empty unknowns, verified only');

  const origQuery = pool.query;
  pool.query = (sql, params) => db.query(sql, params);

  const app = express();
  app.use(express.json({ limit: '32kb' }));
  app.use('/users', userRoutes);
  app.use('/communities', communityRoutes);
  app.use(errorHandler);
  const server = await new Promise((resolve) => {
    const httpServer = app.listen(HTTP_PORT, '127.0.0.1', () => resolve(httpServer));
  });

  try {
    const token = generateAccessToken({
      id: 11,
      login: 'joe5',
      auth_provider: 'local',
    });
    const auth = { Authorization: `Bearer ${token}` };

    const unauth = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/users/search?login=joe5',
    });
    assert(unauth.status === 401, `unauth ${unauth.status}`);
    assert(unauth.json && unauth.json.error === 'Unauthorized', unauth.raw);

    const none = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/users/search',
      headers: auth,
    });
    assert(none.status === 400, `none ${none.status}`);
    assert(none.json.error === 'login or phone is required', none.raw);

    const both = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/users/search?login=joe5&phone=%2B33612345678',
      headers: auth,
    });
    assert(both.status === 400, `both ${both.status}`);
    assert(both.json.error === 'login and phone cannot both be set', both.raw);

    const emptyLogin = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/users/search?login=%20%20',
      headers: auth,
    });
    assert(emptyLogin.status === 400, `empty login ${emptyLogin.status}`);
    assert(emptyLogin.json.error === 'login is required', emptyLogin.raw);

    const longLogin = 'a'.repeat(65);
    const tooLong = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/users/search?login=${longLogin}`,
      headers: auth,
    });
    assert(tooLong.status === 400, `too long ${tooLong.status}`);
    assert(tooLong.json.error === 'login is invalid', tooLong.raw);
    assert(!tooLong.raw.includes(longLogin), 'error leaked long login');

    const secretPhone = '+33612345678';
    const { result: phoneCaptured, lines } = await captureLogs(async () => {
      return httpRequest({
        port: HTTP_PORT,
        method: 'GET',
        urlPath: `/users/search?phone=${encodeURIComponent('+33 6 12-34-56-78')}`,
        headers: auth,
      });
    });
    assert(phoneCaptured.status === 200, `phone http ${phoneCaptured.status}`);
    assertMinimalItems(phoneCaptured.json);
    assert(phoneCaptured.json.items[0].login === 'joe5', 'phone http login');
    const joinedLogs = lines.join('\n');
    assert(!joinedLogs.includes(secretPhone), 'logs leaked phone');
    assert(!phoneCaptured.raw.includes(secretPhone), 'response leaked phone');
    for (const field of PRIVATE_FIELDS) {
      assert(!phoneCaptured.raw.includes(field), `http leaked ${field}`);
    }

    const loginHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/users/search?login=JOE5',
      headers: auth,
    });
    assert(loginHttp.status === 200, `login http ${loginHttp.status}`);
    assert(loginHttp.json.items.length === 1, 'login http one hit');
    assertMinimalItems(loginHttp.json);

    const unknownHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/users/search?login=nobody',
      headers: auth,
    });
    assert(unknownHttp.status === 200 && unknownHttp.json.items.length === 0, 'unknown http empty');

    const partialHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/users/search?login=joe',
      headers: auth,
    });
    assert(partialHttp.status === 200 && partialHttp.json.items.length === 0, 'partial http empty');

    const unverifiedHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/users/search?phone=${encodeURIComponent('+33600000000')}`,
      headers: auth,
    });
    assert(unverifiedHttp.status === 200 && unverifiedHttp.json.items.length === 0, 'unverified http empty');

    const communityUnauth = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/communities',
    });
    assert(communityUnauth.status === 401, `community unauth ${communityUnauth.status}`);
    console.log('D OK HTTP auth/validation/search/privacy');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }

  const isolatedLimiter = createRateLimiter({
    windowMs: USER_SEARCH_RATE_LIMIT.windowMs,
    max: USER_SEARCH_RATE_LIMIT.max,
  });
  const isolated = express();
  isolated.use(requireAuth);
  isolated.get('/users/search', isolatedLimiter, search);
  isolated.use(errorHandler);
  const rateServer = await new Promise((resolve) => {
    const httpServer = isolated.listen(RATE_PORT, '127.0.0.1', () => resolve(httpServer));
  });

  try {
    const token = generateAccessToken({
      id: 11,
      login: 'joe5',
      auth_provider: 'local',
    });
    const auth = { Authorization: `Bearer ${token}` };
    let last = null;
    for (let i = 0; i < 21; i += 1) {
      last = await httpRequest({
        port: RATE_PORT,
        method: 'GET',
        urlPath: '/users/search?login=nobody',
        headers: auth,
      });
      if (i < 20) {
        assert(last.status !== 429, `request ${i + 1} unexpected 429`);
      }
    }
    assert(last.status === 429, `21st status ${last.status}`);
    assert(last.headers['retry-after'], '21st missing Retry-After');
    assert(
      last.json && last.json.error === 'Too many requests' && Object.keys(last.json).length === 1,
      `21st body ${last.raw}`
    );
    console.log('D2 OK isolated rate limit 20 pass, 21st 429');
  } finally {
    await new Promise((resolve) => rateServer.close(resolve));
    pool.query = origQuery;
  }

  const { child, logs } = startIndexServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);
    const unauthIndex = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/users/search?login=joe5',
    });
    assert(unauthIndex.status === 401, `index unauth ${unauthIndex.status}`);
    const communityIndex = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/communities/search?q=JardinSecret',
    });
    assert(communityIndex.status === 401, `index community ${communityIndex.status}`);
    const joined = logs.join('');
    assert(!joined.includes('+336'), 'index logs leaked phone fragment');
    console.log('E OK index mounts /users/search, communities unchanged 401');
  } finally {
    await stopServer(child);
    process.env.JWT_SECRET = previous.JWT_SECRET;
    process.env.JWT_ISSUER = previous.JWT_ISSUER;
    process.env.JWT_AUDIENCE = previous.JWT_AUDIENCE;
    if (!previous.DATABASE_URL) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previous.DATABASE_URL;
    }
  }
}

main()
  .then(() => {
    console.log('User search check succeeded (mock, sans Neon).');
  })
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  });
