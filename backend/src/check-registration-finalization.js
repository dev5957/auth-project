const bcrypt = require('bcrypt');
const { verifyPhoneAndCreateUser } = require('./services/registerService');
const pool = require('./db');

const OTP = '123456';
const TOKEN = 'verification-token-finalization';
const GENERIC_CONFLICT = 'Email, login or phone number is already in use';

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

function registrationData(overrides = {}) {
  return {
    email: 'final@example.com',
    birth_date: '1990-01-15',
    phone_number: '+33600000000',
    login: 'final_user',
    password_hash: 'stored-password-hash',
    first_name: null,
    last_name: null,
    ...overrides,
  };
}

function createMemoryDb({ verification, users = [] }) {
  const state = {
    verification: { ...verification, registration_data: { ...verification.registration_data } },
    users: users.map((user) => ({ ...user })),
    nextUserId: users.reduce((max, user) => Math.max(max, user.id || 0), 0) + 1,
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

    if (key.includes('FROM PHONE_VERIFICATIONS') && key.includes('FOR UPDATE')) {
      await acquireLock();
      const token = params[0];
      if (!state.verification || state.verification.verification_token !== token) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rowCount: 1,
        rows: [
          {
            id: state.verification.id,
            code_hash: state.verification.code_hash,
            expires_at: state.verification.expires_at,
            attempts: state.verification.attempts,
            verified_at: state.verification.verified_at,
            registration_data: { ...state.verification.registration_data },
          },
        ],
      };
    }

    if (key.includes('UPDATE PHONE_VERIFICATIONS') && key.includes('ATTEMPTS')) {
      state.verification.attempts = params[0];
      return { rowCount: 1 };
    }

    if (key.includes('UPDATE PHONE_VERIFICATIONS') && key.includes('VERIFIED_AT')) {
      if (state.verification && state.verification.id === params[0] && !state.verification.verified_at) {
        state.verification.verified_at = new Date();
        return { rowCount: 1 };
      }
      return { rowCount: 0 };
    }

    if (key.includes('DELETE FROM PHONE_VERIFICATIONS')) {
      throw new Error('phone_verifications must not be deleted after successful verify');
    }

    if (key.includes('EXISTS') && key.includes('FROM USERS')) {
      const email = params[0];
      const login = params[1];
      const phone = params[2];
      return {
        rowCount: 1,
        rows: [
          {
            email_taken: state.users.some((user) => user.email === email),
            login_taken: state.users.some((user) => user.login === login),
            phone_taken: state.users.some((user) => user.phone_number === phone),
          },
        ],
      };
    }

    if (key.includes('INSERT INTO USERS')) {
      const email = params[0];
      const phone_number = params[2];
      const login = params[3];
      const auth_provider_literal = key.includes("'LOCAL'");
      assert(auth_provider_literal, 'INSERT users must set auth_provider local');
      if (
        state.users.some(
          (user) => user.email === email || user.login === login || user.phone_number === phone_number
        )
      ) {
        const err = new Error('duplicate');
        err.code = '23505';
        throw err;
      }
      const user = {
        id: state.nextUserId,
        email,
        birth_date: params[1],
        phone_number,
        login,
        password_hash: params[4],
        phone_verified: true,
        auth_provider: 'local',
      };
      state.nextUserId += 1;
      state.users.push(user);
      return {
        rowCount: 1,
        rows: [
          {
            id: user.id,
            email: user.email,
            login: user.login,
            phone_verified: true,
            auth_provider: 'local',
          },
        ],
      };
    }

    throw new Error(`unexpected query: ${sql}`);
  }

  return {
    state,
    pool: {
      connect: async () => ({
        query,
        release() {
          releaseLock();
        },
      }),
    },
  };
}

async function withDb(verification, users, fn) {
  const db = createMemoryDb({ verification, users });
  const originalConnect = pool.connect;
  const originalQuery = pool.query;
  pool.connect = db.pool.connect;
  try {
    return await fn(db.state);
  } finally {
    pool.connect = originalConnect;
    pool.query = originalQuery;
  }
}

