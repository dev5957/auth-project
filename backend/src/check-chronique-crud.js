const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const { generateAccessToken } = require('./services/tokenService');
const { parseCreateInput, parseListQuery, parseChroniqueId } = require('./validators/chroniqueFields');
const AppError = require('./errors/AppError');

const TEST_SECRET = 'chronique-crud-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30450;

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

function validBody(overrides = {}) {
  return {
    title: 'Premier soir',
    body: 'Le texte de la chronique, d au moins vingt caracteres.',
    publish: 'draft',
    ...overrides,
  };
}

async function main() {
  const previous = {
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
  };
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;

  expectAppError(() => parseCreateInput({ body: 'short', publish: 'draft' }), 400, 'body is too short');
  expectAppError(
    () => parseCreateInput({ body: '   ', publish: 'draft' }),
    400,
    'body is required'
  );
  expectAppError(
    () => parseCreateInput({ body: validBody().body, user_id: 1, publish: 'draft' }),
    400,
    'user_id cannot be set'
  );
  expectAppError(
    () => parseCreateInput({ body: validBody().body, status: 'active', publish: 'draft' }),
    400,
    'status cannot be set'
  );
  expectAppError(
    () => parseCreateInput({ body: validBody().body, theme_id: 1, publish: 'draft' }),
    400,
    'theme_id cannot be set'
  );
  expectAppError(
    () => parseCreateInput({ body: validBody().body, is_public: true, publish: 'draft' }),
    400,
    'is_public cannot be set'
  );
  expectAppError(() => parseCreateInput({ body: validBody().body }), 400, 'publish is required');
  expectAppError(
    () => parseCreateInput({ ...validBody(), title: 'x'.repeat(201) }),
    400,
    'title is invalid'
  );
  const created = parseCreateInput(validBody({ publish: 'now' }));
  assert(created.publish === 'now', 'now mode');
  const scheduled = parseCreateInput(
    validBody({
      publish: 'schedule',
      scheduled_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    })
  );
  assert(scheduled.publish === 'schedule', 'schedule mode');
  parseListQuery({ status: 'active' });
  parseListQuery({
    status: 'active',
    before_at: new Date().toISOString(),
    before_id: '10',
  });
  try {
    parseListQuery({ before_id: '1' });
    throw new Error('cursor');
  } catch (err) {
    assert(err.message === 'cursor is incomplete', err.message);
  }
  expectAppError(() => parseChroniqueId('abc'), 400, 'id is invalid');
  console.log('A OK validators create/list/id');

  const { child, logs } = startTestServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);

    const missing = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/chroniques',
    });
    assert(missing.status === 401, `B: GET list ${missing.status} ${missing.raw}`);
    assert(missing.json && missing.json.error === 'Unauthorized', 'B: error');
    console.log('B OK GET /chroniques sans token -> 401');

    const postMissing = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques',
      body: validBody(),
    });
    assert(postMissing.status === 401, `C: POST ${postMissing.status}`);
    console.log('C OK POST /chroniques sans token -> 401');

    const token = generateAccessToken({
      id: 42,
      login: 'chronique_test',
      auth_provider: 'local',
    });
    const auth = { Authorization: `Bearer ${token}` };

    const tooShort = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques',
      headers: auth,
      body: validBody({ body: 'trop court' }),
    });
    assert(tooShort.status === 400, `D: ${tooShort.status} ${tooShort.raw}`);
    assert(tooShort.json.error === 'body is too short', tooShort.raw);
    console.log('D OK POST body trop court -> 400');

    const forbidden = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques',
      headers: auth,
      body: validBody({ user_id: 99 }),
    });
    assert(forbidden.status === 400 && forbidden.json.error === 'user_id cannot be set', forbidden.raw);
    console.log('E OK POST user_id client -> 400');

    const createdHttp = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques',
      headers: auth,
      body: validBody({ publish: 'now' }),
    });
    assert(createdHttp.status === 503, `F: expected 503 without DATABASE_URL, got ${createdHttp.status} ${createdHttp.raw}`);
    assert(createdHttp.json.error === 'Database is not configured', createdHttp.raw);
    console.log('F OK POST valide sans DATABASE_URL -> 503 (migration non appliquée par le test)');

    const other = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/chroniques/1',
      headers: auth,
    });
    assert(other.status === 503, `G: GET id ${other.status}`);
    console.log('G OK GET /chroniques/:id sans DB -> 503');
  } finally {
    await stopServer(child);
    process.env.JWT_SECRET = previous.JWT_SECRET;
    process.env.JWT_ISSUER = previous.JWT_ISSUER;
    process.env.JWT_AUDIENCE = previous.JWT_AUDIENCE;
  }

  console.log('Chronique CRUD check succeeded (Lot 1, sans écrire en base).');
}

main().catch((err) => {
  console.error('Chronique CRUD check failed:', err.message);
  process.exitCode = 1;
});
