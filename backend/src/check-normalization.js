const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const bcrypt = require('bcrypt');
const {
  normalizeEmail,
  normalizeLogin,
  prepareLoginForLookup,
  normalizePhoneNumber,
  EMAIL_MAX_LENGTH,
  LOGIN_MAX_LENGTH,
} = require('./validators/authFields');
const { startLocalRegistration, verifyPhoneAndCreateUser } = require('./services/registerService');
const { loginLocalUser } = require('./services/loginService');
const pool = require('./db');

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

async function withMockedPool({ query, connect }, fn) {
  const originalQuery = pool.query;
  const originalConnect = pool.connect;
  if (query) {
    pool.query = query;
  }
  if (connect) {
    pool.connect = connect;
  }
  try {
    await fn();
  } finally {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

async function testUnitNormalizers() {
  assert(
    normalizeEmail('  Test.User@Example.COM ') === 'test.user@example.com',
    'email example should lowercase and trim'
  );
  assert(normalizeEmail(' Test@Example.COM ') === 'test@example.com', 'A: register email form');
  await expectStatus(() => normalizeEmail('   '), 400, 'email is required');
  await expectStatus(() => normalizeEmail('a'.repeat(EMAIL_MAX_LENGTH + 1)), 400, 'email is invalid');
  console.log('A OK email trim + lowercase, vide et trop long refusés');

  assert(normalizeLogin('  Test_User  ') === 'test_user', 'login example');
  assert(prepareLoginForLookup('TEST_USER') === 'test_user', 'B: login lookup lowercase');
  assert(prepareLoginForLookup('  Test_User  ') === 'test_user', 'B: login lookup trim + lowercase');
  await expectStatus(() => normalizeLogin('   '), 400, 'login is required');
  await expectStatus(() => normalizeLogin('a'.repeat(LOGIN_MAX_LENGTH + 1)), 400, 'login is invalid');
  console.log('B OK login trim + lowercase ; TEST_USER → test_user');

  assert(normalizePhoneNumber('+33 6 12-34-56-78') === '+33612345678', 'phone spaces and hyphens');
  assert(normalizePhoneNumber('+33 6-12-34-56-78') === '+33612345678', 'C: phone hyphens');
  assert(normalizePhoneNumber(' (+33) 6-12-34-56-78 ') === '+33612345678', 'phone parentheses');
  await expectStatus(() => normalizePhoneNumber('   -()  '), 400, 'phone_number is required');
  console.log('C OK téléphone léger → +33612345678');

  assert(
    normalizeEmail(' Test@Example.COM ') === normalizeEmail('test@example.com'),
    'D: equivalent emails collapse'
  );
  assert(normalizeLogin('TEST_USER') === normalizeLogin('  Test_User  '), 'D: equivalent logins collapse');
  assert(
    normalizePhoneNumber('+33 6-12-34-56-78') === normalizePhoneNumber('+33612345678'),
    'D: equivalent phones collapse'
  );
  console.log('D OK formes équivalentes → une seule représentation (pas de doublon logique)');
}

async function testRegisterStoresNormalized() {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousUrl || 'postgres://normalization-test/local';

  let inserted;
  await withMockedPool(
    {
      query: async (sql, params = []) => {
        const key = sqlKey(sql);
        if (key.includes('EXISTS') && key.includes('FROM USERS')) {
          return { rows: [{ email_taken: false, login_taken: false, phone_taken: false }], rowCount: 1 };
        }
        if (key.includes('INSERT INTO PHONE_VERIFICATIONS')) {
          inserted = params;
          return { rows: [], rowCount: 1 };
        }
        throw new Error(`unexpected register query: ${sql}`);
      },
    },
    async () => {
      await startLocalRegistration({
        email: ' Test@Example.COM ',
        birth_date: '1990-01-15',
        login: '  Test_User  ',
        password: 'abcdefgh',
        password_confirmation: 'abcdefgh',
        phone_number: '+33 6-12-34-56-78',
      });
    }
  );

  assert(inserted, 'register should insert phone_verifications');
  assert(inserted[1] === '+33612345678', `phone column stored as ${inserted[1]}`);
  assert(inserted[4].email === 'test@example.com', `email stored as ${inserted[4].email}`);
  assert(inserted[4].login === 'test_user', `login stored as ${inserted[4].login}`);
  assert(inserted[4].phone_number === '+33612345678', `registration_data phone stored as ${inserted[4].phone_number}`);

  if (!previousUrl) {
    delete process.env.DATABASE_URL;
  } else {
    process.env.DATABASE_URL = previousUrl;
  }

  console.log('A OK register/start stocke email/login/téléphone normalisés');
}

async function testLoginLookupUsesNormalizedLogin() {
  const previousUrl = process.env.DATABASE_URL;
  const previousSecret = process.env.JWT_SECRET;
  process.env.DATABASE_URL = previousUrl || 'postgres://normalization-test/local';
  process.env.JWT_SECRET = previousSecret || 'normalization-test-secret';

  let lookedUpLogin;
  await withMockedPool(
    {
      query: async (sql, params = []) => {
        const key = sqlKey(sql);
        if (key.includes('FROM USERS') && key.includes('WHERE LOGIN')) {
          lookedUpLogin = params[0];
          return { rows: [], rowCount: 0 };
        }
        throw new Error(`unexpected login query: ${sql}`);
      },
    },
    async () => {
      await expectStatus(
        () => loginLocalUser({ login: 'TEST_USER', password: 'abcdefgh' }),
        401,
        'Invalid credentials'
      );
    }
  );

  assert(lookedUpLogin === 'test_user', `login lookup used ${lookedUpLogin}`);

  if (!previousUrl) {
    delete process.env.DATABASE_URL;
  } else {
    process.env.DATABASE_URL = previousUrl;
  }
  if (!previousSecret) {
    delete process.env.JWT_SECRET;
  } else {
    process.env.JWT_SECRET = previousSecret;
  }

  console.log('B OK login TEST_USER recherche test_user');
}

async function testVerifyPhoneRenormalizes() {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousUrl || 'postgres://normalization-test/local';

  const code = '123456';
  const code_hash = await bcrypt.hash(code, 10);
  let insertedUser;

  const client = {
    async query(sql, params = []) {
      const key = sqlKey(sql);
      if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
        return { rows: [], rowCount: 0 };
      }
      if (key.includes('FROM PHONE_VERIFICATIONS')) {
        return {
          rowCount: 1,
          rows: [
            {
              id: 1,
              code_hash,
              expires_at: new Date(Date.now() + 60_000),
              attempts: 0,
              verified_at: null,
              registration_data: {
                email: ' Test@Example.COM ',
                birth_date: '1990-01-15',
                phone_number: '+33 6-12-34-56-78',
                login: 'TEST_USER',
                password_hash: 'stored-hash',
                first_name: null,
                last_name: null,
              },
            },
          ],
        };
      }
      if (key.includes('EXISTS') && key.includes('FROM USERS')) {
        return { rows: [{ email_taken: false, login_taken: false, phone_taken: false }], rowCount: 1 };
      }
      if (key.includes('INSERT INTO USERS')) {
        insertedUser = params;
        return {
          rowCount: 1,
          rows: [
            {
              id: 1,
              email: params[0],
              login: params[3],
              phone_verified: true,
              auth_provider: 'local',
            },
          ],
        };
      }
      if (key.includes('DELETE FROM PHONE_VERIFICATIONS')) {
        return { rowCount: 1 };
      }
      throw new Error(`unexpected verify query: ${sql}`);
    },
    release() {},
  };

  await withMockedPool(
    {
      connect: async () => client,
    },
    async () => {
      const user = await verifyPhoneAndCreateUser({
        verification_token: 'token',
        code,
      });
      assert(user.email === 'test@example.com', 'verify-phone user email');
      assert(user.login === 'test_user', 'verify-phone user login');
    }
  );

  assert(insertedUser[0] === 'test@example.com', `users.email inserted as ${insertedUser[0]}`);
  assert(insertedUser[2] === '+33612345678', `users.phone_number inserted as ${insertedUser[2]}`);
  assert(insertedUser[3] === 'test_user', `users.login inserted as ${insertedUser[3]}`);

  if (!previousUrl) {
    delete process.env.DATABASE_URL;
  } else {
    process.env.DATABASE_URL = previousUrl;
  }

  console.log('OK verify-phone re-normalise registration_data avant insert users');
}

function httpRequest(port, method, urlPath, body) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
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
    JWT_SECRET: 'normalization-http-test-secret',
    JWT_ISSUER: 'auth-project',
    JWT_AUDIENCE: 'auth-project-app',
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

async function testHttpAndLogs() {
  const port = 30435;
  const { child, logs } = startTestServer(port);

  try {
    await waitForLog(logs, 'Server listening', 8000);

    const health = await httpRequest(port, 'GET', '/health');
    assert(health.status === 200, `health status ${health.status}`);
    assert(health.json && health.json.status === 'ok', 'health body');

    const register = await httpRequest(port, 'POST', '/auth/register/start', {
      email: ' Test@Example.COM ',
      birth_date: '1990-01-15',
      login: 'TEST_USER',
      password: 'SecretPass1',
      password_confirmation: 'SecretPass1',
      phone_number: '+33 6-12-34-56-78',
    });
    assert(
      register.status === 201 || register.status === 503 || register.status === 409,
      `register/start status ${register.status}`
    );

    const verify = await httpRequest(port, 'POST', '/auth/register/verify-phone', {
      verification_token: 'not-a-real-token',
      code: '123456',
    });
    assert(
      verify.status === 404 || verify.status === 503,
      `verify-phone status ${verify.status}`
    );

    const login = await httpRequest(port, 'POST', '/auth/login', {
      login: 'TEST_USER',
      password: 'SecretPass1',
    });
    assert(
      login.status === 401 || login.status === 503,
      `login status ${login.status}`
    );

    const refresh = await httpRequest(port, 'POST', '/auth/refresh', {});
    assert(refresh.status === 400, `refresh status ${refresh.status}`);
    assert(refresh.json && refresh.json.error === 'refresh_token is required', 'refresh validation');

    const combinedLogs = logs.join('');
    const forbidden = [
      'Test@Example.COM',
      'test@example.com',
      '+33 6-12-34-56-78',
      '+33612345678',
      'SecretPass1',
    ];
    for (const secret of forbidden) {
      assert(!combinedLogs.includes(secret), `logs leaked sensitive value: ${secret}`);
    }

    console.log('E OK GET /health, register/start, verify-phone, login, refresh');
    console.log('F OK logs sans email complet, téléphone complet ni mot de passe');
  } finally {
    child.kill('SIGTERM');
    await new Promise((resolve) => {
      const t = setTimeout(() => {
        child.kill('SIGKILL');
        resolve();
      }, 2000);
      child.on('exit', () => {
        clearTimeout(t);
        resolve();
      });
    });
  }
}

async function main() {
  await testUnitNormalizers();
  await testRegisterStoresNormalized();
  await testLoginLookupUsesNormalizedLogin();
  await testVerifyPhoneRenormalizes();
  await testHttpAndLogs();
  console.log('Normalization checks succeeded.');
}

main().catch((err) => {
  console.error('Normalization checks failed:', err.message);
  process.exitCode = 1;
});
