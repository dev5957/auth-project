const { getChroniqueById, listChroniques } = require('./services/chroniqueService');
const AppError = require('./errors/AppError');

const OWNER_A = 11;
const OWNER_B = 22;
const BODY = 'Le texte de la chronique, d au moins vingt caracteres.';
const SECRET = 'r2-read-lot-secret-must-never-appear';

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
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

function publicationRow(overrides = {}) {
  const now = new Date('2026-09-25T10:00:00.000Z');
  return {
    id: 1,
    user_id: OWNER_A,
    theme_id: null,
    title: 'Lecture R2',
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

function mediaRow(overrides = {}) {
  return {
    id: 1,
    publication_id: 1,
    kind: 'image',
    source_type: 'gallery',
    storage_key: 'publications/1/media/ready-image',
    content_type: 'image/jpeg',
    byte_size: 12345,
    original_filename: 'soir.jpg',
    sort_order: 0,
    status: 'ready',
    created_at: new Date('2026-09-25T10:01:00.000Z'),
    ...overrides,
  };
}

function createMemory({ publications, media }) {
  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key.includes('FROM PUBLICATIONS') && key.includes("STATUS <> 'DELETED'") && key.includes('LIMIT 1')) {
      const row = publications.find(
        (item) =>
          Number(item.id) === Number(params[0]) &&
          Number(item.user_id) === Number(params[1]) &&
          item.status !== 'deleted'
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes('WHERE USER_ID = $1') && key.includes('AND STATUS = $2')) {
      const userId = params[0];
      const status = params[1];
      const limit = Number(params[params.length - 1]);
      const rows = publications
        .filter((item) => Number(item.user_id) === Number(userId) && item.status === status)
        .slice(0, limit)
        .map((item) => ({ ...item }));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM PUBLICATION_MEDIA') && key.includes('ORDER BY SORT_ORDER')) {
      const rows = media
        .filter((item) => Number(item.publication_id) === Number(params[0]))
        .sort((a, b) => Number(a.sort_order) - Number(b.sort_order) || Number(a.id) - Number(b.id))
        .map((item) => ({ ...item }));
      return { rows, rowCount: rows.length };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  return {
    query,
    async connect() {
      return {
        query,
        release() {},
      };
    },
  };
}

function createStorageSpy() {
  const signedKeys = [];
  return {
    signedKeys,
    createDirectUpload() {
      throw new Error('createDirectUpload must not run on GET');
    },
    async head() {
      throw new Error('head must not run on GET');
    },
    async delete() {
      throw new Error('delete must not run on GET');
    },
    async createReadUrl(storageKey) {
      signedKeys.push(storageKey);
      return {
        method: 'GET',
        url: `https://mock-storage.local/read/${encodeURIComponent(storageKey)}`,
        expires_at: '2026-09-25T10:16:00.000Z',
      };
    },
  };
}

function assertPublicMedia(item) {
  const text = JSON.stringify(item);
  assert(!Object.prototype.hasOwnProperty.call(item, 'storage_key'), 'storage_key field');
  assert(!text.includes('"storage_key"'), 'storage_key json');
  assert(!text.includes(SECRET), 'secret leaked');
}

async function main() {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://chronique-read-url-test/local';

  const ready = mediaRow();
  const storage = createStorageSpy();
  const db = createMemory({
    publications: [publicationRow({ media_total_bytes: ready.byte_size })],
    media: [ready],
  });

  const fetched = await getChroniqueById(OWNER_A, 1, { db, storage });
  assert(fetched.id === 1, 'ready get id');
  assert(fetched.media.length === 1, 'ready media count');
  const image = fetched.media[0];
  assert(image.status === 'ready', 'ready status');
  assert(image.kind === 'image', 'ready kind');
  assert(image.source_type === 'gallery', 'ready source');
  assert(image.content_type === 'image/jpeg', 'ready mime');
  assert(image.byte_size === 12345, 'ready size');
  assert(image.original_filename === 'soir.jpg', 'ready filename');
  assert(image.sort_order === 0, 'ready order');
  assert(typeof image.read_url === 'string' && image.read_url.startsWith('https://mock-storage.local/read/'), 'read_url');
  assert(image.read_expires_at === '2026-09-25T10:16:00.000Z', 'read_expires_at');
  assert(storage.signedKeys.length === 1, 'one signature');
  assert(storage.signedKeys[0] === 'publications/1/media/ready-image', 'signed internal key');
  assertPublicMedia(image);
  console.log('1 OK GET :id media ready -> read_url, sans storage_key');

  const pendingStorage = createStorageSpy();
  const pendingDb = createMemory({
    publications: [publicationRow()],
    media: [mediaRow({ status: 'pending_upload', storage_key: 'publications/1/media/pending' })],
  });
  const pending = await getChroniqueById(OWNER_A, 1, { db: pendingDb, storage: pendingStorage });
  assert(pending.media.length === 1, 'pending count');
  assert(pending.media[0].status === 'pending_upload', 'pending status');
  assert(pending.media[0].read_url == null, 'pending no read_url');
  assert(!Object.prototype.hasOwnProperty.call(pending.media[0], 'read_url'), 'pending omits read_url');
  assert(pendingStorage.signedKeys.length === 0, 'pending must not sign');
  assertPublicMedia(pending.media[0]);
  console.log('2 OK pending_upload -> pas de signature');

  const failedStorage = createStorageSpy();
  const failedDb = createMemory({
    publications: [publicationRow()],
    media: [mediaRow({ id: 2, status: 'failed', storage_key: 'publications/1/media/failed' })],
  });
  const failed = await getChroniqueById(OWNER_A, 1, { db: failedDb, storage: failedStorage });
  assert(failed.media[0].status === 'failed', 'failed status');
  assert(!Object.prototype.hasOwnProperty.call(failed.media[0], 'read_url'), 'failed omits read_url');
  assert(failedStorage.signedKeys.length === 0, 'failed must not sign');
  console.log('3 OK failed -> pas de signature');

  const mixStorage = createStorageSpy();
  const mixDb = createMemory({
    publications: [publicationRow({ media_total_bytes: 10000 })],
    media: [
      mediaRow({
        id: 10,
        kind: 'image',
        source_type: 'camera',
        storage_key: 'publications/1/media/img',
        content_type: 'image/png',
        byte_size: 100,
        original_filename: 'cam.png',
        sort_order: 0,
      }),
      mediaRow({
        id: 11,
        kind: 'video',
        source_type: 'gallery',
        storage_key: 'publications/1/media/vid',
        content_type: 'video/mp4',
        byte_size: 200,
        original_filename: 'clip.mp4',
        sort_order: 1,
      }),
      mediaRow({
        id: 12,
        kind: 'audio',
        source_type: 'microphone',
        storage_key: 'publications/1/media/aud',
        content_type: 'audio/mpeg',
        byte_size: 300,
        original_filename: 'voix.mp3',
        sort_order: 2,
      }),
      mediaRow({
        id: 13,
        kind: 'document',
        source_type: 'upload',
        storage_key: 'publications/1/media/doc',
        content_type: 'application/pdf',
        byte_size: 400,
        original_filename: 'note.pdf',
        sort_order: 3,
      }),
    ],
  });
  const mix = await getChroniqueById(OWNER_A, 1, { db: mixDb, storage: mixStorage });
  assert(mix.media.length === 4, 'mix count');
  assert(mix.media.map((item) => item.kind).join(',') === 'image,video,audio,document', 'kinds');
  assert(
    mix.media.map((item) => item.sort_order).join(',') === '0,1,2,3',
    'sort_order'
  );
  for (const item of mix.media) {
    assert(item.status === 'ready', `${item.kind} ready`);
    assert(typeof item.read_url === 'string' && item.read_url.length > 0, `${item.kind} read_url`);
    assert(item.read_expires_at === '2026-09-25T10:16:00.000Z', `${item.kind} expires`);
    assertPublicMedia(item);
  }
  const urls = new Set(mix.media.map((item) => item.read_url));
  assert(urls.size === 4, 'distinct read_url');
  assert(mixStorage.signedKeys.length === 4, 'four signatures');
  console.log('4 OK plusieurs medias ready -> une read_url chacun');

  const foreignStorage = createStorageSpy();
  const foreignDb = createMemory({
    publications: [
      publicationRow({ id: 2, user_id: OWNER_B, title: 'Chez B' }),
    ],
    media: [
      mediaRow({
        id: 99,
        publication_id: 2,
        storage_key: 'publications/2/media/secret',
      }),
    ],
  });
  await expectStatus(
    () => getChroniqueById(OWNER_A, 2, { db: foreignDb, storage: foreignStorage }),
    404,
    'Chronique not found'
  );
  assert(foreignStorage.signedKeys.length === 0, 'foreign must not sign');
  console.log('5 OK ownership GET etranger -> 404, aucune signature');

  const deletedStorage = createStorageSpy();
  const afterDeleteDb = createMemory({
    publications: [publicationRow()],
    media: [],
  });
  const afterDelete = await getChroniqueById(OWNER_A, 1, {
    db: afterDeleteDb,
    storage: deletedStorage,
  });
  assert(afterDelete.media.length === 0, 'deleted media absent');
  assert(deletedStorage.signedKeys.length === 0, 'deleted media must not sign');
  console.log('6 OK media supprime absent de GET :id');

  const listStorage = createStorageSpy();
  const listDb = createMemory({
    publications: [publicationRow({ media_total_bytes: 12345 })],
    media: [mediaRow()],
  });
  const listed = await listChroniques(OWNER_A, { status: 'active' }, { db: listDb, storage: listStorage });
  assert(listed.items.length === 1, 'list count');
  assert(Array.isArray(listed.items[0].media), 'list media array');
  assert(listed.items[0].media.length === 0, 'list media still []');
  assert(listStorage.signedKeys.length === 0, 'list must not sign');
  console.log('7 OK GET /chroniques ne genere pas de read_url');

  const mixedStatusStorage = createStorageSpy();
  const mixedStatusDb = createMemory({
    publications: [publicationRow()],
    media: [
      mediaRow({ id: 1, status: 'ready', sort_order: 0, storage_key: 'publications/1/media/ok' }),
      mediaRow({ id: 2, status: 'pending_upload', sort_order: 1, storage_key: 'publications/1/media/wait' }),
      mediaRow({ id: 3, status: 'failed', sort_order: 2, storage_key: 'publications/1/media/bad' }),
    ],
  });
  const mixedStatus = await getChroniqueById(OWNER_A, 1, {
    db: mixedStatusDb,
    storage: mixedStatusStorage,
  });
  assert(mixedStatus.media.length === 3, 'mixed statuses remain listed');
  assert(mixedStatus.media[0].read_url, 'only ready signed');
  assert(!mixedStatus.media[1].read_url, 'pending unsigned');
  assert(!mixedStatus.media[2].read_url, 'failed unsigned');
  assert(mixedStatusStorage.signedKeys.length === 1, 'sign ready only');
  console.log('8 OK ready signe, pending/failed listes sans URL');

  console.log('Chronique read-url check succeeded.');
}

main().catch((err) => {
  console.error('Chronique read-url check failed:', err.message);
  process.exitCode = 1;
});
