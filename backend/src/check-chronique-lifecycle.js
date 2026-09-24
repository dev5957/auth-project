const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const { generateAccessToken } = require('./services/tokenService');
const { parsePatchInput, parseRestoreInput } = require('./validators/chroniqueFields');
const AppError = require('./errors/AppError');
const {
  updateChronique,
  archiveChronique,
  restoreChronique,
  deleteChronique,
} = require('./services/chroniqueService');

const TEST_SECRET = 'chronique-lifecycle-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30451;
const OWNER_ID = 42;

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

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function sampleRow(overrides = {}) {
  const now = new Date();
  return {
    id: 1,
    user_id: OWNER_ID,
    theme_id: null,
    title: 'Premier soir',
    body: 'Le texte de la chronique, d au moins vingt caracteres.',
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

function createMemoryDb(rows) {
  const state = {
    rows: rows.map((row) => ({ ...row })),
  };

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes('FOR UPDATE')) {
      const row = state.rows.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('UPDATE PUBLICATIONS')) {
      const id = params[params.length - 2];
      const userId = params[params.length - 1];
      const row = state.rows.find(
        (item) => Number(item.id) === Number(id) && Number(item.user_id) === Number(userId)
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      Object.assign(row, {
        title: params[0],
        body: params[1],
        status: params[2],
        scheduled_at: params[3],
        published_at: params[4],
        archived_at: params[5],
        expired_at: params[6],
        purge_after: params[7],
        deleted_at: params[8],
        is_time_limited: params[9],
        expires_at: params[10],
        theme_id: null,
        is_public: false,
        audience: 'private',
        comments_enabled: false,
        updated_at: new Date(),
      });
      return { rows: [{ ...row }], rowCount: 1 };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  return {
    state,
    async connect() {
      return {
        query,
        release() {},
      };
    },
  };
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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://chronique-lifecycle-test/local';

  expectAppError(() => parsePatchInput({}), 400, 'No fields to update');
  expectAppError(() => parsePatchInput({ status: 'active' }), 400, 'status cannot be set');
  expectAppError(() => parsePatchInput({ user_id: 1, title: 'x' }), 400, 'user_id cannot be set');
  expectAppError(() => parsePatchInput({ is_public: true, title: 'x' }), 400, 'is_public cannot be set');
  expectAppError(
    () => parsePatchInput({ body: 'trop court' }),
    400,
    'body is too short'
  );
  expectAppError(() => parseRestoreInput({ status: 'active' }), 400, 'status cannot be set');
  parsePatchInput({ title: 'Nouveau titre' });
  parseRestoreInput({});
  parseRestoreInput(null);
  console.log('A OK validators patch/restore');

  const activeDb = createMemoryDb([
    sampleRow({
      id: 1,
      status: 'active',
      is_time_limited: true,
      expires_at: new Date(Date.now() + 60 * 60 * 1000),
    }),
  ]);
  const archivedActive = await archiveChronique(OWNER_ID, 1, { db: activeDb });
  assert(archivedActive.status === 'archived', 'archive active status');
  assert(archivedActive.archived_at != null, 'archive active archived_at');
  assert(archivedActive.is_time_limited === false, 'archive clears ephemeral');
  assert(archivedActive.expires_at == null, 'archive clears expires_at');
  console.log('B OK archive active');

  const scheduledDb = createMemoryDb([
    sampleRow({
      id: 2,
      status: 'scheduled',
      scheduled_at: new Date(Date.now() + 60 * 60 * 1000),
      published_at: null,
    }),
  ]);
  const archivedScheduled = await archiveChronique(OWNER_ID, 2, { db: scheduledDb });
  assert(archivedScheduled.status === 'archived', 'archive scheduled status');
  assert(archivedScheduled.scheduled_at == null, 'archive cancels schedule');
  console.log('C OK archive scheduled');

  const draftDb = createMemoryDb([sampleRow({ id: 3, status: 'draft', published_at: null })]);
  await expectStatus(
    () => archiveChronique(OWNER_ID, 3, { db: draftDb }),
    400,
    'Chronique cannot be archived in this status'
  );
  console.log('D OK archive draft refusee');

  const restoreDb = createMemoryDb([
    sampleRow({
      id: 4,
      status: 'archived',
      archived_at: new Date(),
      published_at: new Date('2026-01-01T10:00:00.000Z'),
    }),
  ]);
  const restored = await restoreChronique(OWNER_ID, 4, {}, { db: restoreDb });
  assert(restored.status === 'active', 'restore status');
  assert(restored.archived_at == null, 'restore clears archived_at');
  assert(restored.is_time_limited === false, 'restore default durable');
  assert(restored.published_at === new Date('2026-01-01T10:00:00.000Z').toISOString(), 'keep published_at');
  console.log('E OK restore archived');

  const expiredDb = createMemoryDb([
    sampleRow({
      id: 5,
      status: 'expired',
      expired_at: new Date(),
      published_at: new Date(),
    }),
  ]);
  await expectStatus(
    () => restoreChronique(OWNER_ID, 5, {}, { db: expiredDb }),
    400,
    'Chronique cannot be restored in this status'
  );
  console.log('F OK restore expired refuse');

  const deleteDb = createMemoryDb([sampleRow({ id: 6, status: 'active' })]);
  await deleteChronique(OWNER_ID, 6, { db: deleteDb });
  assert(deleteDb.state.rows[0].status === 'deleted', 'logical delete status');
  assert(deleteDb.state.rows[0].deleted_at != null, 'logical delete deleted_at');
  await expectStatus(
    () => deleteChronique(OWNER_ID, 6, { db: deleteDb }),
    404,
    'Chronique not found'
  );
  console.log('G OK delete logique');

  const foreignDb = createMemoryDb([sampleRow({ id: 7, user_id: 99, status: 'active' })]);
  await expectStatus(
    () => archiveChronique(OWNER_ID, 7, { db: foreignDb }),
    404,
    'Chronique not found'
  );
  await expectStatus(
    () => updateChronique(OWNER_ID, 7, { title: 'Autre' }, { db: foreignDb }),
    404,
    'Chronique not found'
  );
  console.log('H OK ownership refusee');

  const editActiveDb = createMemoryDb([sampleRow({ id: 8, status: 'active' })]);
  await expectStatus(
    () => updateChronique(OWNER_ID, 8, { publish: 'draft' }, { db: editActiveDb }),
    409,
    'Invalid status transition'
  );
  console.log('I OK active ne revient pas en draft');

  const archivedEditDb = createMemoryDb([
    sampleRow({ id: 9, status: 'archived', archived_at: new Date() }),
  ]);
  await expectStatus(
    () => updateChronique(OWNER_ID, 9, { title: 'Nope' }, { db: archivedEditDb }),
    400,
    'Chronique cannot be edited in this status'
  );
  console.log('I2 OK patch archived refuse');

  const expiredArchiveDb = createMemoryDb([
    sampleRow({ id: 10, status: 'expired', expired_at: new Date() }),
  ]);
  await expectStatus(
    () => archiveChronique(OWNER_ID, 10, { db: expiredArchiveDb }),
    400,
    'Chronique cannot be archived in this status'
  );
  const expiredDeleted = createMemoryDb([
    sampleRow({ id: 11, status: 'expired', expired_at: new Date() }),
  ]);
  await deleteChronique(OWNER_ID, 11, { db: expiredDeleted });
  assert(expiredDeleted.state.rows[0].status === 'deleted', 'expired -> deleted');
  console.log('I3 OK expired archive refusee, delete logique');

  const { child, logs } = startTestServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);

    const unauth = await Promise.all([
      httpRequest({ port: TEST_PORT, method: 'PATCH', urlPath: '/chroniques/1', body: { title: 'x' } }),
      httpRequest({ port: TEST_PORT, method: 'POST', urlPath: '/chroniques/1/archive' }),
      httpRequest({ port: TEST_PORT, method: 'POST', urlPath: '/chroniques/1/restore' }),
      httpRequest({ port: TEST_PORT, method: 'DELETE', urlPath: '/chroniques/1' }),
    ]);
    for (const res of unauth) {
      assert(res.status === 401, `auth: ${res.status} ${res.raw}`);
      assert(res.json && res.json.error === 'Unauthorized', res.raw);
    }
    console.log('J OK routes lifecycle sans token -> 401');

    const token = generateAccessToken({
      id: OWNER_ID,
      login: 'chronique_lifecycle',
      auth_provider: 'local',
    });
    const auth = { Authorization: `Bearer ${token}` };

    const missingDb = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques/1/archive',
      headers: auth,
    });
    assert(missingDb.status === 503, `K: archive sans DATABASE_URL ${missingDb.status} ${missingDb.raw}`);
    assert(missingDb.json.error === 'Database is not configured', missingDb.raw);
    console.log('K OK archive sans DATABASE_URL -> 503');
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

  console.log('Chronique lifecycle check succeeded (Lot 2, sans ecrire en base).');
}

main().catch((err) => {
  console.error('Chronique lifecycle check failed:', err.message);
  process.exitCode = 1;
});
