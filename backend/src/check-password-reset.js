const bcrypt = require('bcrypt');
const {
  GENERIC_FORGOT_MESSAGE,
  GENERIC_RESET_ERROR,
  RESET_SUCCESS_MESSAGE,
  requestPasswordReset,
  confirmPasswordReset,
} = require('./services/passwordResetService');
const smsService = require('./services/smsService');

const CODE = '123456';
const PHONE = '+33612345678';
const OLD_PASSWORD = 'oldpass12';
const NEW_PASSWORD = 'newpass12';
const LOGIN = 'ada';

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

function localUser(overrides = {}) {
  return {
    id: 1,
    email: 'ada@example.com',
    login: LOGIN,
    phone_number: PHONE,
    phone_verified: true,
    auth_provider: 'local',
    password_hash: bcrypt.hashSync(OLD_PASSWORD, 4),
    ...overrides,
  };
}

function createMemoryDb({ users = [], resets = [], tokens = [] } = {}) {
  const state = {
    users: users.map((user) => ({ ...user })),
    resets: resets.map((row) => ({ ...row })),
    tokens: tokens.map((row) => ({ ...row })),
    nextResetId: resets.reduce((max, row) => Math.max(max, row.id || 0), 0) + 1,
  };

  let lock = Promise.resolve();
  let lockRelease = null;

  async function acquireLock() {
    const previous = lock;
    let release;
    const held = new Promise((resolve) => {
      release = resolve;
    });
    lock = previous.then(() => held);
    await previous;
    lockRelease = release;
  }

  function releaseLock() {
    if (lockRelease) {
      lockRelease();
      lockRelease = null;
    }
  }

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN') {
      return { rows: [], rowCount: 0 };
    }
    if (key === 'COMMIT' || key === 'ROLLBACK') {
      releaseLock();
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('FROM USERS') && key.includes('PHONE_VERIFIED') && key.includes('PHONE_NUMBER')) {
      const phone_number = params[0];
      const user = state.users.find((item) => item.phone_number === phone_number);
      return {
        rowCount: user ? 1 : 0,
        rows: user
          ? [
              {
                id: user.id,
                auth_provider: user.auth_provider,
                password_hash: user.password_hash,
                phone_verified: user.phone_verified,
              },
            ]
          : [],
      };
    }

    if (key.includes('FROM PASSWORD_RESET_REQUESTS') && key.includes('CREATED_AT') && !key.includes('FOR UPDATE')) {
      const phone_number = params[0];
      const rows = state.resets
        .filter((row) => row.phone_number === phone_number)
        .sort((a, b) => new Date(b.created_at) - new Date(a.created_at) || b.id - a.id);
      return {
        rowCount: rows.length ? 1 : 0,
        rows: rows[0] ? [{ created_at: rows[0].created_at }] : [],
      };
    }

    if (key.includes('INSERT INTO PASSWORD_RESET_REQUESTS')) {
      const row = {
        id: state.nextResetId,
        user_id: params[0],
        phone_number: params[1],
        code_hash: params[2],
        expires_at: params[3],
        attempts: 0,
        used_at: null,
        created_at: new Date(),
      };
      state.nextResetId += 1;
      state.resets.push(row);
      return { rowCount: 1, rows: [] };
    }

    if (key.includes('FROM PASSWORD_RESET_REQUESTS') && key.includes('FOR UPDATE')) {
      await acquireLock();
      const phone_number = params[0];
      const rows = state.resets
        .filter((row) => row.phone_number === phone_number && row.used_at == null)
        .sort((a, b) => new Date(b.created_at) - new Date(a.created_at) || b.id - a.id);
      const row = rows[0];
      return {
        rowCount: row ? 1 : 0,
        rows: row
          ? [
              {
                id: row.id,
                user_id: row.user_id,
                phone_number: row.phone_number,
                code_hash: row.code_hash,
                expires_at: row.expires_at,
                attempts: row.attempts,
                used_at: row.used_at,
              },
            ]
          : [],
      };
    }

    if (key.includes('UPDATE PASSWORD_RESET_REQUESTS') && key.includes('ATTEMPTS')) {
      const row = state.resets.find((item) => item.id === params[1]);
      if (row) {
        row.attempts = params[0];
        return { rowCount: 1, rows: [] };
      }
      return { rowCount: 0, rows: [] };
    }

    if (key.includes('UPDATE PASSWORD_RESET_REQUESTS') && key.includes('USED_AT')) {
      const row = state.resets.find((item) => item.id === params[0] && item.used_at == null);
      if (!row) {
        return { rowCount: 0, rows: [] };
      }
      row.used_at = new Date();
      return { rowCount: 1, rows: [] };
    }

    if (key.includes('UPDATE USERS') && key.includes('PASSWORD_HASH')) {
      const user = state.users.find(
        (item) => item.id === params[1] && item.auth_provider === 'local'
      );
      if (!user) {
        return { rowCount: 0, rows: [] };
      }
      user.password_hash = params[0];
      return { rowCount: 1, rows: [] };
    }

    if (key.includes('UPDATE REFRESH_TOKENS') && key.includes('REVOKED_AT')) {
      let count = 0;
      for (const token of state.tokens) {
        if (token.user_id === params[0] && token.revoked_at == null) {
          token.revoked_at = new Date();
          count += 1;
        }
      }
      return { rowCount: count, rows: [] };
    }

    throw new Error(`unexpected SQL: ${sql}`);
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

