const http = require('http');
const express = require('express');
const AppError = require('./errors/AppError');

const TEST_SECRET = 'google-oauth-flow-test-secret';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30444;
const ID_TOKEN = 'simulated-google-id-token-not-from-google-cloud';
const PHONE = '+33610000001';
const CONFLICT_PHONE = '+33610000002';
const LOGIN = 'google_tester';
const BIRTH_DATE = '1992-03-04';

const GOOGLE_IDENTITY = {
  provider: 'google',
  provider_user_id: 'google-test-user-001',
  email: 'test.google@example.com',
  first_name: 'Google',
  last_name: 'Tester',
};

process.env.PORT = String(TEST_PORT);
process.env.JWT_SECRET = TEST_SECRET;
process.env.JWT_ISSUER = TEST_ISSUER;
process.env.JWT_AUDIENCE = TEST_AUDIENCE;
process.env.JWT_EXPIRES_IN = '15m';
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://google-oauth-flow-test/local';
process.env.SMS_PROVIDER = 'mock';
process.env.DEV_LOG_SMS_CODE = 'true';
process.env.GOOGLE_CLIENT_ID = 'google-oauth-flow-test-client-id';

const stats = {
  usersCreated: 0,
  refreshCreated: 0,
  refreshRevoked: 0,
};

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function createFlowDb() {
  const state = {
    users: [],
    tokens: [],
    verifications: [],
  };
  let nextUserId = 1;
  let nextTokenId = 1;
  let nextVerificationId = 1;

  function reset(seed = {}) {
    state.users = (seed.users || []).map((user) => ({ ...user }));
    state.tokens = (seed.tokens || []).map((token) => ({ ...token }));
    state.verifications = (seed.verifications || []).map((row, index) => ({
      id: row.id || index + 1,
      verified_at: row.verified_at ?? null,
      attempts: row.attempts ?? 0,
      ...row,
    }));
    nextUserId = state.users.reduce((max, user) => Math.max(max, user.id || 0), 0) + 1;
    nextTokenId = state.tokens.reduce((max, token) => Math.max(max, token.id || 0), 0) + 1;
    nextVerificationId =
      state.verifications.reduce((max, row) => Math.max(max, row.id || 0), 0) + 1;
  }

  function revokeToken(token, reason) {
    if (!token || token.revoked_at) {
      return 0;
    }
    token.revoked_at = new Date();
    token.revoked_reason = reason;
    stats.refreshRevoked += 1;
    return 1;
  }

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('DELETE FROM PHONE_VERIFICATIONS')) {
      throw new Error('phone_verifications must not be deleted');
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
                registration_data: row.registration_data ? { ...row.registration_data } : null,
              },
            ]
          : [],
        rowCount: row ? 1 : 0,
      };
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

    if (key.startsWith('UPDATE PHONE_VERIFICATIONS') && key.includes('REGISTRATION_DATA')) {
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

    if (key.startsWith('UPDATE PHONE_VERIFICATIONS') && key.includes('ATTEMPTS')) {
      const row = state.verifications.find((item) => item.id === params[1]);
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.attempts = params[0];
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('UPDATE PHONE_VERIFICATIONS') && key.includes('VERIFIED_AT')) {
      const row = state.verifications.find((item) => item.id === params[0]);
      if (!row || row.verified_at) {
        return { rows: [], rowCount: 0 };
      }
      row.verified_at = new Date();
      return { rows: [], rowCount: 1 };
    }

    if (key.includes('EMAIL_PROVIDER') && key.includes('LOGIN_TAKEN')) {
      const emailUser = state.users.find((user) => user.email === params[0]);
      return {
        rows: [
          {
            email_provider: emailUser ? emailUser.auth_provider : null,
            login_taken: state.users.some((user) => user.login === params[1]),
            phone_taken: state.users.some((user) => user.phone_number === params[2]),
            provider_taken: state.users.some(
              (user) => user.auth_provider === params[3] && user.provider_user_id === params[4]
            ),
          },
        ],
        rowCount: 1,
      };
    }

    if (key.includes('FROM USERS') && key.includes("AUTH_PROVIDER = 'GOOGLE'") && key.includes('PROVIDER_USER_ID')) {
      const row = state.users.find(
        (user) => user.auth_provider === 'google' && user.provider_user_id === params[0]
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('EXISTS') && key.includes('FROM USERS') && key.includes('PHONE_NUMBER')) {
      const taken = state.users.some((user) => user.phone_number === params[0]);
      return { rows: [{ phone_taken: taken }], rowCount: 1 };
    }

    if (key.includes('FROM USERS') && key.includes('WHERE EMAIL')) {
      const row = state.users.find((user) => user.email === params[0]);
      return {
        rows: row ? [{ auth_provider: row.auth_provider }] : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes('FROM USERS') && key.includes('WHERE ID')) {
      const row = state.users.find((user) => user.id === params[0]);
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('INSERT INTO USERS')) {
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
      stats.usersCreated += 1;
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

    if (key.includes('FROM REFRESH_TOKENS') && key.includes('TOKEN_HASH')) {
      const row = state.tokens.find((token) => token.token_hash === params[0]);
      return {
        rows: row
          ? [{ id: row.id, user_id: row.user_id, expires_at: row.expires_at, revoked_at: row.revoked_at }]
          : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes('FROM REFRESH_TOKENS') && key.includes('USER_ID')) {
      const rows = state.tokens.filter(
        (token) =>
          token.user_id === params[0] &&
          token.revoked_at == null &&
          (!token.expires_at || new Date(token.expires_at).getTime() > Date.now())
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
      stats.refreshCreated += 1;
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('UPDATE REFRESH_TOKENS') && key.includes('USER_ID')) {
      let count = 0;
      for (const token of state.tokens) {
        if (token.user_id === params[0] && token.revoked_at == null) {
          count += revokeToken(token, 'user');
        }
      }
      return { rows: [], rowCount: count };
    }

    if (key.startsWith('UPDATE REFRESH_TOKENS') && key.includes('ANY(')) {
      const ids = params[0] || [];
      let count = 0;
      for (const token of state.tokens) {
        if (ids.includes(token.id) && token.revoked_at == null) {
          count += revokeToken(token, 'overflow');
        }
      }
      return { rows: [], rowCount: count };
    }

    if (key.startsWith('UPDATE REFRESH_TOKENS')) {
      const row = state.tokens.find((token) => token.id === params[0]);
      const count = revokeToken(row, 'id');
      return { rows: [], rowCount: count };
    }

    throw new Error(`unexpected query: ${sql}`);
  }

  return {
    state,
    reset,
    query,
    async connect() {
      return {
        query,
        release() {},
      };
    },
  };
}

const flowDb = createFlowDb();
const dbPath = require.resolve('./db');
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: flowDb,
};

const googleAuthService = require('./services/googleAuthService');
googleAuthService.verifyGoogleIdToken = async (idToken) => {
  if (typeof idToken !== 'string' || idToken.trim() === '') {
    throw new AppError(400, 'id_token is required');
  }
  return {
    provider_user_id: GOOGLE_IDENTITY.provider_user_id,
    email: GOOGLE_IDENTITY.email,
    first_name: GOOGLE_IDENTITY.first_name,
    last_name: GOOGLE_IDENTITY.last_name,
  };
};

const authRoutes = require('./routes/auth');
const errorHandler = require('./middleware/errorHandler');
const smsService = require('./services/smsService');

const smsCalls = [];
const originalSendSms = smsService.sendSms;
smsService.sendSms = async (...args) => {
  smsCalls.push({ phoneNumber: args[0], message: args[1] });
  return originalSendSms(...args);
};

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

let clientIp = '203.0.113.10';

function httpRequest({ method, urlPath, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: TEST_PORT,
        path: urlPath,
        method,
        headers: {
          ...(data
            ? {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
              }
            : {}),
          'X-Forwarded-For': clientIp,
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

async function withOtpCapture(fn) {
  const codes = [];
  const originalLog = console.log;
  console.log = (...args) => {
    const text = args.map(String).join(' ');
    const match = text.match(/\[DEV\] SMS verification code:\s*(\d{6})/);
    if (match) {
      codes.push(match[1]);
      return;
    }
    originalLog.apply(console, args);
  };
  try {
    const result = await fn();
    return { result, code: codes[0] || null };
  } finally {
    console.log = originalLog;
  }
}

async function googleStart() {
  return httpRequest({
    method: 'POST',
    urlPath: '/auth/google/start',
    body: { id_token: ID_TOKEN },
  });
}

async function startPhone(body) {
  smsCalls.length = 0;
  return withOtpCapture(() =>
    httpRequest({
      method: 'POST',
      urlPath: '/auth/oauth/start-phone',
      body,
    })
  );
}

async function verifyPhone(body) {
  return httpRequest({
    method: 'POST',
    urlPath: '/auth/oauth/verify-phone',
    body,
  });
}

async function beginOauthToSms(phoneNumber = PHONE) {
  const started = await googleStart();
  assert(started.status === 200, `google/start: ${started.status} ${started.raw}`);
  assert(started.json && started.json.oauth_verification_token, 'oauth_verification_token missing');
  const token = started.json.oauth_verification_token;
  const phone = await startPhone({
    oauth_verification_token: token,
    phone_number: phoneNumber,
  });
  assert(phone.result.status === 200, `oauth/start-phone: ${phone.result.status} ${phone.result.raw}`);
  assert(phone.code, 'OTP was not captured');
  return { token, code: phone.code };
}

function printReport(results) {
  const passed = results.filter((item) => item.ok);
  const failed = results.filter((item) => !item.ok);
  const activeRefresh = flowDb.state.tokens.filter((token) => token.revoked_at == null).length;
  const revokedRefresh = flowDb.state.tokens.filter((token) => token.revoked_at != null).length;

  console.log('');
  console.log('=== Rapport Google OAuth (tests fonctionnels internes) ===');
  console.log(`Tests réussis : ${passed.length}`);
  for (const item of passed) {
    console.log(`  - ${item.name}`);
  }
  console.log(`Tests échoués : ${failed.length}`);
  for (const item of failed) {
    console.log(`  - ${item.name}: ${item.error}`);
  }
  console.log(`Utilisateurs créés (INSERT users) : ${stats.usersCreated}`);
  console.log(`refresh_tokens créés : ${stats.refreshCreated}`);
  console.log(`refresh_tokens révoqués : ${stats.refreshRevoked}`);
  console.log(`refresh_tokens actifs en fin de suite : ${activeRefresh}`);
  console.log(`refresh_tokens révoqués encore en base mémoire : ${revokedRefresh}`);
  console.log('Google Cloud réel : non utilisé (identité simulée).');
}

async function main() {
  const app = express();
  app.set('trust proxy', true);
  app.use(express.json({ limit: '32kb' }));
  app.use('/auth', authRoutes);
  app.use(errorHandler);

  const server = await new Promise((resolve, reject) => {
    const httpServer = app.listen(TEST_PORT, '127.0.0.1', () => resolve(httpServer));
    httpServer.on('error', reject);
  });

  const results = [];
  let session = null;

  async function runTest(name, fn) {
    clientIp = `203.0.113.${10 + results.length}`;
    try {
      await fn();
      results.push({ name, ok: true });
      console.log(`OK ${name}`);
    } catch (err) {
      results.push({ name, ok: false, error: err.message });
      console.log(`FAIL ${name}: ${err.message}`);
    }
  }

  try {
    await runTest('1. Nouveau compte Google complet', async () => {
      flowDb.reset();
      const pending = await googleStart();
      assert(pending.status === 200, `google/start status ${pending.status} ${pending.raw}`);
      assert(pending.json.message === 'Phone verification required', 'google/start message');
      assert(pending.json.email === GOOGLE_IDENTITY.email, 'google/start email');
      assert(flowDb.state.users.length === 0, 'google/start must not create users');

      const phone = await startPhone({
        oauth_verification_token: pending.json.oauth_verification_token,
        phone_number: PHONE,
      });
      assert(phone.result.status === 200, `start-phone status ${phone.result.status} ${phone.result.raw}`);
      assert(phone.result.json.message === 'Verification code generated', 'start-phone message');
      assert(smsCalls.length === 1, 'start-phone must send SMS');
      assert(flowDb.state.users.length === 0, 'start-phone must not create users');

      const created = await verifyPhone({
        oauth_verification_token: pending.json.oauth_verification_token,
        code: phone.code,
        birth_date: BIRTH_DATE,
        login: LOGIN,
      });
      assert(created.status === 201, `verify-phone status ${created.status} ${created.raw}`);
      assert(created.json.message === 'Account created', 'verify-phone message');
      assert(typeof created.json.access_token === 'string', 'access_token');
      assert(typeof created.json.refresh_token === 'string', 'refresh_token');

      assert(flowDb.state.users.length === 1, 'one user created');
      const user = flowDb.state.users[0];
      assert(user.auth_provider === 'google', `auth_provider=${user.auth_provider}`);
      assert(user.provider_user_id === GOOGLE_IDENTITY.provider_user_id, 'provider_user_id');
      assert(user.password_hash === null, 'password_hash must be NULL');
      assert(user.phone_verified === true, 'phone_verified');
      assert(user.birth_date === BIRTH_DATE, 'birth_date');
      assert(user.email === GOOGLE_IDENTITY.email, 'email');
      assert(user.first_name === GOOGLE_IDENTITY.first_name, 'first_name');
      assert(user.last_name === GOOGLE_IDENTITY.last_name, 'last_name');

      const active = flowDb.state.tokens.filter((token) => token.revoked_at == null);
      assert(active.length === 1, `active refresh tokens: ${active.length}`);
      session = {
        access_token: created.json.access_token,
        refresh_token: created.json.refresh_token,
        userId: user.id,
      };
    });

    await runTest('2. Téléphone absent', async () => {
      flowDb.reset();
      const pending = await googleStart();
      assert(pending.status === 200, 'google/start for missing phone');
      const usersBefore = flowDb.state.users.length;
      smsCalls.length = 0;
      const missing = await httpRequest({
        method: 'POST',
        urlPath: '/auth/oauth/start-phone',
        body: { oauth_verification_token: pending.json.oauth_verification_token },
      });
      assert(missing.status === 400, `expected 400, got ${missing.status} ${missing.raw}`);
      assert(missing.json && missing.json.error === 'phone_number is required', missing.raw);
      assert(smsCalls.length === 0, 'no SMS when phone is missing');
      assert(flowDb.state.users.length === usersBefore, 'no user created');
    });

    await runTest('3. Date de naissance absente', async () => {
      flowDb.reset();
      const step = await beginOauthToSms();
      const usersBefore = flowDb.state.users.length;
      const missing = await verifyPhone({
        oauth_verification_token: step.token,
        code: step.code,
        login: LOGIN,
      });
      assert(missing.status === 400, `expected 400, got ${missing.status} ${missing.raw}`);
      assert(missing.json && missing.json.error === 'birth_date is required', missing.raw);
      assert(flowDb.state.users.length === usersBefore, 'no user created without birth_date');
    });

    await runTest('4. Login absent', async () => {
      flowDb.reset();
      const step = await beginOauthToSms();
      const usersBefore = flowDb.state.users.length;
      const missing = await verifyPhone({
        oauth_verification_token: step.token,
        code: step.code,
        birth_date: BIRTH_DATE,
      });
      assert(missing.status === 400, `expected 400, got ${missing.status} ${missing.raw}`);
      assert(missing.json && missing.json.error === 'login is required', missing.raw);
      assert(flowDb.state.users.length === usersBefore, 'no user created without login');
    });

    await runTest('5. Conflit téléphone', async () => {
      flowDb.reset({
        users: [
          {
            id: 50,
            login: 'local_phone_user',
            email: 'local.phone@example.com',
            phone_number: CONFLICT_PHONE,
            phone_verified: true,
            auth_provider: 'local',
            provider_user_id: null,
            password_hash: 'local-hash',
            birth_date: '1980-01-01',
          },
        ],
      });
      const pending = await googleStart();
      assert(pending.status === 200, 'google/start before phone conflict');
      const usersBefore = flowDb.state.users.length;
      const conflict = await startPhone({
        oauth_verification_token: pending.json.oauth_verification_token,
        phone_number: CONFLICT_PHONE,
      });
      assert(conflict.result.status === 409, `expected 409, got ${conflict.result.status} ${conflict.result.raw}`);
      assert(
        conflict.result.json && conflict.result.json.error === 'Phone number is already in use',
        conflict.result.raw
      );
      assert(flowDb.state.users.length === usersBefore, 'no extra user on phone conflict');
    });

    await runTest('6. Conflit email', async () => {
      flowDb.reset({
        users: [
          {
            id: 60,
            login: 'local_email_user',
            email: GOOGLE_IDENTITY.email,
            phone_number: '+33610000099',
            phone_verified: true,
            auth_provider: 'local',
            provider_user_id: null,
            password_hash: 'local-hash',
            birth_date: '1980-01-01',
          },
        ],
      });
      const usersBefore = flowDb.state.users.length;
      const conflict = await googleStart();
      assert(conflict.status === 409, `expected 409, got ${conflict.status} ${conflict.raw}`);
      assert(
        conflict.json &&
          conflict.json.error === 'Account already exists with another authentication method',
        conflict.raw
      );
      assert(flowDb.state.users.length === usersBefore, 'no extra user on email conflict');
    });

    await runTest('7. Reconnexion Google existant', async () => {
      assert(session, 'session from test 1 is required');
      flowDb.reset();
      const first = await beginOauthToSms();
      const created = await verifyPhone({
        oauth_verification_token: first.token,
        code: first.code,
        birth_date: BIRTH_DATE,
        login: LOGIN,
      });
      assert(created.status === 201, `recreate path failed: ${created.status} ${created.raw}`);
      const usersBefore = flowDb.state.users.length;
      const relogin = await googleStart();
      assert(relogin.status === 200, `reconnect status ${relogin.status} ${relogin.raw}`);
      assert(relogin.json.message === 'Login successful', 'reconnect message');
      assert(typeof relogin.json.access_token === 'string', 'reconnect access_token');
      assert(typeof relogin.json.refresh_token === 'string', 'reconnect refresh_token');
      assert(flowDb.state.users.length === usersBefore, 'must not create another user');
      session = {
        access_token: relogin.json.access_token,
        refresh_token: relogin.json.refresh_token,
        userId: flowDb.state.users[0].id,
      };
    });

    await runTest('8. Logout puis refresh invalide', async () => {
      assert(session, 'session from reconnect is required');
      const logout = await httpRequest({
        method: 'POST',
        urlPath: '/auth/logout',
        headers: { Authorization: `Bearer ${session.access_token}` },
        body: { refresh_token: session.refresh_token },
      });
      assert(logout.status === 200, `logout status ${logout.status} ${logout.raw}`);
      assert(logout.json && logout.json.message === 'Logged out', 'logout message');

      const refresh = await httpRequest({
        method: 'POST',
        urlPath: '/auth/refresh',
        body: { refresh_token: session.refresh_token },
      });
      assert(refresh.status === 401, `refresh status ${refresh.status} ${refresh.raw}`);
      assert(refresh.json && refresh.json.error === 'Invalid refresh token', refresh.raw);
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    smsService.sendSms = originalSendSms;
  }

  printReport(results);
  if (results.some((item) => !item.ok)) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('Google OAuth flow checks failed:', err.message);
  process.exitCode = 1;
});
