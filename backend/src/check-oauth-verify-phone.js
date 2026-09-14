const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { verifyOAuthPhoneAndCreateUser } = require('./services/oauthService');

const TEST_SECRET = 'oauth-verify-phone-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30443;
const OAUTH_TOKEN = 'b'.repeat(64);
const SMS_CODE = '123456';
const WRONG_CODE = '000000';
const PHONE = '+33612345678';
const LOGIN = 'Ada_User';
const NORMALIZED_LOGIN = 'ada_user';
const BIRTH_DATE = '1990-01-15';

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

function oauthRegistrationData(overrides = {}) {
  return {
    provider: 'google',
    provider_user_id: 'google-user-123',
    email: 'user@example.com',
    first_name: 'Ada',
    last_name: 'Lovelace',
    phone_number: PHONE,
    ...overrides,
  };
}

function verifyBody(overrides = {}) {
  return {
    oauth_verification_token: OAUTH_TOKEN,
    code: SMS_CODE,
    birth_date: BIRTH_DATE,
    login: LOGIN,
    ...overrides,
  };
}

function createMemoryDb({ users = [], verifications = [], tokens = [] } = {}) {
  const state = {
    users: users.map((user) => ({ ...user })),
    verifications: verifications.map((row, index) => ({
      id: row.id || index + 1,
      verified_at: row.verified_at ?? null,
      attempts: row.attempts ?? 0,
      ...row,
    })),
    tokens: tokens.map((token) => ({ ...token })),
    deletedVerifications: 0,
  };
  let nextUserId = state.users.reduce((max, user) => Math.max(max, user.id || 0), 0) + 1;
  let nextTokenId = state.tokens.reduce((max, token) => Math.max(max, token.id || 0), 0) + 1;

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('DELETE FROM PHONE_VERIFICATIONS')) {
      state.deletedVerifications += 1;
      throw new Error('phone_verifications must not be deleted after OAuth verify');
    }

    if (key.includes('FROM PHONE_VERIFICATIONS') && key.includes('VERIFICATION_TOKEN')) {
      const row = state.verifications.find((item) => item.verification_token === params[0]);
      return {
        rows: row
          ? [
              {
                id: row.id,
                code_hash: row.code_hash,
                expires_at: row.expires_at,
                attempts: row.attempts,
                verified_at: row.verified_at,
                registration_data: { ...row.registration_data },
              },
            ]
          : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes('UPDATE PHONE_VERIFICATIONS') && key.includes('ATTEMPTS')) {
      const row = state.verifications.find((item) => item.id === params[1]);
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.attempts = params[0];
      return { rows: [], rowCount: 1 };
    }

    if (key.includes('UPDATE PHONE_VERIFICATIONS') && key.includes('VERIFIED_AT')) {
      const row = state.verifications.find((item) => item.id === params[0]);
      if (!row || row.verified_at) {
        return { rows: [], rowCount: 0 };
      }
      row.verified_at = new Date();
      return { rows: [], rowCount: 1 };
    }

    if (key.includes('EMAIL_PROVIDER') && key.includes('LOGIN_TAKEN')) {
      const emailUser = state.users.find((user) => user.email === params[0]);
      const loginTaken = state.users.some((user) => user.login === params[1]);
      const phoneTaken = state.users.some((user) => user.phone_number === params[2]);
      const providerTaken = state.users.some(
        (user) => user.auth_provider === params[3] && user.provider_user_id === params[4]
      );
      return {
        rows: [
          {
            email_provider: emailUser ? emailUser.auth_provider : null,
            login_taken: loginTaken,
            phone_taken: phoneTaken,
            provider_taken: providerTaken,
          },
        ],
        rowCount: 1,
      };
    }

    if (key.startsWith('INSERT INTO USERS')) {
      assert(key.includes('PASSWORD_HASH'), 'insert must mention password_hash');
      assert(key.includes(', NULL,'), 'password_hash must be SQL NULL');
      assert(!params.includes('stored-password-hash'), 'must not persist a password hash');
      const user = {
        id: nextUserId,
        email: params[0],
        birth_date: params[1],
        phone_number: params[2],
        phone_verified: true,
        login: params[3],
        password_hash: null,
        auth_provider: params[4],
        provider_user_id: params[5],
        first_name: params[6],
        last_name: params[7],
      };
      state.users.push(user);
      nextUserId += 1;
      return {
        rows: [
          {
            id: user.id,
            login: user.login,
            email: user.email,
            auth_provider: user.auth_provider,
            provider_user_id: user.provider_user_id,
            phone_verified: user.phone_verified,
            password_hash: user.password_hash,
          },
        ],
        rowCount: 1,
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

async function pendingVerification(overrides = {}) {
  return {
    verification_token: OAUTH_TOKEN,
    phone_number: PHONE,
    code_hash: await bcrypt.hash(SMS_CODE, 10),
    expires_at: new Date(Date.now() + 60_000),
    attempts: 0,
    verified_at: null,
    registration_data: oauthRegistrationData(),
    ...overrides,
  };
}

function httpRequest({ port, method, urlPath, body }) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers: data
          ? {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(data),
            }
          : {},
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
    DEV_LOG_SMS_CODE: 'false',
    SMS_PROVIDER: 'mock',
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
  };

  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://oauth-verify-phone-test/local';
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.JWT_EXPIRES_IN = '15m';

  await expectStatus(() => verifyOAuthPhoneAndCreateUser({}), 400, 'oauth_verification_token is required');
  await expectStatus(
    () => verifyOAuthPhoneAndCreateUser({ oauth_verification_token: OAUTH_TOKEN }),
    400,
    'code is required'
  );
  await expectStatus(
    () => verifyOAuthPhoneAndCreateUser({ oauth_verification_token: OAUTH_TOKEN, code: SMS_CODE }),
    400,
    'birth_date is required'
  );
  await expectStatus(
    () =>
      verifyOAuthPhoneAndCreateUser({
        oauth_verification_token: OAUTH_TOKEN,
        code: SMS_CODE,
        birth_date: BIRTH_DATE,
      }),
    400,
    'login is required'
  );
  console.log('OK champs absents -> 400');

  const invalidDb = createMemoryDb({
    verifications: [await pendingVerification()],
  });
  await expectStatus(
    () => verifyOAuthPhoneAndCreateUser(verifyBody({ code: WRONG_CODE }), { db: invalidDb }),
    400,
    'Invalid verification code'
  );
  assert(invalidDb.state.verifications[0].attempts === 1, 'invalid OTP increments attempts');
  assert(invalidDb.state.users.length === 0, 'invalid OTP must not create users');
  assert(invalidDb.state.tokens.length === 0, 'invalid OTP must not issue refresh');
  console.log('OK OTP invalide -> 400, pas de users');

  const loginDb = createMemoryDb({
    users: [
      {
        id: 4,
        login: NORMALIZED_LOGIN,
        email: 'other@example.com',
        phone_number: '+33600000001',
        auth_provider: 'local',
        provider_user_id: null,
        password_hash: 'local-hash',
      },
    ],
    verifications: [await pendingVerification()],
  });
  await expectStatus(
    () => verifyOAuthPhoneAndCreateUser(verifyBody(), { db: loginDb }),
    409,
    'Login is already in use'
  );
  assert(loginDb.state.users.length === 1, 'login taken: no extra user');
  assert(loginDb.state.users[0].password_hash === 'local-hash', 'login taken: existing hash untouched');
  console.log('OK login deja utilise -> 409');

  const phoneDb = createMemoryDb({
    users: [
      {
        id: 5,
        login: 'someone_else',
        email: 'other@example.com',
        phone_number: PHONE,
        auth_provider: 'local',
        provider_user_id: null,
        password_hash: 'local-hash',
      },
    ],
    verifications: [await pendingVerification()],
  });
  await expectStatus(
    () => verifyOAuthPhoneAndCreateUser(verifyBody(), { db: phoneDb }),
    409,
    'Phone number is already in use'
  );
  assert(phoneDb.state.users.length === 1, 'phone taken: no extra user');
  console.log('OK telephone deja utilise -> 409');

  const successDb = createMemoryDb({
    verifications: [await pendingVerification()],
  });
  const created = await verifyOAuthPhoneAndCreateUser(verifyBody(), { db: successDb });
  assert(created.message === 'Account created', 'google: message');
  assert(typeof created.access_token === 'string' && created.access_token.length > 20, 'google: access_token');
  assert(typeof created.refresh_token === 'string' && created.refresh_token.length > 20, 'google: refresh_token');
  assert(successDb.state.users.length === 1, 'google: one user');
  const user = successDb.state.users[0];
  assert(user.auth_provider === 'google', 'google: auth_provider');
  assert(user.provider_user_id === 'google-user-123', 'google: provider_user_id');
  assert(user.password_hash === null, 'google: password_hash NULL');
  assert(user.phone_verified === true, 'google: phone_verified');
  assert(user.login === NORMALIZED_LOGIN, 'google: login normalized');
  assert(user.email === 'user@example.com', 'google: email');
  assert(user.phone_number === PHONE, 'google: phone');
  assert(user.birth_date === BIRTH_DATE, 'google: birth_date from request');
  assert(user.first_name === 'Ada', 'google: first_name');
  assert(user.last_name === 'Lovelace', 'google: last_name');
  assert(successDb.state.verifications[0].verified_at, 'google: verification consumed');
  assert(successDb.state.deletedVerifications === 0, 'google: verification row kept');
  assert(successDb.state.tokens.length === 1, 'google: refresh stored');
  const payload = jwt.verify(created.access_token, TEST_SECRET, {
    algorithms: ['HS256'],
    issuer: TEST_ISSUER,
    audience: TEST_AUDIENCE,
  });
  assert(payload.userId === user.id, 'google: JWT userId');
  assert(payload.login === NORMALIZED_LOGIN, 'google: JWT login');
  assert(payload.auth_provider === 'google', 'google: JWT auth_provider');
  console.log('OK OTP valide / creation Google -> users + session, password_hash NULL');

  await expectStatus(
    () => verifyOAuthPhoneAndCreateUser(verifyBody(), { db: successDb }),
    400,
    'Verification is no longer valid'
  );
  console.log('OK jeton deja consomme -> 400');

  const { child, logs } = startTestServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);

    const missing = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/oauth/verify-phone',
      body: {},
    });
    assert(missing.status === 400, `HTTP missing: ${missing.status} ${missing.raw}`);
    assert(
      missing.json && missing.json.error === 'oauth_verification_token is required',
      'HTTP missing message'
    );

    const noCode = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/oauth/verify-phone',
      body: { oauth_verification_token: OAUTH_TOKEN, birth_date: BIRTH_DATE, login: LOGIN },
    });
    assert(noCode.status === 400, `HTTP no code: ${noCode.status} ${noCode.raw}`);
    assert(noCode.json && noCode.json.error === 'code is required', 'HTTP code message');
    assert(!noCode.raw.includes(SMS_CODE), 'HTTP response leaked OTP');

    const unknown = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/oauth/verify-phone',
      body: verifyBody(),
    });
    assert(unknown.status === 503 || unknown.status === 404, `HTTP unknown: ${unknown.status} ${unknown.raw}`);
    assert(!unknown.raw.includes(OAUTH_TOKEN), 'HTTP response leaked oauth token');
    assert(!unknown.raw.includes(SMS_CODE), 'HTTP response leaked OTP');

    const combinedLogs = logs.join('');
    assert(!combinedLogs.includes(OAUTH_TOKEN), 'HTTP logs leaked oauth token');
    assert(!combinedLogs.includes(SMS_CODE), 'HTTP logs leaked OTP');
    console.log('OK HTTP POST /auth/oauth/verify-phone et logs propres');
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

  console.log('OAuth verify-phone checks succeeded.');
}

main().catch((err) => {
  console.error('OAuth verify-phone checks failed:', err.message);
  process.exitCode = 1;
});