function depsFor(db, extras = {}) {
  return {
    db,
    generateCode: () => CODE,
    sendSms: extras.sendSms || (async () => ({ mocked: true })),
    nowMs: extras.nowMs || Date.now(),
  };
}

async function assertLocalLoginWouldSucceed(user, password) {
  assert(user.auth_provider === 'local', 'login: still local');
  assert(user.phone_verified === true, 'login: phone_verified');
  assert(typeof user.password_hash === 'string' && user.password_hash.length > 0, 'login: hash');
  assert(await bcrypt.compare(password, user.password_hash), 'login: new password matches');
  assert(!(await bcrypt.compare(OLD_PASSWORD, user.password_hash)), 'login: old password rejected');
}

async function main() {
  const previousUrl = process.env.DATABASE_URL;
  const previousDev = process.env.DEV_LOG_RESET_CODE;
  process.env.DATABASE_URL = 'postgres://password-reset-test';
  process.env.DEV_LOG_RESET_CODE = 'true';

  try {
    const forgotBody = { phone_number: '+33 6 12-34-56-78' };
    const resetBody = {
      phone_number: PHONE,
      code: CODE,
      password: NEW_PASSWORD,
      password_confirmation: NEW_PASSWORD,
    };

    await (async () => {
      const sends = [];
      const unknown = createMemoryDb();
      const google = createMemoryDb({
        users: [localUser({ auth_provider: 'google', password_hash: null })],
      });
      const apple = createMemoryDb({
        users: [localUser({ auth_provider: 'apple', password_hash: null, id: 2 })],
      });
      const unverified = createMemoryDb({
        users: [localUser({ phone_verified: false })],
      });
      const local = createMemoryDb({ users: [localUser()] });
      const sendSms = async (phone_number, message) => {
        sends.push({ phone_number, message });
        return { mocked: true };
      };

      const unknownResult = await requestPasswordReset(forgotBody, depsFor(unknown, { sendSms }));
      const googleResult = await requestPasswordReset(forgotBody, depsFor(google, { sendSms }));
      const appleResult = await requestPasswordReset(forgotBody, depsFor(apple, { sendSms }));
      const unverifiedResult = await requestPasswordReset(forgotBody, depsFor(unverified, { sendSms }));
      const localResult = await requestPasswordReset(forgotBody, depsFor(local, { sendSms }));

      assert(unknownResult.message === GENERIC_FORGOT_MESSAGE, 'unknown message');
      assert(googleResult.message === localResult.message, 'google same message');
      assert(appleResult.message === localResult.message, 'apple same message');
      assert(unverifiedResult.message === localResult.message, 'unverified same message');
      assert(unknown.state.resets.length === 0, 'unknown must not insert');
      assert(google.state.resets.length === 0, 'google must not insert');
      assert(apple.state.resets.length === 0, 'apple must not insert');
      assert(unverified.state.resets.length === 0, 'unverified local must not insert');
      assert(local.state.resets.length === 1, 'local verified must insert');
      assert(local.state.resets[0].code_hash !== CODE, 'code must be hashed');
      assert(!Object.prototype.hasOwnProperty.call(local.state.resets[0], 'code'), 'no plaintext code column');
      assert(sends.length === 1, 'only recoverable local receives a code');
      assert(sends[0].phone_number === PHONE, 'normalized phone');
      assert(sends[0].message.includes(CODE), 'sms body includes code');
      console.log('OK forgot: même 200 générique, code seulement pour local + téléphone vérifié');
    })();

    await (async () => {
      const db = createMemoryDb({
        users: [localUser()],
        tokens: [
          { id: 10, user_id: 1, revoked_at: null },
          { id: 11, user_id: 1, revoked_at: null },
          { id: 12, user_id: 2, revoked_at: null },
        ],
      });
      await requestPasswordReset(forgotBody, depsFor(db));
      const result = await confirmPasswordReset(resetBody, depsFor(db));
      assert(result.message === RESET_SUCCESS_MESSAGE, 'reset message');
      assert(!('access_token' in result), 'no access token');
      assert(!('refresh_token' in result), 'no refresh token');
      assert(db.state.resets[0].used_at, 'used_at set');
      assert(db.state.users[0].auth_provider === 'local', 'still local');
      assert(await bcrypt.compare(NEW_PASSWORD, db.state.users[0].password_hash), 'password updated');
      assert(db.state.tokens[0].revoked_at, 'refresh 1 revoked');
      assert(db.state.tokens[1].revoked_at, 'refresh 2 revoked');
      assert(db.state.tokens[2].revoked_at == null, 'other user refresh stays');
      await assertLocalLoginWouldSucceed(db.state.users[0], NEW_PASSWORD);
      console.log('OK reset local: password + révocation refresh, pas de JWT, login nouveau mot de passe');
    })();

    await (async () => {
      const db = createMemoryDb({ users: [localUser()] });
      await requestPasswordReset(forgotBody, depsFor(db));
      await confirmPasswordReset(resetBody, depsFor(db));
      await expectStatus(
        () => confirmPasswordReset(resetBody, depsFor(db)),
        400,
        GENERIC_RESET_ERROR
      );
      console.log('OK code usage unique');
    })();

    await (async () => {
      const db = createMemoryDb({ users: [localUser()] });
      await requestPasswordReset(forgotBody, depsFor(db));
      const before = db.state.users[0].password_hash;
      await expectStatus(
        () => confirmPasswordReset({ ...resetBody, code: '000000' }, depsFor(db)),
        400,
        GENERIC_RESET_ERROR
      );
      assert(db.state.resets[0].attempts === 1, 'attempts incremented');
      assert(db.state.users[0].password_hash === before, 'password unchanged');
      console.log('OK mauvais code');
    })();

    await (async () => {
      const db = createMemoryDb({
        users: [localUser()],
        resets: [
          {
            id: 8,
            user_id: 1,
            phone_number: PHONE,
            code_hash: await bcrypt.hash(CODE, 4),
            expires_at: new Date(Date.now() - 1000),
            attempts: 0,
            used_at: null,
            created_at: new Date(),
          },
        ],
      });
      await expectStatus(() => confirmPasswordReset(resetBody, depsFor(db)), 400, GENERIC_RESET_ERROR);
      console.log('OK code expiré');
    })();

    await (async () => {
      const db = createMemoryDb({
        users: [localUser()],
        resets: [
          {
            id: 9,
            user_id: 1,
            phone_number: PHONE,
            code_hash: await bcrypt.hash(CODE, 4),
            expires_at: new Date(Date.now() + 10 * 60 * 1000),
            attempts: 5,
            used_at: null,
            created_at: new Date(),
          },
        ],
      });
      await expectStatus(() => confirmPasswordReset(resetBody, depsFor(db)), 400, GENERIC_RESET_ERROR);
      console.log('OK 5 tentatives max');
    })();

    await (async () => {
      const db = createMemoryDb({ users: [localUser()] });
      await expectStatus(
        () =>
          confirmPasswordReset(
            { ...resetBody, password: 'short', password_confirmation: 'short' },
            depsFor(db)
          ),
        400,
        'Password must be between 8 and 72 characters'
      );
      await expectStatus(
        () =>
          confirmPasswordReset(
            { ...resetBody, password_confirmation: 'otherpass' },
            depsFor(db)
          ),
        400,
        'password and password_confirmation do not match'
      );
      console.log('OK politique mot de passe');
    })();

    await (async () => {
      const db = createMemoryDb({
        users: [localUser({ auth_provider: 'google', password_hash: null })],
      });
      await requestPasswordReset(forgotBody, depsFor(db));
      await expectStatus(() => confirmPasswordReset(resetBody, depsFor(db)), 400, GENERIC_RESET_ERROR);
      assert(db.state.users[0].auth_provider === 'google', 'google stays google');
      assert(db.state.users[0].password_hash == null, 'google password_hash stays null');
      console.log('OK Google: pas de code, pas de conversion local');
    })();

    await (async () => {
      const db = createMemoryDb({ users: [localUser()] });
      const t0 = Date.now();
      await requestPasswordReset(forgotBody, depsFor(db, { nowMs: t0 }));
      await requestPasswordReset(forgotBody, depsFor(db, { nowMs: t0 + 1000 }));
      assert(db.state.resets.length === 1, 'cooldown 60s');
      await requestPasswordReset(forgotBody, depsFor(db, { nowMs: t0 + 61 * 1000 }));
      assert(db.state.resets.length === 2, 'after cooldown a new row is inserted');
      console.log('OK cooldown 60s par téléphone normalisé');
    })();

    await (async () => {
      const db = createMemoryDb({ users: [localUser()] });
      await requestPasswordReset(forgotBody, depsFor(db));
      const results = await Promise.allSettled([
        confirmPasswordReset(resetBody, depsFor(db)),
        confirmPasswordReset(resetBody, depsFor(db)),
      ]);
      const fulfilled = results.filter((item) => item.status === 'fulfilled');
      const rejected = results.filter((item) => item.status === 'rejected');
      assert(fulfilled.length === 1, 'one concurrent reset succeeds');
      assert(rejected.length === 1, 'one concurrent reset fails');
      assert(rejected[0].reason.statusCode === 400, 'loser is generic 400');
      assert(db.state.resets.filter((row) => row.used_at).length === 1, 'consumed once');
      console.log('OK concurrence FOR UPDATE');
    })();

    await (async () => {
      const db = createMemoryDb({ users: [localUser()] });
      const captured = await captureLogs(() => requestPasswordReset(forgotBody, depsFor(db)));
      assert(
        captured.logs.includes(`[DEV] Password reset code: ${CODE}`),
        'DEV_LOG_RESET_CODE must print the code'
      );
      assert(captured.result.message === GENERIC_FORGOT_MESSAGE, 'API stays generic');
      assert(!captured.result.message.includes(CODE), 'API must not return the code');
      assert(!captured.logs.includes(NEW_PASSWORD), 'logs must not contain password');
      assert(!captured.logs.includes(OLD_PASSWORD), 'logs must not contain old password');
      assert(!captured.logs.includes(db.state.resets[0].code_hash), 'logs must not contain hash');
      console.log('OK DEV_LOG_RESET_CODE affiche le code, pas dans la réponse HTTP');
    })();

    await (async () => {
      const db = createMemoryDb({ users: [localUser()] });
      process.env.DEV_LOG_RESET_CODE = 'false';
      const captured = await captureLogs(() => requestPasswordReset(forgotBody, depsFor(db)));
      process.env.DEV_LOG_RESET_CODE = 'true';
      assert(!captured.logs.includes(CODE), 'logs must not contain reset code when flag is off');
      assert(!captured.logs.includes(NEW_PASSWORD), 'logs must not contain password');
      assert(!captured.logs.includes(db.state.resets[0].code_hash), 'logs must not contain hash');
      console.log('OK sans DEV_LOG_RESET_CODE: pas de code dans les logs');
    })();

    await (async () => {
      const previousSms = {
        SMS_PROVIDER: process.env.SMS_PROVIDER,
        TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID,
        TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN,
        TWILIO_PHONE_NUMBER: process.env.TWILIO_PHONE_NUMBER,
      };
      process.env.SMS_PROVIDER = 'mock';
      process.env.TWILIO_ACCOUNT_SID = 'ACtestaccountsidnotreal0000000000';
      process.env.TWILIO_AUTH_TOKEN = 'SK_should_never_appear';
      process.env.TWILIO_PHONE_NUMBER = '+15550000000';
      try {
        const db = createMemoryDb({ users: [localUser()] });
        const captured = await captureLogs(() =>
          requestPasswordReset(forgotBody, {
            db,
            generateCode: () => CODE,
            sendSms: smsService.sendSms,
            nowMs: Date.now(),
          })
        );
        assert(captured.result.message === GENERIC_FORGOT_MESSAGE, 'API stays generic');
        assert(captured.logs.includes('[DEV] SMS provider: mock'), 'mock provider log');
        assert(db.state.resets.length === 1, 'reset row inserted before mock send');
        assert(db.state.resets[0].code_hash !== CODE, 'code stays hashed');
        assert(!captured.logs.includes('Unhandled error'), 'SMS mock must not throw unhandled');
      } finally {
        Object.entries(previousSms).forEach(([key, value]) => {
          if (value === undefined) {
            delete process.env[key];
          } else {
            process.env[key] = value;
          }
        });
      }
      console.log('OK forgot + SMS_PROVIDER=mock: pas de Twilio, envoi simulé');
    })();
  } finally {
    if (previousUrl === undefined) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previousUrl;
    }
    if (previousDev === undefined) {
      delete process.env.DEV_LOG_RESET_CODE;
    } else {
      process.env.DEV_LOG_RESET_CODE = previousDev;
    }
  }
}

main()
  .then(() => {
    console.log('Password reset checks passed.');
  })
  .catch((err) => {
    console.error('Password reset checks failed:', err.message);
    process.exitCode = 1;
  });
