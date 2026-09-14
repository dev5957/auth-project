const express = require('express');
const AppError = require('./errors/AppError');
const { hashRefreshToken } = require('./services/tokenService');
const {
  createOauthFlowMemoryDb,
  installMemoryDb,
  assert,
  createHttpClient,
  withOtpCapture,
} = require('./oauthFlowTestSupport');

const TEST_SECRET = 'apple-oauth-flow-test-secret';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30447;
const IDENTITY_TOKEN = 'simulated-apple-identity-token-not-from-apple';
const NO_EMAIL_TOKEN = 'simulated-apple-identity-token-without-email';
const NAMED_TOKEN = 'simulated-apple-identity-token-with-names';
const UNKNOWN_TOKEN = 'eyJhbGciOiJSUzI1NiIsImtpZCI6ImZha2UifQ.fake.signature';
const PHONE = '+33620000001';
const CONFLICT_PHONE = '+33620000002';
const LOGIN = 'apple_tester';
const TAKEN_LOGIN = 'taken_apple_login';
const BIRTH_DATE = '1991-07-15';
const PENDING_PHONE_PLACEHOLDER = 'oauth-pending';

const APPLE_IDENTITY = {
  provider: 'apple',
  provider_user_id: 'apple-test-user-001',
  email: 'test.apple@example.com',
  first_name: null,
  last_name: null,
};

const APPLE_NAMED_IDENTITY = {
  provider: 'apple',
  provider_user_id: 'apple-test-user-002',
  email: 'test.apple.named@example.com',
  first_name: 'Ada',
  last_name: 'Lovelace',
};

const APPLE_NO_EMAIL_IDENTITY = {
  provider: 'apple',
  provider_user_id: 'apple-test-user-no-email',
  email: null,
  first_name: null,
  last_name: null,
};

const MOCK_APPLE_IDENTITIES = {
  [IDENTITY_TOKEN]: APPLE_IDENTITY,
  [NAMED_TOKEN]: APPLE_NAMED_IDENTITY,
  [NO_EMAIL_TOKEN]: APPLE_NO_EMAIL_IDENTITY,
};

process.env.PORT = String(TEST_PORT);
process.env.JWT_SECRET = TEST_SECRET;
process.env.JWT_ISSUER = TEST_ISSUER;
process.env.JWT_AUDIENCE = TEST_AUDIENCE;
process.env.JWT_EXPIRES_IN = '15m';
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://apple-oauth-flow-test/local';
process.env.SMS_PROVIDER = 'mock';
process.env.DEV_LOG_SMS_CODE = 'true';
process.env.APPLE_CLIENT_ID = 'apple-oauth-flow-test-client-id';

const flowDb = createOauthFlowMemoryDb();
installMemoryDb(flowDb);

const appleAuthService = require('./services/appleAuthService');
const productionVerifyAppleIdentityToken = appleAuthService.verifyAppleIdentityToken;
let productionVerifyCalls = 0;

appleAuthService.verifyAppleIdentityToken = async function mockVerifyAppleIdentityToken(identityToken) {
  if (typeof identityToken !== 'string' || identityToken.trim() === '') {
    throw new AppError(400, 'identity_token is required');
  }
  const identity = MOCK_APPLE_IDENTITIES[identityToken.trim()];
  if (!identity) {
    throw new AppError(401, 'Unauthorized');
  }
  return {
    provider_user_id: identity.provider_user_id,
    email: identity.email,
    first_name: identity.first_name,
    last_name: identity.last_name,
  };
};

const authRoutes = require('./routes/auth');
const errorHandler = require('./middleware/errorHandler');
const smsService = require('./services/smsService');

assert(
  appleAuthService.verifyAppleIdentityToken !== productionVerifyAppleIdentityToken,
  'Apple HTTP flow test must use an explicit mock of verifyAppleIdentityToken'
);

