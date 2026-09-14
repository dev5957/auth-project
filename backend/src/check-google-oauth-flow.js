const express = require('express');
const AppError = require('./errors/AppError');
const {
  createOauthFlowMemoryDb,
  installMemoryDb,
  assert,
  createHttpClient,
  withOtpCapture,
} = require('./oauthFlowTestSupport');

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

const flowDb = createOauthFlowMemoryDb();
installMemoryDb(flowDb);

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

let clientIp = '203.0.113.10';
const httpRequest = createHttpClient({
  port: TEST_PORT,
  getClientIp: () => clientIp,
});

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
  console.log(`Utilisateurs créés (INSERT users) : ${flowDb.stats.usersCreated}`);
  console.log(`refresh_tokens créés : ${flowDb.stats.refreshCreated}`);
  console.log(`refresh_tokens révoqués : ${flowDb.stats.refreshRevoked}`);
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
