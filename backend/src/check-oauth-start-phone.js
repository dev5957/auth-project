const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const bcrypt = require('bcrypt');
const {
  startOAuthPhoneVerification,
  createPendingOauthContext,
  prepareOauthUserDraft,
  parseOauthContext,
  PENDING_PHONE_PLACEHOLDER,
} = require('./services/oauthService');

const TEST_SECRET = 'oauth-start-phone-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30442;
const OAUTH_TOKEN = 'a'.repeat(64);
const SMS_CODE = '654321';
const RAW_PHONE = '+33 6-12-34-56-78';
const NORMALIZED_PHONE = '+33612345678';

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
    ...overrides,
  };
}

function createMemoryDb({ users = [], verifications = [] } = {}) {
  const state = {
    users: users.map((user) => ({ ...user })),
    verifications: verifications.map((row, index) => ({
      id: row.id || index + 1,
      verified_at: row.verified_at ?? null,
      attempts: row.attempts ?? 0,
      ...row,
    })),
    insertedUsers: 0,
    insertedRefreshTokens: 0,
  };
  let nextVerificationId =
    state.verifications.reduce((max, row) => Math.max(max, row.id || 0), 0) + 1;

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO USERS')) {
      state.insertedUsers += 1;
      throw new Error('users must not be inserted by oauth/start-phone');
    }

    if (key.startsWith('INSERT INTO REFRESH_TOKENS')) {
      state.insertedRefreshTokens += 1;
      throw new Error('refresh tokens must not be inserted by oauth/start-phone');
    }

    if (key.startsWith('INSERT INTO PHONE_VERIFICATIONS')) {
      state.verifications.push({
        id: nextVerificationId,
        verification_token: params[0],
        phone_number: params[1],
        code_hash: params[2],
        expires_at: params[3],
        attempts: 0,
        verified_at: null,
        registration_data: params[4],
      });
      nextVerificationId += 1;
      return { rows: [], rowCount: 1 };
    }

    if (key.includes('FROM PHONE_VERIFICATIONS') && key.includes('VERIFICATION_TOKEN')) {
      const row = state.verifications.find((item) => item.verification_token === params[0]);
      return {
        rows: row
          ? [
              {
                id: row.id,
                expires_at: row.expires_at,
                verified_at: row.verified_at,
                registration_data: row.registration_data,
              },
            ]
          : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes('EXISTS') && key.includes('FROM USERS') && key.includes('PHONE_NUMBER')) {
      const taken = state.users.some((user) => user.phone_number === params[0]);
      return { rows: [{ phone_taken: taken }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE PHONE_VERIFICATIONS')) {
      const row = state.verifications.find((item) => item.id === params[4]);
      if (!row || row.verified_at) {
        return { rows: [], rowCount: 0 };
      }
      row.phone_number = params[0];
      row.code_hash = params[1];
      row.expires_at = params[2];
      row.attempts = 0;
      row.registration_data = params[3];
      return { rows: [], rowCount: 1 };
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

function captureLogs(fn) {
  const logs = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args) => {
    logs.push(args.map(String).join(' '));
  };
  console.error = (...args) => {
    logs.push(args.map(String).join(' '));
  };
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      console.log = originalLog;
      console.error = originalError;
    })
    .then((result) => ({ result, logs: logs.join('\n') }));
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
    GOOGLE_CLIENT_ID: 'oauth-start-phone-http-client-id',
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

async function startPhone(body, db, extras = {}) {
  const smsCalls = extras.smsCalls || [];
  return startOAuthPhoneVerification(body, {
    db,
    generateSmsCode: extras.generateSmsCode || (() => SMS_CODE),
    sendSms: extras.sendSms || (async (phoneNumber, message) => {
      smsCalls.push({ phoneNumber, message });
      return { skipped: false, mocked: true };
    }),
  });
}

async function main() {
  const previous = {
    DATABASE_URL: process.env.DATABASE_URL,
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN,
    DEV_LOG_SMS_CODE: process.env.DEV_LOG_SMS_CODE,
    SMS_PROVIDER: process.env.SMS_PROVIDER,
  };

  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://oauth-start-phone-test/local';
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.JWT_EXPIRES_IN = '15m';
  process.env.DEV_LOG_SMS_CODE = 'false';
  process.env.SMS_PROVIDER = 'mock';

  await expectStatus(() => startOAuthPhoneVerification({}), 400, 'oauth_verification_token is required');
  await expectStatus(
    () => startOAuthPhoneVerification({ oauth_verification_token: '   ' }),
    400,
    'oauth_verification_token is required'
  );
  await expectStatus(
    () => startOAuthPhoneVerification({ oauth_verification_token: OAUTH_TOKEN }),
    400,
    'phone_number is required'
  );
  console.log('OK champs absents -> 400');

  const missingDb = createMemoryDb();
  await expectStatus(
    () => startPhone({ oauth_verification_token: OAUTH_TOKEN, phone_number: NORMALIZED_PHONE }, missingDb),
    404,
    'Verification token not found'
  );
  console.log('OK jeton inconnu -> 404');

  const expiredDb = createMemoryDb({
    verifications: [
      {
        verification_token: OAUTH_TOKEN,
        phone_number: PENDING_PHONE_PLACEHOLDER,
        expires_at: new Date(Date.now() - 1000),
        registration_data: oauthRegistrationData(),
      },
    ],
  });
  await expectStatus(
    () => startPhone({ oauth_verification_token: OAUTH_TOKEN, phone_number: NORMALIZED_PHONE }, expiredDb),
    400,
    'Verification is no longer valid'
  );
  console.log('OK contexte OAuth expire -> 400');

  const verifiedDb = createMemoryDb({
    verifications: [
      {
        verification_token: OAUTH_TOKEN,
        phone_number: PENDING_PHONE_PLACEHOLDER,
        expires_at: new Date(Date.now() + 60_000),
        verified_at: new Date(),
        registration_data: oauthRegistrationData(),
      },
    ],
  });
  await expectStatus(
    () => startPhone({ oauth_verification_token: OAUTH_TOKEN, phone_number: NORMALIZED_PHONE }, verifiedDb),
    400,
    'Verification is no longer valid'
  );
  console.log('OK contexte deja consomme -> 400');

  const localDb = createMemoryDb({
    verifications: [
      {
        verification_token: OAUTH_TOKEN,
        phone_number: '+33600000000',
        expires_at: new Date(Date.now() + 60_000),
        registration_data: {
          email: 'local@example.com',
          login: 'local_user',
          password_hash: 'not-a-real-hash',
          phone_number: '+33600000000',
          birth_date: '1990-01-15',
        },
      },
    ],
  });
  await expectStatus(
    () => startPhone({ oauth_verification_token: OAUTH_TOKEN, phone_number: NORMALIZED_PHONE }, localDb),
    400,
    'Verification is no longer valid'
  );
  console.log('OK jeton inscription locale -> 400');

  const takenDb = createMemoryDb({
    users: [
      {
        id: 9,
        login: 'taken',
        email: 'taken@example.com',
        phone_number: NORMALIZED_PHONE,
        auth_provider: 'local',
      },
    ],
    verifications: [
      {
        verification_token: OAUTH_TOKEN,
        phone_number: PENDING_PHONE_PLACEHOLDER,
        expires_at: new Date(Date.now() + 60_000),
        registration_data: oauthRegistrationData(),
      },
    ],
  });
  await expectStatus(
    () => startPhone({ oauth_verification_token: OAUTH_TOKEN, phone_number: RAW_PHONE }, takenDb),
    409,
    'Phone number is already in use'
  );
  assert(takenDb.state.verifications[0].phone_number === PENDING_PHONE_PLACEHOLDER, 'conflict: phone not stored');
  console.log('OK telephone deja pris -> 409');

  const smsCalls = [];
  const pendingDb = createMemoryDb();
  const created = await createPendingOauthContext(
    oauthRegistrationData({ email: 'User@Example.com' }),
    { db: pendingDb }
  );
  assert(pendingDb.state.verifications[0].phone_number === PENDING_PHONE_PLACEHOLDER, 'pending: placeholder');
  const started = await startPhone(
    {
      oauth_verification_token: created.oauth_verification_token,
      phone_number: RAW_PHONE,
    },
    pendingDb,
    { smsCalls }
  );
  assert(started.message === 'Verification code generated', 'start: message');
  assert(started.oauth_verification_token === created.oauth_verification_token, 'start: same token');
  assert(!started.access_token, 'start: no access_token');
  assert(!started.refresh_token, 'start: no refresh_token');
  assert(pendingDb.state.insertedUsers === 0, 'start: no users insert');
  assert(pendingDb.state.insertedRefreshTokens === 0, 'start: no refresh insert');
  assert(pendingDb.state.users.length === 0, 'start: users table empty');

  const row = pendingDb.state.verifications[0];
  assert(row.phone_number === NORMALIZED_PHONE, `start: stored phone ${row.phone_number}`);
  assert(row.attempts === 0, 'start: attempts reset');
  assert(row.registration_data.provider === 'google', 'start: provider');
  assert(row.registration_data.provider_user_id === 'google-user-123', 'start: provider_user_id');
  assert(row.registration_data.email === 'user@example.com', 'start: email');
  assert(row.registration_data.first_name === 'Ada', 'start: first_name');
  assert(row.registration_data.last_name === 'Lovelace', 'start: last_name');
  assert(row.registration_data.phone_number === NORMALIZED_PHONE, 'start: context phone');
  assert(!row.registration_data.password_hash, 'start: no password_hash');
  assert(!row.registration_data.login, 'start: no login yet');
  assert(!row.registration_data.birth_date, 'start: no birth_date yet');
  assert(await bcrypt.compare(SMS_CODE, row.code_hash), 'start: OTP hashed with existing bcrypt mechanism');
  assert(!(await bcrypt.compare('000000', row.code_hash)), 'start: other code does not match');
  assert(smsCalls.length === 1, 'start: SMS sent once');
  assert(smsCalls[0].phoneNumber === NORMALIZED_PHONE, 'start: SMS to normalized phone');
  assert(smsCalls[0].message === `Your verification code is ${SMS_CODE}`, 'start: SMS body');

  const draft = prepareOauthUserDraft(parseOauthContext(row.registration_data, { requirePhone: true }));
  assert(draft.password_hash === null, 'draft: password_hash null');
  assert(draft.phone_verified === true, 'draft: phone_verified prepared');
  assert(draft.auth_provider === 'google', 'draft: auth_provider');
  assert(draft.provider_user_id === 'google-user-123', 'draft: provider_user_id');
  assert(draft.email === 'user@example.com', 'draft: email');
  assert(draft.phone_number === NORMALIZED_PHONE, 'draft: phone');
  console.log('OK contexte Google valide -> OTP + SMS, pas de users ni JWT');

  const logged = await captureLogs(() =>
    startPhone(
      {
        oauth_verification_token: created.oauth_verification_token,
        phone_number: NORMALIZED_PHONE,
      },
      pendingDb,
      { smsCalls: [] }
    )
  );
  assert(!logged.logs.includes(SMS_CODE), 'default logs leaked OTP');
  assert(!logged.logs.includes(created.oauth_verification_token), 'default logs leaked oauth token');
  assert(!logged.logs.includes(NORMALIZED_PHONE), 'default logs leaked phone');
  console.log('OK logs sans OTP, jeton ni telephone');

  process.env.DEV_LOG_SMS_CODE = 'true';
  const devLogged = await captureLogs(() =>
    startPhone(
      {
        oauth_verification_token: created.oauth_verification_token,
        phone_number: NORMALIZED_PHONE,
      },
      pendingDb,
      { smsCalls: [] }
    )
  );
  assert(devLogged.logs.includes(SMS_CODE), 'DEV_LOG_SMS_CODE should log OTP');
  assert(!devLogged.logs.includes(created.oauth_verification_token), 'DEV logs leaked oauth token');
  process.env.DEV_LOG_SMS_CODE = 'false';
  console.log('OK DEV_LOG_SMS_CODE=true logue uniquement le code');

  const previousDbUrl = process.env.DATABASE_URL;
  try {
    delete process.env.DATABASE_URL;
    await expectStatus(
      () =>
        startOAuthPhoneVerification({
          oauth_verification_token: OAUTH_TOKEN,
          phone_number: NORMALIZED_PHONE,
        }),
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
      urlPath: '/auth/oauth/start-phone',
      body: {},
    });
    assert(missing.status === 400, `HTTP missing: ${missing.status} ${missing.raw}`);
    assert(
      missing.json && missing.json.error === 'oauth_verification_token is required',
      'HTTP missing message'
    );

    const noPhone = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/oauth/start-phone',
      body: { oauth_verification_token: OAUTH_TOKEN },
    });
    assert(noPhone.status === 400, `HTTP no phone: ${noPhone.status} ${noPhone.raw}`);
    assert(noPhone.json && noPhone.json.error === 'phone_number is required', 'HTTP phone message');

    const unknown = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/oauth/start-phone',
      body: { oauth_verification_token: OAUTH_TOKEN, phone_number: NORMALIZED_PHONE },
    });
    assert(unknown.status === 503 || unknown.status === 404, `HTTP unknown: ${unknown.status} ${unknown.raw}`);
    assert(!unknown.raw.includes(OAUTH_TOKEN), 'HTTP response leaked oauth token');
    assert(!unknown.raw.includes(SMS_CODE), 'HTTP response leaked OTP');
    assert(!unknown.json || unknown.json.access_token == null, 'HTTP must not issue access_token');
    assert(!unknown.json || unknown.json.refresh_token == null, 'HTTP must not issue refresh_token');

    const combinedLogs = logs.join('');
    assert(!combinedLogs.includes(OAUTH_TOKEN), 'HTTP logs leaked oauth token');
    assert(!combinedLogs.includes(SMS_CODE), 'HTTP logs leaked OTP');
    console.log('OK HTTP POST /auth/oauth/start-phone et logs propres');
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

  console.log('OAuth start-phone checks succeeded.');
}

main().catch((err) => {
  console.error('OAuth start-phone checks failed:', err.message);
  process.exitCode = 1;
});
