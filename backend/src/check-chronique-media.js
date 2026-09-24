const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const { parseUploadInput, parseMediaOrder } = require('./validators/mediaFields');
const mockStorage = require('./services/mockStorageService');
const {
  createMediaUpload,
  completeMedia,
  deleteMedia,
  MAX_MEDIA,
  MAX_BYTES,
} = require('./services/chroniqueMediaService');

const TEST_SECRET = 'chronique-media-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30452;
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

function samplePublication(overrides = {}) {
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

function createMemoryDb({ publications = [], media = [] } = {}) {
  const state = {
    publications: publications.map((row) => ({ ...row })),
    media: media.map((row) => ({ ...row })),
  };
  let nextMediaId = state.media.reduce((max, row) => Math.max(max, Number(row.id) || 0), 0) + 1;

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes('FOR UPDATE')) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM PUBLICATION_MEDIA') && key.includes('COUNT(*)') && key.includes('SUM(BYTE_SIZE)')) {
      const counted = state.media.filter(
        (item) =>
          Number(item.publication_id) === Number(params[0]) &&
          (item.status === 'pending_upload' || item.status === 'ready')
      );
      const bytes = counted.reduce((sum, item) => sum + Number(item.byte_size), 0);
      return {
        rows: [{ media_count: counted.length, media_bytes: bytes }],
        rowCount: 1,
      };
    }

    if (key.includes('COALESCE(MAX(SORT_ORDER)')) {
      const ready = state.media.filter(
        (item) => Number(item.publication_id) === Number(params[0]) && item.status === 'ready'
      );
      const maxOrder = ready.reduce((max, item) => Math.max(max, Number(item.sort_order)), -1);
      return { rows: [{ max_order: maxOrder }], rowCount: 1 };
    }

    if (key.startsWith('INSERT INTO PUBLICATION_MEDIA')) {
      const row = {
        id: nextMediaId,
        publication_id: params[0],
        kind: params[1],
        source_type: params[2],
        storage_key: params[3],
        content_type: params[4],
        byte_size: params[5],
        original_filename: params[6],
        sort_order: 0,
        status: 'pending_upload',
        created_at: new Date(),
      };
      nextMediaId += 1;
      state.media.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.includes('UPDATE PUBLICATIONS') && key.includes('MEDIA_TOTAL_BYTES')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.media_total_bytes = params[0];
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (
      key.includes('FROM PUBLICATION_MEDIA') &&
      key.includes('FOR UPDATE') &&
      key.includes('AND PUBLICATION_ID') &&
      key.includes('WHERE ID')
    ) {
      const row = state.media.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.publication_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM PUBLICATION_MEDIA') && key.includes("STATUS = 'READY'") && key.includes('FOR UPDATE')) {
      const rows = state.media
        .filter((item) => Number(item.publication_id) === Number(params[0]) && item.status === 'ready')
        .sort((a, b) => a.sort_order - b.sort_order || a.id - b.id)
        .map((item) => ({ id: item.id }));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM PUBLICATION_MEDIA') && key.includes('ORDER BY SORT_ORDER')) {
      const rows = state.media
        .filter((item) => Number(item.publication_id) === Number(params[0]))
        .sort((a, b) => a.sort_order - b.sort_order || a.id - b.id)
        .map((item) => ({ ...item }));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('UPDATE PUBLICATION_MEDIA') && key.includes("STATUS = 'FAILED'")) {
      const row = state.media.find((item) => Number(item.id) === Number(params[0]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'failed';
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.includes('UPDATE PUBLICATION_MEDIA') && key.includes("STATUS = 'READY'")) {
      const row = state.media.find((item) => Number(item.id) === Number(params[1]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'ready';
      row.sort_order = params[0];
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.includes('UPDATE PUBLICATION_MEDIA') && key.includes('SORT_ORDER + 100000')) {
      for (const row of state.media) {
        if (Number(row.publication_id) === Number(params[0]) && row.status === 'ready') {
          row.sort_order += 100000;
        }
      }
      return { rows: [], rowCount: 1 };
    }

    if (
      key.includes('UPDATE PUBLICATION_MEDIA') &&
      key.includes('SET SORT_ORDER') &&
      key.includes("STATUS = 'READY'")
    ) {
      const row = state.media.find(
        (item) =>
          Number(item.id) === Number(params[1]) &&
          Number(item.publication_id) === Number(params[2]) &&
          item.status === 'ready'
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.sort_order = params[0];
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('DELETE FROM PUBLICATION_MEDIA')) {
      const index = state.media.findIndex((item) => Number(item.id) === Number(params[0]));
      if (index < 0) {
        return { rows: [], rowCount: 0 };
      }
      state.media.splice(index, 1);
      return { rows: [], rowCount: 1 };
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

function validUpload(overrides = {}) {
  return {
    kind: 'image',
    source_type: 'camera',
    content_type: 'image/jpeg',
    byte_size: 1024,
    original_filename: 'soir.jpg',
    ...overrides,
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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://chronique-media-test/local';
  mockStorage.reset();

  expectAppError(() => parseUploadInput({}), 400, 'kind is required');
  expectAppError(() => parseUploadInput({ kind: 'image' }), 400, 'source_type is required');
  expectAppError(
    () => parseUploadInput({ kind: 'document', source_type: 'camera', content_type: 'application/pdf', byte_size: 10 }),
    400,
    'source_type is invalid'
  );
  expectAppError(
    () => parseUploadInput({ kind: 'document', source_type: 'upload', content_type: 'image/jpeg', byte_size: 10 }),
    400,
    'content_type is invalid'
  );
  expectAppError(
    () => parseUploadInput({ ...validUpload(), user_id: 1 }),
    400,
    'user_id cannot be set'
  );
  const documentOk = parseUploadInput({
    kind: 'document',
    source_type: 'upload',
    content_type: 'application/pdf',
    byte_size: 2048,
    original_filename: 'note.pdf',
  });
  assert(documentOk.kind === 'document', 'document kind');
  expectAppError(() => parseMediaOrder({ media_ids: [] }), 400, 'media_ids is invalid');
  console.log('A OK validators media / document');

  const db = createMemoryDb({ publications: [samplePublication()] });
  const created = await createMediaUpload(OWNER_ID, 1, validUpload(), { db, storage: mockStorage });
  assert(created.media.status === 'pending_upload', 'pending status');
  assert(created.media.kind === 'image', 'kind');
  assert(created.upload.method === 'PUT', 'upload method');
  assert(String(created.upload.url).startsWith('https://mock-storage.local/upload/'), 'mock url');
  assert(created.media.storage_key == null, 'storage_key must not be public');
  const stored = db.state.media[0];
  assert(stored.status === 'pending_upload', 'row pending');
  assert(stored.storage_key.includes('publications/1/media/'), 'opaque key');
  console.log('B OK creation pending_upload + mock storage');

  await expectStatus(
    () => completeMedia(OWNER_ID, 1, stored.id, { db, storage: mockStorage }),
    400,
    'Upload is incomplete'
  );
  assert(db.state.media[0].status === 'failed', 'incomplete -> failed');
  console.log('C OK complete incomplet -> failed');

  const created2 = await createMediaUpload(
    OWNER_ID,
    1,
    validUpload({ original_filename: 'ok.jpg', byte_size: 2048 }),
    { db, storage: mockStorage }
  );
  const pending = db.state.media.find((row) => row.status === 'pending_upload');
  mockStorage.put(pending.storage_key, { byteSize: 2048, contentType: 'image/jpeg' });
  const readyChronique = await completeMedia(OWNER_ID, 1, pending.id, { db, storage: mockStorage });
  assert(readyChronique.media.some((item) => item.status === 'ready' && item.id === pending.id), 'ready media');
  assert(readyChronique.media.every((item) => item.storage_key == null), 'no storage_key in chronique');
  console.log('D OK complete ready');

  const pdf = await createMediaUpload(
    OWNER_ID,
    1,
    {
      kind: 'document',
      source_type: 'upload',
      content_type: 'application/pdf',
      byte_size: 100,
      original_filename: 'contrat.pdf',
    },
    { db, storage: mockStorage }
  );
  assert(pdf.media.kind === 'document', 'document created');
  assert(pdf.media.source_type === 'upload', 'document source');
  console.log('E OK validation document');

  const quotaDb = createMemoryDb({
    publications: [samplePublication({ id: 2, media_total_bytes: MAX_BYTES })],
    media: [
      {
        id: 50,
        publication_id: 2,
        kind: 'video',
        source_type: 'upload',
        storage_key: 'publications/2/media/full',
        content_type: 'video/mp4',
        byte_size: MAX_BYTES,
        original_filename: 'full.mp4',
        sort_order: 0,
        status: 'ready',
        created_at: new Date(),
      },
    ],
  });
  await expectStatus(
    () => createMediaUpload(OWNER_ID, 2, validUpload({ byte_size: 1 }), { db: quotaDb, storage: mockStorage }),
    400,
    'Media quota exceeded'
  );

  const many = [];
  for (let i = 0; i < MAX_MEDIA; i += 1) {
    many.push({
      id: 100 + i,
      publication_id: 3,
      kind: 'image',
      source_type: 'gallery',
      storage_key: `publications/3/media/${i}`,
      content_type: 'image/png',
      byte_size: 10,
      original_filename: `n${i}.png`,
      sort_order: i,
      status: 'ready',
      created_at: new Date(),
    });
  }
  const countDb = createMemoryDb({
    publications: [samplePublication({ id: 3, media_total_bytes: MAX_MEDIA * 10 })],
    media: many,
  });
  await expectStatus(
    () => createMediaUpload(OWNER_ID, 3, validUpload(), { db: countDb, storage: mockStorage }),
    400,
    'Too many media'
  );
  console.log('F OK quota 20 / 200 Mio');

  const beforeDelete = db.state.media.length;
  const toDelete = db.state.media.find((row) => row.status === 'ready');
  await deleteMedia(OWNER_ID, 1, toDelete.id, { db, storage: mockStorage });
  assert(db.state.media.length === beforeDelete - 1, 'media row removed');
  assert(mockStorage.getObject(toDelete.storage_key) == null, 'mock object deleted');
  console.log('G OK suppression media + mock delete');

  const foreign = createMemoryDb({
    publications: [samplePublication({ id: 9, user_id: 99 })],
  });
  await expectStatus(
    () => createMediaUpload(OWNER_ID, 9, validUpload(), { db: foreign, storage: mockStorage }),
    404,
    'Chronique not found'
  );
  console.log('H OK ownership refusee');

  const { child, logs } = startTestServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);

    const unauth = await Promise.all([
      httpRequest({
        port: TEST_PORT,
        method: 'POST',
        urlPath: '/chroniques/1/media/uploads',
        body: validUpload(),
      }),
      httpRequest({
        port: TEST_PORT,
        method: 'POST',
        urlPath: '/chroniques/1/media/7/complete',
      }),
      httpRequest({
        port: TEST_PORT,
        method: 'DELETE',
        urlPath: '/chroniques/1/media/7',
      }),
      httpRequest({
        port: TEST_PORT,
        method: 'PATCH',
        urlPath: '/chroniques/1/media/order',
        body: { media_ids: [1] },
      }),
    ]);
    for (const res of unauth) {
      assert(res.status === 401, `auth: ${res.status} ${res.raw}`);
      assert(res.json && res.json.error === 'Unauthorized', res.raw);
    }
    console.log('I OK routes media sans token -> 401');

    const token = generateAccessToken({
      id: OWNER_ID,
      login: 'chronique_media',
      auth_provider: 'local',
    });
    const missingDb = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques/1/media/uploads',
      headers: { Authorization: `Bearer ${token}` },
      body: validUpload(),
    });
    assert(missingDb.status === 503, `J: ${missingDb.status} ${missingDb.raw}`);
    assert(missingDb.json.error === 'Database is not configured', missingDb.raw);
    console.log('J OK upload sans DATABASE_URL -> 503');
  } finally {
    await stopServer(child);
    mockStorage.reset();
    process.env.JWT_SECRET = previous.JWT_SECRET;
    process.env.JWT_ISSUER = previous.JWT_ISSUER;
    process.env.JWT_AUDIENCE = previous.JWT_AUDIENCE;
    if (!previous.DATABASE_URL) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previous.DATABASE_URL;
    }
  }

  console.log('Chronique media check succeeded (Lot 3A, mock storage, sans R2).');
}

main().catch((err) => {
  console.error('Chronique media check failed:', err.message);
  process.exitCode = 1;
});