const smsCalls = [];
const originalSendSms = smsService.sendSms;
smsService.sendSms = async (...args) => {
  smsCalls.push({ phoneNumber: args[0], message: args[1] });
  return originalSendSms(...args);
};

let clientIp = '203.0.113.40';
const httpRequest = createHttpClient({
  port: TEST_PORT,
  getClientIp: () => clientIp,
});

async function appleStart(body = { identity_token: IDENTITY_TOKEN }) {
  return httpRequest({
    method: 'POST',
    urlPath: '/auth/apple/start',
    body,
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

async function beginOauthToSms({
  identityToken = IDENTITY_TOKEN,
  phoneNumber = PHONE,
  extraStartBody = {},
} = {}) {
  const started = await appleStart({ identity_token: identityToken, ...extraStartBody });
  assert(started.status === 200, `apple/start: ${started.status} ${started.raw}`);
  assert(started.json && started.json.oauth_verification_token, 'oauth_verification_token missing');
  const token = started.json.oauth_verification_token;
  const phone = await startPhone({
    oauth_verification_token: token,
    phone_number: phoneNumber,
  });
  assert(phone.result.status === 200, `oauth/start-phone: ${phone.result.status} ${phone.result.raw}`);
  assert(phone.code, 'OTP was not captured');
  return { token, code: phone.code, started };
}

function printReport(results) {
  const passed = results.filter((item) => item.ok);
  const failed = results.filter((item) => !item.ok);
  const activeRefresh = flowDb.state.tokens.filter((token) => token.revoked_at == null).length;
  const revokedRefresh = flowDb.state.tokens.filter((token) => token.revoked_at != null).length;

  console.log('');
  console.log('=== Rapport Apple OAuth (tests fonctionnels internes) ===');
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
  console.log('Apple Developer / JWKS / clé .p8 : non utilisés (mock de vérification explicite).');
  console.log(
    `verifyAppleIdentityToken de production : ${productionVerifyCalls} appel(s) (attendu : 0).`
  );
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
    clientIp = `203.0.113.${40 + results.length}`;
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
    await runTest('1. Nouveau compte Apple complet', async () => {
      flowDb.reset();
      const pending = await appleStart();
      assert(pending.status === 200, `apple/start status ${pending.status} ${pending.raw}`);
      assert(pending.json.message === 'Phone verification required', 'apple/start message');
      assert(typeof pending.json.oauth_verification_token === 'string', 'oauth_verification_token');
      assert(pending.json.provider === 'apple', `provider=${pending.json.provider}`);
      assert(pending.json.email === APPLE_IDENTITY.email, 'apple/start email');
      assert(flowDb.state.users.length === 0, 'apple/start must not create users');
      assert(flowDb.state.verifications.length === 1, 'pending phone_verifications row');
      const pendingRow = flowDb.state.verifications[0];
      assert(pendingRow.phone_number === PENDING_PHONE_PLACEHOLDER, 'placeholder phone');
      assert(pendingRow.registration_data.provider === 'apple', 'registration_data.provider');
      assert(
        pendingRow.registration_data.provider_user_id === APPLE_IDENTITY.provider_user_id,
        'registration_data.provider_user_id'
      );
      assert(pendingRow.registration_data.email === APPLE_IDENTITY.email, 'registration_data.email');

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
      assert(user.auth_provider === 'apple', `auth_provider=${user.auth_provider}`);
      assert(user.provider_user_id === APPLE_IDENTITY.provider_user_id, 'provider_user_id');
      assert(user.email === APPLE_IDENTITY.email, 'email');
      assert(user.phone_verified === true, 'phone_verified');
      assert(user.password_hash === null, 'password_hash must be NULL');
      assert(user.birth_date === BIRTH_DATE, 'birth_date');
      assert(user.login === LOGIN, 'login');

      const active = flowDb.state.tokens.filter((token) => token.revoked_at == null);
      assert(active.length === 1, `active refresh tokens: ${active.length}`);
      session = {
        access_token: created.json.access_token,
        refresh_token: created.json.refresh_token,
        userId: user.id,
      };
    });

    await runTest('2. GET /auth/me avec access_token', async () => {
      assert(session, 'session from test 1 is required');
      const me = await httpRequest({
        method: 'GET',
        urlPath: '/auth/me',
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      assert(me.status === 200, `me status ${me.status} ${me.raw}`);
      assert(me.json && me.json.user, 'me user');
      assert(me.json.user.userId === session.userId, 'me userId');
      assert(me.json.user.login === LOGIN, 'me login');
      assert(me.json.user.auth_provider === 'apple', 'me auth_provider');
    });

    await runTest('3. POST /auth/refresh', async () => {
      assert(session, 'session from test 1 is required');
      const refresh = await httpRequest({
        method: 'POST',
        urlPath: '/auth/refresh',
        body: { refresh_token: session.refresh_token },
      });
      assert(refresh.status === 200, `refresh status ${refresh.status} ${refresh.raw}`);
      assert(refresh.json && refresh.json.message === 'Token refreshed', 'refresh message');
      assert(typeof refresh.json.access_token === 'string', 'new access_token');
      assert(typeof refresh.json.refresh_token === 'string', 'new refresh_token');
      assert(refresh.json.refresh_token !== session.refresh_token, 'refresh token must rotate');
      session = {
        access_token: refresh.json.access_token,
        refresh_token: refresh.json.refresh_token,
        userId: session.userId,
      };
    });

    await runTest('4. Logout puis refresh refusé', async () => {
      assert(session, 'session from refresh is required');
      const previousRefresh = session.refresh_token;
      const logout = await httpRequest({
        method: 'POST',
        urlPath: '/auth/logout',
        headers: { Authorization: `Bearer ${session.access_token}` },
        body: { refresh_token: previousRefresh },
      });
      assert(logout.status === 200, `logout status ${logout.status} ${logout.raw}`);
      assert(logout.json && logout.json.message === 'Logged out', 'logout message');

      const refresh = await httpRequest({
        method: 'POST',
        urlPath: '/auth/refresh',
        body: { refresh_token: previousRefresh },
      });
      assert(refresh.status === 401, `refresh status ${refresh.status} ${refresh.raw}`);
      assert(refresh.json && refresh.json.error === 'Invalid refresh token', refresh.raw);
    });

    await runTest('5. Reconnexion Apple après logout', async () => {
      assert(session, 'session from tests 1-4 is required');
      assert(flowDb.state.users.length === 1, 'must keep the Apple user created in test 1');
      const existing = flowDb.state.users[0];
      assert(existing.id === session.userId, 'same user_id as before logout');
      assert(existing.provider_user_id === APPLE_IDENTITY.provider_user_id, 'same apple sub');
      assert(existing.auth_provider === 'apple', 'auth_provider remains apple');

      const usersBefore = flowDb.state.users.length;
      const previousAccess = session.access_token;
      const previousRefresh = session.refresh_token;

      const relogin = await appleStart();
      assert(relogin.status === 200, `reconnect after logout: ${relogin.status} ${relogin.raw}`);
      assert(relogin.json.message === 'Login successful', 'reconnect after logout message');
      assert(typeof relogin.json.access_token === 'string', 'new access_token');
      assert(typeof relogin.json.refresh_token === 'string', 'new refresh_token');
      assert(relogin.json.access_token !== previousAccess, 'access_token must be new');
      assert(relogin.json.refresh_token !== previousRefresh, 'refresh_token must be new');
      assert(flowDb.state.users.length === usersBefore, 'must not create another user after logout');
      assert(flowDb.state.users[0].id === existing.id, 'same user_id after Apple reconnect');
      assert(
        flowDb.state.users[0].provider_user_id === APPLE_IDENTITY.provider_user_id,
        'provider_user_id/sub unchanged'
      );

      const me = await httpRequest({
        method: 'GET',
        urlPath: '/auth/me',
        headers: { Authorization: `Bearer ${relogin.json.access_token}` },
      });
      assert(me.status === 200, `me after reconnect: ${me.status} ${me.raw}`);
      assert(me.json && me.json.user, 'me user after reconnect');
      assert(me.json.user.userId === existing.id, 'me userId after reconnect');
      assert(me.json.user.login === LOGIN, 'me login after reconnect');
      assert(me.json.user.auth_provider === 'apple', 'me auth_provider after reconnect');

      session = {
        access_token: relogin.json.access_token,
        refresh_token: relogin.json.refresh_token,
        userId: existing.id,
      };
    });

    await runTest('6. Ancien refresh Apple refusé après rotation', async () => {
      assert(session, 'session from Apple reconnect is required');
      assert(flowDb.state.users.length === 1, 'must keep the Apple user');
      const userId = session.userId;
      const refreshA = session.refresh_token;
      const hashA = hashRefreshToken(refreshA);

      const rotated = await httpRequest({
        method: 'POST',
        urlPath: '/auth/refresh',
        body: { refresh_token: refreshA },
      });
      assert(rotated.status === 200, `refresh status ${rotated.status} ${rotated.raw}`);
      assert(rotated.json && rotated.json.message === 'Token refreshed', 'refresh message');
      assert(typeof rotated.json.access_token === 'string', 'access_token_B');
      assert(typeof rotated.json.refresh_token === 'string', 'refresh_token_B');
      const refreshB = rotated.json.refresh_token;
      assert(refreshB !== refreshA, 'refresh_token_B must differ from refresh_token_A');

      const hashB = hashRefreshToken(refreshB);
      const rowA = flowDb.state.tokens.find((token) => token.token_hash === hashA);
      const rowB = flowDb.state.tokens.find((token) => token.token_hash === hashB);
      assert(rowA, 'refresh_token_A row');
      assert(rowB, 'refresh_token_B row');
      assert(rowA.user_id === userId, 'refresh_token_A user_id');
      assert(rowB.user_id === userId, 'refresh_token_B user_id');
      assert(rowA.revoked_at, 'refresh_token_A must be revoked after rotation');
      assert(rowB.revoked_at == null, 'refresh_token_B must be the active session token');

      const createdBeforeReuse = flowDb.stats.refreshCreated;
      const securityEvents = [];
      const originalError = console.error;
      console.error = (...args) => {
        securityEvents.push(args.map(String).join(' '));
        originalError.apply(console, args);
      };
      let reuse;
      try {
        reuse = await httpRequest({
          method: 'POST',
          urlPath: '/auth/refresh',
          body: { refresh_token: refreshA },
        });
      } finally {
        console.error = originalError;
      }

      assert(reuse.status === 401, `reuse status ${reuse.status} ${reuse.raw}`);
      assert(reuse.json && reuse.json.error === 'Invalid refresh token', reuse.raw);
      assert(
        securityEvents.some((line) => line.includes('refresh_token_reuse')),
        'expected refresh_token_reuse security event'
      );
      assert(flowDb.stats.refreshCreated === createdBeforeReuse, 'reuse must not insert a refresh token');
      assert(rowA.revoked_at, 'refresh_token_A stays revoked after reuse');
      assert(rowB.revoked_at, 'reuse of a revoked token must revoke remaining active tokens');
      const active = flowDb.state.tokens.filter(
        (token) => token.user_id === userId && token.revoked_at == null
      );
      assert(active.length === 0, `active refresh tokens after reuse: ${active.length}`);
    });

    await runTest('7. Reconnexion Apple existant', async () => {
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
      const relogin = await appleStart();
      assert(relogin.status === 200, `reconnect status ${relogin.status} ${relogin.raw}`);
      assert(relogin.json.message === 'Login successful', 'reconnect message');
      assert(typeof relogin.json.access_token === 'string', 'reconnect access_token');
      assert(typeof relogin.json.refresh_token === 'string', 'reconnect refresh_token');
      assert(flowDb.state.users.length === usersBefore, 'must not create another user');
      assert(flowDb.state.users[0].provider_user_id === APPLE_IDENTITY.provider_user_id, 'same apple sub');
    });

    await runTest('8. Conflit email déjà utilisé par local', async () => {
      flowDb.reset({
        users: [
          {
            id: 60,
            login: 'local_email_user',
            email: APPLE_IDENTITY.email,
            phone_number: '+33620000099',
            phone_verified: true,
            auth_provider: 'local',
            provider_user_id: null,
            password_hash: 'local-hash',
            birth_date: '1980-01-01',
          },
        ],
      });
      const usersBefore = flowDb.state.users.length;
      const conflict = await appleStart();
      assert(conflict.status === 409, `expected 409, got ${conflict.status} ${conflict.raw}`);
      assert(
        conflict.json &&
          conflict.json.error === 'Account already exists with another authentication method',
        conflict.raw
      );
      assert(flowDb.state.users.length === usersBefore, 'no extra user on local email conflict');
      assert(flowDb.state.verifications.length === 0, 'no pending oauth on email conflict');
    });

    await runTest('9. Conflit email déjà utilisé par google', async () => {
      flowDb.reset({
        users: [
          {
            id: 61,
            login: 'google_email_user',
            email: APPLE_IDENTITY.email,
            phone_number: '+33620000098',
            phone_verified: true,
            auth_provider: 'google',
            provider_user_id: 'google-other-user',
            password_hash: null,
            birth_date: '1981-02-02',
          },
        ],
      });
      const usersBefore = flowDb.state.users.length;
      const conflict = await appleStart();
      assert(conflict.status === 409, `expected 409, got ${conflict.status} ${conflict.raw}`);
      assert(
        conflict.json &&
          conflict.json.error === 'Account already exists with another authentication method',
        conflict.raw
      );
      assert(flowDb.state.users.length === usersBefore, 'no extra user on google email conflict');
    });

    await runTest('10. Conflit login déjà utilisé', async () => {
      flowDb.reset({
        users: [
          {
            id: 70,
            login: TAKEN_LOGIN,
            email: 'local.login@example.com',
            phone_number: '+33620000097',
            phone_verified: true,
            auth_provider: 'local',
            provider_user_id: null,
            password_hash: 'local-hash',
            birth_date: '1982-03-03',
          },
        ],
      });
      const step = await beginOauthToSms({ phoneNumber: '+33620000021' });
      const usersBefore = flowDb.state.users.length;
      const conflict = await verifyPhone({
        oauth_verification_token: step.token,
        code: step.code,
        birth_date: BIRTH_DATE,
        login: TAKEN_LOGIN,
      });
      assert(conflict.status === 409, `expected 409, got ${conflict.status} ${conflict.raw}`);
      assert(conflict.json && conflict.json.error === 'Login is already in use', conflict.raw);
      assert(flowDb.state.users.length === usersBefore, 'no extra user on login conflict');
    });

    await runTest('11. Conflit téléphone déjà utilisé', async () => {
      flowDb.reset({
        users: [
          {
            id: 50,
            login: 'local_phone_user',
            email: 'local.phone.apple@example.com',
            phone_number: CONFLICT_PHONE,
            phone_verified: true,
            auth_provider: 'local',
            provider_user_id: null,
            password_hash: 'local-hash',
            birth_date: '1980-01-01',
          },
        ],
      });
      const pending = await appleStart();
      assert(pending.status === 200, 'apple/start before phone conflict');
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

    await runTest('12. Conflit provider_user_id Apple déjà utilisé', async () => {
      flowDb.reset();
      const pending = await appleStart();
      assert(pending.status === 200, 'apple/start before provider conflict');
      flowDb.state.users.push({
        id: 80,
        login: 'existing_apple',
        email: 'existing.apple@example.com',
        phone_number: '+33620000096',
        phone_verified: true,
        auth_provider: 'apple',
        provider_user_id: APPLE_IDENTITY.provider_user_id,
        password_hash: null,
        birth_date: '1983-04-04',
      });
      const phone = await startPhone({
        oauth_verification_token: pending.json.oauth_verification_token,
        phone_number: '+33620000022',
      });
      assert(phone.result.status === 200, 'start-phone before provider_user_id conflict');
      const usersBefore = flowDb.state.users.length;
      const conflict = await verifyPhone({
        oauth_verification_token: pending.json.oauth_verification_token,
        code: phone.code,
        birth_date: BIRTH_DATE,
        login: 'other_apple_login',
      });
      assert(conflict.status === 409, `expected 409, got ${conflict.status} ${conflict.raw}`);
      assert(
        conflict.json &&
          conflict.json.error === 'Account already exists with another authentication method',
        conflict.raw
      );
      assert(flowDb.state.users.length === usersBefore, 'no extra user on apple sub conflict');
    });

    await runTest('13. Apple sans email', async () => {
      flowDb.reset();
      const missing = await appleStart({ identity_token: NO_EMAIL_TOKEN });
      assert(missing.status === 400, `expected 400, got ${missing.status} ${missing.raw}`);
      assert(missing.json && missing.json.error === 'email is required', missing.raw);
      assert(flowDb.state.users.length === 0, 'no users without email');
      assert(flowDb.state.verifications.length === 0, 'no pending oauth without email');
    });

    await runTest('14. Noms optionnels', async () => {
      flowDb.reset();
      const fromBody = await appleStart({
        identity_token: IDENTITY_TOKEN,
        first_name: 'BodyFirst',
        last_name: 'BodyLast',
      });
      assert(fromBody.status === 200, `names from body: ${fromBody.status} ${fromBody.raw}`);
      assert(flowDb.state.verifications[0].registration_data.first_name === 'BodyFirst', 'body first_name');
      assert(flowDb.state.verifications[0].registration_data.last_name === 'BodyLast', 'body last_name');

      flowDb.reset();
      const fromToken = await appleStart({
        identity_token: NAMED_TOKEN,
        first_name: 'Ignored',
        last_name: 'Ignored',
      });
      assert(fromToken.status === 200, `names from token: ${fromToken.status} ${fromToken.raw}`);
      assert(
        fromToken.json.email === APPLE_NAMED_IDENTITY.email,
        'named identity email'
      );
      assert(flowDb.state.verifications[0].registration_data.first_name === 'Ada', 'token first_name wins');
      assert(flowDb.state.verifications[0].registration_data.last_name === 'Lovelace', 'token last_name wins');

      const phone = await startPhone({
        oauth_verification_token: fromToken.json.oauth_verification_token,
        phone_number: '+33620000023',
      });
      const created = await verifyPhone({
        oauth_verification_token: fromToken.json.oauth_verification_token,
        code: phone.code,
        birth_date: BIRTH_DATE,
        login: 'apple_named',
      });
      assert(created.status === 201, `named verify-phone: ${created.status} ${created.raw}`);
      assert(flowDb.state.users[0].first_name === 'Ada', 'persisted first_name');
      assert(flowDb.state.users[0].last_name === 'Lovelace', 'persisted last_name');
      assert(flowDb.state.users[0].auth_provider === 'apple', 'named user provider');
    });

    await runTest('15. Token Apple inconnu rejeté par le mock', async () => {
      flowDb.reset();
      const unknown = await appleStart({ identity_token: UNKNOWN_TOKEN });
      assert(unknown.status === 401, `expected 401, got ${unknown.status} ${unknown.raw}`);
      assert(unknown.json && unknown.json.error === 'Unauthorized', unknown.raw);
      assert(flowDb.state.users.length === 0, 'unknown token must not create users');
      assert(flowDb.state.verifications.length === 0, 'unknown token must not create pending oauth');
      assert(productionVerifyCalls === 0, 'production JWKS verify must not run in this suite');
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
  console.error('Apple OAuth flow checks failed:', err.message);
  process.exitCode = 1;
});
