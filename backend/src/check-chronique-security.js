const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const { parseCreateInput } = require('./validators/chroniqueFields');
const {
  getChroniqueById,
  updateChronique,
  listChroniques,
  deleteChronique,
} = require('./services/chroniqueService');
const { createPublicationsMemory } = require('./check-chronique-memory');

const TEST_SECRET = 'chronique-security-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30452;
const OWNER_ID = 42;
const STRANGER_ID = 99;
const BODY = 'Le texte de la chronique, d au moins vingt caracteres.';

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

async function expectStatus(fn, statusCode, message) {
  try {
    await fn();
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err && err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    assert(err.message === message, `unexpected message: ${err.message}`);
  }
}

function httpRequest({ port, method, urlPath, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const payload = body == null ? null : Buffer.from(JSON.stringify(body), 'utf8');
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers: {
          ...headers,
          ...(payload
            ? { 'Content-Type': 'application/json', 'Content-Length': String(payload.length) }
            : {}),
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
    if (payload) {
      req.write(payload);
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

function sampleRow(overrides = {}) {
  const now = new Date();
  return {
    id: 1,
    user_id: OWNER_ID,
    theme_id: null,
    title: 'Premier soir',
    body: BODY,
    status: 'active',
    scheduled_at: null,
    published_at: now,
    archived_at: null,
    expired_at: null,
    purge_after: null,
    deleted_at: null,
    is_time_limited: false,
    expires_at: null,
    is_public: false,
    audience: 'private',
    comments_enabled: false,
    media_total_bytes: 0,
    created_at: now,
    updated_at: now,
    ...overrides,
  };
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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://chronique-security-test/local';

  expectAppError(
    () => parseCreateInput({ body: BODY, publish: 'now', user_id: STRANGER_ID }),
    400,
    'user_id cannot be set'
  );
  expectAppError(
    () => parseCreateInput({ body: BODY, publish: 'now', theme_id: 3 }),
    400,
    'theme_id cannot be set'
  );
  console.log('A OK user_id injecte refuse');

  const db = createPublicationsMemory([
    sampleRow({ id: 1, user_id: OWNER_ID }),
    sampleRow({ id: 2, user_id: STRANGER_ID, title: 'Pas a toi' }),
    sampleRow({ id: 3, user_id: OWNER_ID, status: 'deleted', deleted_at: new Date() }),
  ]);

  await expectStatus(
    () => getChroniqueById(OWNER_ID, 2, { db }),
    404,
    'Chronique not found'
  );
  await expectStatus(
    () => updateChronique(OWNER_ID, 2, { title: 'Hack' }, { db }),
    404,
    'Chronique not found'
  );
  await expectStatus(
    () => deleteChronique(OWNER_ID, 2, { db }),
    404,
    'Chronique not found'
  );
  await expectStatus(
    () => getChroniqueById(OWNER_ID, 3, { db }),
    404,
    'Chronique not found'
  );

  const listed = await listChroniques(OWNER_ID, { status: 'active' }, { db });
  assert(listed.items.length === 1, 'list own only');
  assert(listed.items[0].id === 1, 'list own id');
  assert(!listed.items.some((item) => item.id === 2), 'stranger hidden');
  console.log('B OK acces autre user et deleted -> 404');

  const { child, logs } = startTestServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);

    const routes = [
      { method: 'POST', urlPath: '/chroniques', body: { body: BODY, publish: 'now' } },
      { method: 'GET', urlPath: '/chroniques' },
      { method: 'GET', urlPath: '/chroniques/1' },
      { method: 'PATCH', urlPath: '/chroniques/1', body: { title: 'x' } },
      { method: 'POST', urlPath: '/chroniques/1/archive' },
      { method: 'POST', urlPath: '/chroniques/1/restore' },
      { method: 'DELETE', urlPath: '/chroniques/1' },
    ];

    for (const route of routes) {
      const res = await httpRequest({ port: TEST_PORT, ...route });
      assert(res.status === 401, `${route.method} ${route.urlPath} ${res.status} ${res.raw}`);
      assert(res.json && res.json.error === 'Unauthorized', res.raw);
    }
    console.log('C OK absence JWT -> 401 sur toutes les routes Chronique');

    const token = generateAccessToken({
      id: OWNER_ID,
      login: 'chronique_security',
      auth_provider: 'local',
    });
    const injected = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques',
      headers: { Authorization: `Bearer ${token}` },
      body: { body: BODY, publish: 'now', user_id: STRANGER_ID },
    });
    assert(injected.status === 400, `inject status ${injected.status}`);
    assert(injected.json.error === 'user_id cannot be set', injected.raw);
    console.log('D OK POST user_id client avec JWT -> 400');
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

  console.log('Chronique security check succeeded.');
}

main().catch((err) => {
  console.error('Chronique security check failed:', err.message);
  process.exitCode = 1;
});