async function main() {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousUrl || 'postgres://registration-finalization-test/local';

  const code_hash = await bcrypt.hash(OTP, 10);
  const baseVerification = () => ({
    id: 1,
    verification_token: TOKEN,
    code_hash,
    expires_at: new Date(Date.now() + 60_000),
    attempts: 0,
    verified_at: null,
    registration_data: registrationData(),
  });

  const logs = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args) => {
    logs.push(args.map(String).join(' '));
    originalLog.apply(console, args);
  };
  console.error = (...args) => {
    logs.push(args.map(String).join(' '));
    originalError.apply(console, args);
  };

  try {
    await withDb(baseVerification(), [], async (state) => {
      const user = await verifyPhoneAndCreateUser({ verification_token: TOKEN, code: OTP });
      assert(user.login === 'final_user', 'A: login');
      assert(user.email === 'final@example.com', 'A: email');
      assert(user.phone_verified === true, 'A: phone_verified');
      assert(user.auth_provider === 'local', 'A: auth_provider');
      assert(state.users.length === 1, 'A: one users row');
      assert(state.verification.verified_at, 'A: verified_at must be set');
      assert(state.verification.registration_data.password_hash, 'A: row kept for audit');
      const publicUser = JSON.stringify(user);
      assert(!publicUser.includes('password_hash'), 'A: no password_hash in result');
      assert(!publicUser.includes(code_hash), 'A: no code_hash in result');
      console.log('A OK OTP valide -> creation users + verified_at');
    });

    await withDb(
      {
        ...baseVerification(),
        verified_at: new Date(),
      },
      [{ id: 1, email: 'final@example.com', login: 'final_user', phone_number: '+33600000000' }],
      async (state) => {
        await expectStatus(
          () => verifyPhoneAndCreateUser({ verification_token: TOKEN, code: OTP }),
          400,
          'Verification is no longer valid'
        );
        assert(state.users.length === 1, 'B: must not create a second user');
        console.log('B OK deuxieme utilisation du token -> refus');
      }
    );

    await withDb(baseVerification(), [], async (state) => {
      const results = await Promise.allSettled([
        verifyPhoneAndCreateUser({ verification_token: TOKEN, code: OTP }),
        verifyPhoneAndCreateUser({ verification_token: TOKEN, code: OTP }),
      ]);
      const fulfilled = results.filter((item) => item.status === 'fulfilled');
      const rejected = results.filter((item) => item.status === 'rejected');
      assert(fulfilled.length === 1, `C: expected 1 success, got ${fulfilled.length}`);
      assert(rejected.length === 1, `C: expected 1 refusal, got ${rejected.length}`);
      assert(rejected[0].reason.statusCode === 400, 'C: concurrent loser must be 400');
      assert(state.users.length === 1, 'C: only one users row');
      console.log('C OK validations concurrentes -> une seule creation users');
    });

    await withDb(
      {
        ...baseVerification(),
        expires_at: new Date(Date.now() - 1000),
      },
      [],
      async (state) => {
        await expectStatus(
          () => verifyPhoneAndCreateUser({ verification_token: TOKEN, code: OTP }),
          400,
          'Verification code has expired'
        );
        assert(state.users.length === 0, 'D: expired OTP must not create a user');
        console.log('D OK OTP expire -> refus');
      }
    );

    await withDb(baseVerification(), [], async (state) => {
      await expectStatus(
        () => verifyPhoneAndCreateUser({ verification_token: TOKEN, code: '000000' }),
        400,
        'Invalid verification code'
      );
      assert(state.verification.attempts === 1, `E: attempts should be 1, got ${state.verification.attempts}`);
      assert(state.users.length === 0, 'E: bad code must not create a user');
      console.log('E OK mauvais code -> attempts incremente');
    });

    const conflictCases = [
      {
        label: 'email',
        users: [{ id: 9, email: 'final@example.com', login: 'other', phone_number: '+33611111111' }],
      },
      {
        label: 'login',
        users: [{ id: 10, email: 'other@example.com', login: 'final_user', phone_number: '+33611111111' }],
      },
      {
        label: 'phone',
        users: [{ id: 11, email: 'other@example.com', login: 'other', phone_number: '+33600000000' }],
      },
    ];
    for (const conflict of conflictCases) {
      await withDb(baseVerification(), conflict.users, async (state) => {
        await expectStatus(
          () => verifyPhoneAndCreateUser({ verification_token: TOKEN, code: OTP }),
          409,
          GENERIC_CONFLICT
        );
        assert(state.users.length === 1, `F/${conflict.label}: must not insert another user`);
        assert(!state.verification.verified_at, `F/${conflict.label}: must not consume verification`);
      });
    }
    console.log('F OK conflit email/login/telephone -> 409 generique');
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }

  const capturedLogs = logs.join('\n');
  const forbidden = [
    'stored-password-hash',
    code_hash,
    TOKEN,
    'registration_data',
    OTP,
  ];
  for (const secret of forbidden) {
    assert(!capturedLogs.includes(secret), `G: logs leaked ${secret}`);
  }
  console.log('G OK logs sans code_hash, password_hash, registration_data ni token');

  if (!previousUrl) {
    delete process.env.DATABASE_URL;
  } else {
    process.env.DATABASE_URL = previousUrl;
  }

  console.log('Registration finalization checks succeeded.');
}

main().catch((err) => {
  console.error('Registration finalization checks failed:', err.message);
  process.exitCode = 1;
});
