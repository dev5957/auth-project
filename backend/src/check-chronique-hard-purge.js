const { runPurgeExpiredJob, collectMediaStorageKeys } = require('./services/chroniqueJobs');
const { PURGE_DELAY_DAYS } = require('./validators/chroniqueFields');
const { thumbnailStorageKey } = require('./services/mediaStorageKeys');
const AppError = require('./errors/AppError');

const NOW = new Date('2026-09-28T12:00:00.000Z');
const BODY = 'Le texte de la chronique, d au moins vingt caracteres.';

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function clone(row) {
  return { ...row };
}

function publicationRow(overrides = {}) {
  return {
    id: 1,
    user_id: 11,
    theme_id: null,
    title: 'Purge',
    body: BODY,
    status: 'expired',
    scheduled_at: null,
    published_at: new Date('2026-08-01T10:00:00.000Z'),
    archived_at: null,
    expired_at: new Date('2026-08-01T10:00:00.000Z'),
    purge_after: new Date('2026-08-31T10:00:00.000Z'),
    deleted_at: null,
    is_time_limited: true,
    expires_at: new Date('2026-08-01T10:00:00.000Z'),
    is_public: false,
    audience: 'private',
    comments_enabled: false,
    media_total_bytes: 0,
    created_at: new Date('2026-08-01T09:00:00.000Z'),
    updated_at: new Date('2026-08-01T10:00:00.000Z'),
    ...overrides,
  };
}

function mediaRow(overrides = {}) {
  return {
    id: 1,
    publication_id: 1,
    kind: 'image',
    source_type: 'gallery',
    storage_key: 'publications/1/media/img',
    content_type: 'image/jpeg',
    byte_size: 10,
    original_filename: 'img.jpg',
    sort_order: 0,
    status: 'ready',
    created_at: new Date('2026-08-01T09:01:00.000Z'),
    ...overrides,
  };
}

function isDueExpired(row, now) {
  if (row.status !== 'expired') {
    return false;
  }
  if (row.purge_after) {
    return new Date(row.purge_after).getTime() <= now.getTime();
  }
  if (!row.expired_at) {
    return false;
  }
  return new Date(row.expired_at).getTime() <= now.getTime() - PURGE_DELAY_DAYS * 24 * 60 * 60 * 1000;
}

