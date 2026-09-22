const http = require('http');
const express = require('express');
const { generateAccessToken } = require('./services/tokenService');
const mockStorage = require('./services/mockStorageService');
const pool = require('./db');
const errorHandler = require('./middleware/errorHandler');
const { corsMiddleware } = require('./middleware/cors');
const chroniqueRoutes = require('./routes/chroniques');

const TEST_SECRET = 'chronique-full-flow-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30453;
const OWNER_ID = 42;
const OTHER_ID = 99;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function createMemoryDb() {
  const state = {
    publications: [],
    media: [],
  };
  let nextPubId = 1;
  let nextMediaId = 1;

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO PUBLICATIONS')) {
      const now = new Date();
      const row = {
        id: nextPubId,
        user_id: params[0],
        theme_id: null,
        title: params[1],
        body: params[2],
        status: params[3],
        scheduled_at: params[4],
        published_at: params[5],
        archived_at: null,
        expired_at: null,
        purge_after: null,
        deleted_at: null,
        is_time_limited: params[6] === true,
        expires_at: params[7],
        is_public: false,
        audience: 'private',
        comments_enabled: false,
        media_total_bytes: 0,
        created_at: now,
        updated_at: now,
      };
      nextPubId += 1;
      state.publications.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes('FOR UPDATE')) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes("STATUS <> 'DELETED'")) {
      const row = state.publications.find(
        (item) =>
          Number(item.id) === Number(params[0]) &&
          Number(item.user_id) === Number(params[1]) &&
          item.status !== 'deleted'
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

    if (key.includes('UPDATE PUBLICATIONS') && key.includes('SET TITLE')) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[11]) && Number(item.user_id) === Number(params[12])
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
    query,
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

function storageKeyFromUploadUrl(url) {
  const marker = '/upload/';
  const index = String(url).indexOf(marker);
  assert(index >= 0, `upload url is not mock storage: ${url}`);
  return decodeURIComponent(String(url).slice(index + marker.length));
}

function assertNoSecrets(payload, raw) {
  const text = `${JSON.stringify(payload)}\n${raw}`;
  assert(!text.includes('storage_key'), 'leaked storage_key');
  assert(!/"user_id"/.test(text), 'leaked user_id');
  assert(!text.includes('deleted_at'), 'leaked deleted_at');
  assert(!text.includes(TEST_SECRET), 'leaked JWT secret');
  assert(!text.includes('r2.cloudflarestorage.com'), 'leaked R2 hostname');
  assert(!text.includes('AKIA'), 'leaked cloud credential');
}

const MEDIA_SPECS = [
  {
    kind: 'image',
    source_type: 'gallery',
    content_type: 'image/jpeg',
    byte_size: 1111,
    original_filename: 'soir.jpg',
  },
  {
    kind: 'video',
    source_type: 'camera',
    content_type: 'video/mp4',
    byte_size: 2222,
    original_filename: 'marche.mp4',
  },
  {
    kind: 'document',
    source_type: 'upload',
    content_type: 'application/pdf',
    byte_size: 3333,
    original_filename: 'note.pdf',
  },
];

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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://chronique-full-flow-test/local';

  mockStorage.reset();
  const storageCalls = { createDirectUpload: 0, head: 0, delete: 0 };
  const origCreate = mockStorage.createDirectUpload.bind(mockStorage);
  const origHead = mockStorage.head.bind(mockStorage);
  const origDelete = mockStorage.delete.bind(mockStorage);
  mockStorage.createDirectUpload = (args) => {
    storageCalls.createDirectUpload += 1;
    assert(args && String(args.storageKey).includes('publications/'), 'storage_key opaque');
    const upload = origCreate(args);
    assert(String(upload.url).startsWith('https://mock-storage.local/upload/'), 'mock upload url');
    return upload;
  };
  mockStorage.head = async (storageKey) => {
    storageCalls.head += 1;
    return origHead(storageKey);
  };
  mockStorage.delete = async (storageKey) => {
    storageCalls.delete += 1;
    return origDelete(storageKey);
  };

  const memory = createMemoryDb();
  pool.query = (sql, params) => memory.query(sql, params);
  pool.connect = () => memory.connect();

  const app = express();
  app.use(corsMiddleware);
  app.use(express.json({ limit: '32kb' }));
  app.use('/chroniques', chroniqueRoutes);
  app.use(errorHandler);

  const server = await new Promise((resolve) => {
    const httpServer = app.listen(TEST_PORT, '127.0.0.1', () => resolve(httpServer));
  });

  try {
    const token = generateAccessToken({
      id: OWNER_ID,
      login: 'chronique_full_flow',
      auth_provider: 'local',
    });
    const auth = { Authorization: `Bearer ${token}` };
    const otherToken = generateAccessToken({
      id: OTHER_ID,
      login: 'chronique_stranger',
      auth_provider: 'local',
    });
    const otherAuth = { Authorization: `Bearer ${otherToken}` };

    const created = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques',
      headers: auth,
      body: {
        title: 'Soir de rentre',
        body: 'Le texte de la chronique, d au moins vingt caracteres.',
        publish: 'now',
      },
    });
    assert(created.status === 201, `create ${created.status} ${created.raw}`);
    assert(created.json.chronique.status === 'active', 'created active');
    assert(created.json.chronique.id, 'created id');
    assertNoSecrets(created.json, created.raw);
    const chroniqueId = created.json.chronique.id;
    console.log('A OK POST /chroniques active');

    const uploaded = [];
    for (const spec of MEDIA_SPECS) {
      const init = await httpRequest({
        port: TEST_PORT,
        method: 'POST',
        urlPath: `/chroniques/${chroniqueId}/media/uploads`,
        headers: auth,
        body: spec,
      });
      assert(init.status === 201, `upload ${spec.kind} ${init.status} ${init.raw}`);
      assert(init.json.media.status === 'pending_upload', `${spec.kind} pending`);
      assert(init.json.media.kind === spec.kind, `${spec.kind} kind`);
      assert(init.json.media.source_type === spec.source_type, `${spec.kind} source`);
      assert(init.json.upload.method === 'PUT', 'upload method');
      assertNoSecrets(init.json, init.raw);

      const storageKey = storageKeyFromUploadUrl(init.json.upload.url);
      mockStorage.put(storageKey, { byteSize: spec.byte_size, contentType: spec.content_type });

      const complete = await httpRequest({
        port: TEST_PORT,
        method: 'POST',
        urlPath: `/chroniques/${chroniqueId}/media/${init.json.media.id}/complete`,
        headers: auth,
      });
      assert(complete.status === 200, `complete ${spec.kind} ${complete.status} ${complete.raw}`);
      const ready = complete.json.chronique.media.find((item) => item.id === init.json.media.id);
      assert(ready && ready.status === 'ready', `${spec.kind} ready`);
      assertNoSecrets(complete.json, complete.raw);
      uploaded.push({ ...spec, id: init.json.media.id, storageKey });
    }
    assert(storageCalls.createDirectUpload === 3, `uploads ${storageCalls.createDirectUpload}`);
    assert(storageCalls.head === 3, `heads ${storageCalls.head}`);
    console.log('B OK 3 medias pending -> ready via MockStorage');

    const read = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: `/chroniques/${chroniqueId}`,
      headers: auth,
    });
    assert(read.status === 200, `GET ${read.status} ${read.raw}`);
    assert(read.json.chronique.title === 'Soir de rentre', 'title');
    assert(read.json.chronique.status === 'active', 'status');
    assert(read.json.chronique.body.includes('vingt'), 'body');
    assert(Array.isArray(read.json.chronique.media), 'media array');
    assert(read.json.chronique.media.length === 3, `media count ${read.json.chronique.media.length}`);
    const kinds = read.json.chronique.media.map((item) => item.kind).sort().join(',');
    assert(kinds === 'document,image,video', `kinds ${kinds}`);
    assert(
      read.json.chronique.media.every((item) => item.status === 'ready'),
      'all ready'
    );
    assertNoSecrets(read.json, read.raw);
    console.log('C OK GET chronique + medias sans secrets');

    const unauth = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: `/chroniques/${chroniqueId}/media/uploads`,
      body: MEDIA_SPECS[0],
    });
    assert(unauth.status === 401, `unauth ${unauth.status}`);
    assert(unauth.json.error === 'Unauthorized', unauth.raw);

    const stranger = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: `/chroniques/${chroniqueId}`,
      headers: otherAuth,
    });
    assert(stranger.status === 404, `other GET ${stranger.status} ${stranger.raw}`);
    assert(stranger.json.error === 'Chronique not found', stranger.raw);

    const badDoc = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: `/chroniques/${chroniqueId}/media/uploads`,
      headers: auth,
      body: {
        kind: 'document',
        source_type: 'camera',
        content_type: 'application/pdf',
        byte_size: 10,
        original_filename: 'x.pdf',
      },
    });
    assert(badDoc.status === 400, `bad document ${badDoc.status} ${badDoc.raw}`);
    assert(badDoc.json.error === 'source_type is invalid', badDoc.raw);
    console.log('D OK refus 401 / ownership 404 / document source_type');

    const readyIds = read.json.chronique.media
      .slice()
      .sort((a, b) => a.sort_order - b.sort_order)
      .map((item) => item.id);
    const reversed = readyIds.slice().reverse();
    const ordered = await httpRequest({
      port: TEST_PORT,
      method: 'PATCH',
      urlPath: `/chroniques/${chroniqueId}/media/order`,
      headers: auth,
      body: { media_ids: reversed },
    });
    assert(ordered.status === 200, `order ${ordered.status} ${ordered.raw}`);
    const afterOrder = ordered.json.chronique.media
      .filter((item) => item.status === 'ready')
      .sort((a, b) => a.sort_order - b.sort_order)
      .map((item) => item.id);
    assert(JSON.stringify(afterOrder) === JSON.stringify(reversed), `order ${afterOrder}`);
    console.log('E OK PATCH media/order');

    const removedId = uploaded[1].id;
    const removedKey = uploaded[1].storageKey;
    const deleted = await httpRequest({
      port: TEST_PORT,
      method: 'DELETE',
      urlPath: `/chroniques/${chroniqueId}/media/${removedId}`,
      headers: auth,
    });
    assert(deleted.status === 200, `delete media ${deleted.status} ${deleted.raw}`);
    assert(!deleted.json.chronique.media.some((item) => item.id === removedId), 'media gone');
    assert(mockStorage.getObject(removedKey) == null, 'mock object deleted');
    assert(storageCalls.delete === 1, `delete calls ${storageCalls.delete}`);
    console.log('F OK DELETE media + MockStorage.delete');

    const archived = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: `/chroniques/${chroniqueId}/archive`,
      headers: auth,
    });
    assert(archived.status === 200, `archive ${archived.status} ${archived.raw}`);
    assert(archived.json.chronique.status === 'archived', 'archived status');

    const afterArchive = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: `/chroniques/${chroniqueId}/media/uploads`,
      headers: auth,
      body: MEDIA_SPECS[0],
    });
    assert(afterArchive.status === 400, `media after archive ${afterArchive.status}`);
    assert(
      afterArchive.json.error === 'Chronique cannot accept media in this status',
      afterArchive.raw
    );

    const otherArchive = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: `/chroniques/${chroniqueId}/archive`,
      headers: otherAuth,
    });
    assert(otherArchive.status === 404, `other archive ${otherArchive.status}`);
    console.log('G OK archive apres medias + refus post-archive');

    assert(storageCalls.createDirectUpload === 3, 'no extra upload after refusals');
    assert(storageCalls.head === 3, 'no extra head');
    assert(storageCalls.delete === 1, 'single mock delete');
    console.log('H OK MockStorage appels attendus (3 upload, 3 head, 1 delete)');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    mockStorage.createDirectUpload = origCreate;
    mockStorage.head = origHead;
    mockStorage.delete = origDelete;
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

  console.log('Chronique full-flow check succeeded (HTTP + MockStorage, sans R2 ni migration).');
}

main().catch((err) => {
  console.error('Chronique full-flow check failed:', err.message);
  process.exitCode = 1;
});