function createMemory({ publications, media }) {
  const state = {
    publications: publications.map(clone),
    media: media.map(clone),
  };

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.startsWith('SELECT') && key.includes('FROM PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'")) {
      const now = params[0];
      const limit = Number(params[params.length - 1]);
      const hasCursor = params.length >= 4;
      const cursorAt = hasCursor ? new Date(params[1]).getTime() : null;
      const cursorId = hasCursor ? Number(params[2]) : null;
      let rows = state.publications
        .filter((item) => isDueExpired(item, new Date(now)))
        .sort((a, b) => {
          const av = new Date(a.purge_after || a.expired_at).getTime();
          const bv = new Date(b.purge_after || b.expired_at).getTime();
          return av - bv || Number(a.id) - Number(b.id);
        });
      if (hasCursor) {
        rows = rows.filter((item) => {
          const it = new Date(item.purge_after || item.expired_at).getTime();
          return it > cursorAt || (it === cursorAt && Number(item.id) > cursorId);
        });
      }
      rows = rows.slice(0, limit).map(clone);
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('DELETE FROM PUBLICATION_MEDIA')) {
      const publicationId = params[0];
      const remaining = [];
      let removed = 0;
      for (const item of state.media) {
        if (Number(item.publication_id) === Number(publicationId)) {
          removed += 1;
        } else {
          remaining.push(item);
        }
      }
      state.media = remaining;
      return { rows: [], rowCount: removed };
    }

    if (key.includes('FROM PUBLICATION_MEDIA')) {
      const publicationId = params[0];
      const rows = state.media
        .filter((item) => Number(item.publication_id) === Number(publicationId))
        .sort((a, b) => Number(a.id) - Number(b.id))
        .map(clone);
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('DELETE FROM PUBLICATIONS')) {
      const id = params[0];
      const index = state.publications.findIndex(
        (item) => Number(item.id) === Number(id) && item.status === 'expired'
      );
      if (index < 0) {
        return { rows: [], rowCount: 0 };
      }
      const [removed] = state.publications.splice(index, 1);
      return { rows: [clone(removed)], rowCount: 1 };
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

function createStorage({ failOn = new Set() } = {}) {
  const deleted = [];
  return {
    deleted,
    createDirectUpload() {
      throw new Error('upload must not run on purge');
    },
    async head() {
      throw new Error('head must not run on purge');
    },
    async createReadUrl() {
      throw new Error('read url must not run on purge');
    },
    async delete(storageKey) {
      deleted.push(storageKey);
      if (failOn.has(storageKey)) {
        throw new Error(`R2 delete failed for ${storageKey}`);
      }
    },
  };
}

async function runPurge(db, storage, extras = {}) {
  return runPurgeExpiredJob({
    db,
    query: db.query.bind(db),
    storage,
    now: NOW,
    ...extras,
  });
}

async function main() {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://chronique-hard-purge-test/local';
  assert(PURGE_DELAY_DAYS === 30, 'retention constant');

  const videoKey = 'publications/2/media/clip';
  const videoThumb = thumbnailStorageKey(videoKey);
  assert(collectMediaStorageKeys({ kind: 'video', storage_key: videoKey }).includes(videoThumb), 'thumb key');

  const future = publicationRow({
    id: 1,
    title: 'Encore en rétention',
    expired_at: new Date('2026-09-20T12:00:00.000Z'),
    purge_after: addDays(new Date('2026-09-20T12:00:00.000Z'), 30),
  });
  const due = publicationRow({ id: 2, title: 'À purger' });
  const fallbackDue = publicationRow({
    id: 3,
    title: 'Fallback',
    expired_at: new Date('2026-08-20T12:00:00.000Z'),
    purge_after: null,
  });
  const active = publicationRow({
    id: 4,
    status: 'active',
    expired_at: null,
    purge_after: null,
    is_time_limited: false,
  });
  const archived = publicationRow({
    id: 5,
    status: 'archived',
    archived_at: new Date('2026-08-01T10:00:00.000Z'),
    expired_at: null,
    purge_after: null,
  });
  const scheduled = publicationRow({
    id: 6,
    status: 'scheduled',
    scheduled_at: new Date('2026-10-01T10:00:00.000Z'),
    expired_at: null,
    purge_after: null,
  });

  const dueMedia = [
    mediaRow({ id: 21, publication_id: 2, kind: 'image', storage_key: 'publications/2/media/img' }),
    mediaRow({
      id: 22,
      publication_id: 2,
      kind: 'video',
      storage_key: videoKey,
      content_type: 'video/mp4',
      original_filename: 'clip.mp4',
      sort_order: 1,
    }),
  ];

  const db = createMemory({
    publications: [future, due, fallbackDue, active, archived, scheduled],
    media: [...dueMedia, mediaRow({ id: 41, publication_id: 4, storage_key: 'publications/4/media/active' })],
  });
  const storage = createStorage();
  const first = await runPurge(db, storage);

  const remainingIds = db.state.publications.map((row) => row.id).sort((a, b) => a - b);
  assert(!remainingIds.includes(2), 'due expired removed');
  assert(remainingIds.includes(1), 'future retained');
  assert(!remainingIds.includes(3), 'null purge_after fallback removed');
  assert(remainingIds.includes(4), 'active retained');
  assert(remainingIds.includes(5), 'archived retained');
  assert(remainingIds.includes(6), 'scheduled retained');
  assert(first.length === 2, 'two hard deletes');
  assert(
    db.state.media.every((item) => item.publication_id !== 2 && item.publication_id !== 3),
    'due media rows removed'
  );
  assert(db.state.media.some((item) => item.publication_id === 4), 'active media kept');
  assert(storage.deleted.includes('publications/2/media/img'), 'image key deleted');
  assert(storage.deleted.includes(videoKey), 'video key deleted');
  assert(storage.deleted.includes(videoThumb), 'video thumbnail key deleted');
  assert(!storage.deleted.includes('publications/4/media/active'), 'active media not deleted');
  console.log('1-7 OK selection, fallback, isolation of other statuses, R2 keys, Neon delete');

  const failDb = createMemory({
    publications: [publicationRow({ id: 10 }), publicationRow({ id: 11, purge_after: new Date('2026-08-30T10:00:00.000Z') })],
    media: [
      mediaRow({ id: 101, publication_id: 10, storage_key: 'publications/10/media/boom' }),
      mediaRow({ id: 111, publication_id: 11, storage_key: 'publications/11/media/ok' }),
    ],
  });
  const failStorage = createStorage({ failOn: new Set(['publications/10/media/boom']) });
  const mixed = await runPurge(failDb, failStorage);
  assert(mixed.length === 1 && mixed[0].id === 11, 'other item still purged');
  assert(failDb.state.publications.some((row) => row.id === 10), 'failed item kept in neon');
  assert(failDb.state.media.some((item) => item.publication_id === 10), 'failed media kept');
  assert(failDb.state.publications.every((row) => row.id !== 11), 'success item gone');
  assert(!failDb.state.media.some((item) => item.publication_id === 11), 'success media gone');
  console.log('8+10 OK R2 error keeps neon and continues batch');

  const retry = await runPurge(failDb, createStorage());
  assert(retry.length === 1 && retry[0].id === 10, 'retry purges previously failed item');
  assert(failDb.state.publications.every((row) => row.id !== 10), 'retried item gone');
  assert(failDb.state.media.length === 0, 'retried media gone');
  console.log('11 OK resume after partial failure');

  const absentDb = createMemory({
    publications: [publicationRow({ id: 20 })],
    media: [mediaRow({ id: 201, publication_id: 20, storage_key: 'publications/20/media/gone' })],
  });
  const absentStorage = createStorage();
  const absent = await runPurge(absentDb, absentStorage);
  assert(absent.length === 1, 'missing object still succeeds');
  assert(absentStorage.deleted.includes('publications/20/media/gone'), 'delete attempted');
  assert(absentDb.state.publications.length === 0, 'neon publication removed');
  console.log('9 OK absent R2 object is idempotent success');

  const pageDb = createMemory({
    publications: [
      publicationRow({ id: 31, purge_after: new Date('2026-08-01T10:00:00.000Z') }),
      publicationRow({ id: 32, purge_after: new Date('2026-08-02T10:00:00.000Z') }),
      publicationRow({ id: 33, purge_after: new Date('2026-08-03T10:00:00.000Z') }),
    ],
    media: [],
  });
  const pageStorage = createStorage();
  const pageAll = await runPurge(pageDb, pageStorage, { limit: 2 });
  assert(pageAll.length === 3, 'one run drains all pages');
  assert(pageDb.state.publications.length === 0, 'no eligible ignored');
  console.log('12 OK intra-run pagination drains remaining eligible');

  const starveDb = createMemory({
    publications: [
      publicationRow({ id: 51, purge_after: new Date('2026-08-01T10:00:00.000Z') }),
      publicationRow({ id: 52, purge_after: new Date('2026-08-02T10:00:00.000Z') }),
    ],
    media: [
      mediaRow({ id: 511, publication_id: 51, storage_key: 'publications/51/media/poison' }),
      mediaRow({ id: 521, publication_id: 52, storage_key: 'publications/52/media/ok' }),
    ],
  });
  const starveStorage = createStorage({ failOn: new Set(['publications/51/media/poison']) });
  const starved = await runPurge(starveDb, starveStorage, { limit: 1, maxPages: 5 });
  assert(starved.length === 1 && starved[0].id === 52, 'healthy after poison is purged in same run');
  assert(starveDb.state.publications.some((row) => row.id === 51 && row.status === 'expired'), 'poison stays expired');
  assert(starveDb.state.media.some((item) => item.publication_id === 51), 'poison neon media kept');
  assert(starveDb.state.publications.every((row) => row.id !== 52), 'healthy gone');
  console.log('13 OK limit=1 poison does not starve later eligible');

  const partialKeysDb = createMemory({
    publications: [publicationRow({ id: 40 })],
    media: [
      mediaRow({ id: 401, publication_id: 40, storage_key: 'publications/40/media/a' }),
      mediaRow({ id: 402, publication_id: 40, storage_key: 'publications/40/media/b' }),
    ],
  });
  const partialStorage = createStorage({ failOn: new Set(['publications/40/media/b']) });
  const partial = await runPurge(partialKeysDb, partialStorage);
  assert(partial.length === 0, 'partial r2 failure is not success');
  assert(partialKeysDb.state.publications.some((row) => row.id === 40), 'publication kept for resume');
  assert(partialKeysDb.state.media.length === 2, 'media rows kept for resume');
  const recovered = await runPurge(partialKeysDb, createStorage());
  assert(recovered.length === 1, 'resume after partial r2 success');
  assert(partialKeysDb.state.publications.length === 0, 'publication removed after resume');
  console.log('11b OK partial R2 delete does not drop neon references');

  console.log('Chronique hard purge check succeeded.');
}

main().catch((err) => {
  if (err instanceof AppError) {
    console.error('Chronique hard purge check failed:', err.statusCode, err.message);
  } else {
    console.error('Chronique hard purge check failed:', err.message);
  }
  process.exitCode = 1;
});
