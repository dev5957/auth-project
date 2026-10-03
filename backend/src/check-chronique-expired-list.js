const { getChroniqueById, listChroniques } = require('./services/chroniqueService');
const { PURGE_DELAY_DAYS } = require('./validators/chroniqueFields');
const AppError = require('./errors/AppError');

const OWNER_A = 11;
const OWNER_B = 22;
const BODY = 'Le texte de la chronique, d au moins vingt caracteres.';
const NOW = new Date('2026-09-27T12:00:00.000Z');

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

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function publicationRow(overrides = {}) {
  const expiredAt =
    overrides.expired_at === undefined ? new Date('2026-09-20T10:00:00.000Z') : overrides.expired_at;
  const purgeAfter =
    overrides.purge_after === undefined
      ? expiredAt
        ? addDays(expiredAt, PURGE_DELAY_DAYS)
        : null
      : overrides.purge_after;
  return {
    id: 1,
    user_id: OWNER_A,
    theme_id: null,
    title: 'Expirée',
    body: BODY,
    status: 'expired',
    scheduled_at: null,
    published_at: new Date('2026-09-19T10:00:00.000Z'),
    archived_at: null,
    deleted_at: null,
    is_time_limited: true,
    expires_at: expiredAt,
    is_public: false,
    audience: 'private',
    comments_enabled: false,
    media_total_bytes: 0,
    created_at: new Date('2026-09-19T09:00:00.000Z'),
    updated_at: new Date('2026-09-20T10:00:00.000Z'),
    ...overrides,
    expired_at: expiredAt,
    purge_after: purgeAfter,
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
    created_at: new Date('2026-09-19T09:01:00.000Z'),
    ...overrides,
  };
}

function stillInRetention(row, nowMs) {
  const purgeAfter = row.purge_after ? new Date(row.purge_after).getTime() : null;
  if (purgeAfter != null) {
    return purgeAfter > nowMs;
  }
  if (!row.expired_at) {
    return false;
  }
  return new Date(row.expired_at).getTime() + PURGE_DELAY_DAYS * 24 * 60 * 60 * 1000 > nowMs;
}

function createMemory({ publications, media }) {
  const stats = { publicationQueries: 0, mediaQueries: 0, getQueries: 0, detailMediaQueries: 0 };
  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key.includes('FROM PUBLICATIONS') && key.includes("STATUS <> 'DELETED'") && key.includes('LIMIT 1')) {
      stats.getQueries += 1;
      assert(key.includes('COALESCE(PURGE_AFTER'), 'get must apply retention SQL');
      const row = publications.find(
        (item) =>
          Number(item.id) === Number(params[0]) &&
          Number(item.user_id) === Number(params[1]) &&
          item.status !== 'deleted'
      );
      if (row && row.status === 'expired' && !stillInRetention(row, Date.now())) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes('WHERE USER_ID = $1') && key.includes('AND STATUS = $2')) {
      stats.publicationQueries += 1;
      const userId = params[0];
      const status = params[1];
      const hasCursor = params.length >= 5;
      const cursorAt = hasCursor ? new Date(params[2]).getTime() : null;
      const cursorId = hasCursor ? Number(params[3]) : null;
      const limit = Number(params[params.length - 1]);
      const sortColumn =
        status === 'scheduled'
          ? 'scheduled_at'
          : status === 'archived'
            ? 'archived_at'
            : status === 'expired'
              ? 'expired_at'
              : status === 'draft'
                ? 'updated_at'
                : 'published_at';
      let rows = publications.filter(
        (item) => Number(item.user_id) === Number(userId) && item.status === status
      );
      assert(
        status !== 'expired' || key.includes('COALESCE(PURGE_AFTER'),
        'expired list must apply retention SQL'
      );
      if (status === 'expired' && key.includes('COALESCE(PURGE_AFTER')) {
        const nowMs = Date.now();
        rows = rows.filter((item) => stillInRetention(item, nowMs));
      }
      rows.sort((a, b) => {
        const av = a[sortColumn] ? new Date(a[sortColumn]).getTime() : 0;
        const bv = b[sortColumn] ? new Date(b[sortColumn]).getTime() : 0;
        if (status === 'scheduled') {
          return av - bv || Number(a.id) - Number(b.id);
        }
        return bv - av || Number(b.id) - Number(a.id);
      });
      if (hasCursor) {
        rows = rows.filter((item) => {
          const it = item[sortColumn] ? new Date(item[sortColumn]).getTime() : 0;
          if (status === 'scheduled') {
            return it > cursorAt || (it === cursorAt && Number(item.id) > cursorId);
          }
          return it < cursorAt || (it === cursorAt && Number(item.id) < cursorId);
        });
      }
      rows = rows.slice(0, limit).map((item) => ({ ...item }));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM PUBLICATION_MEDIA') && key.includes('ANY($1::BIGINT[])')) {
      stats.mediaQueries += 1;
      const rawIds = Array.isArray(params[0]) ? params[0] : [params[0]];
      const ids = new Set(rawIds.map((id) => Number(id)));
      const kinds = new Set(['image', 'video', 'audio', 'document']);
      const rows = media
        .filter((item) => ids.has(Number(item.publication_id)))
        .filter((item) => item.status === 'ready')
        .filter((item) => kinds.has(item.kind))
        .sort(
          (a, b) =>
            Number(a.publication_id) - Number(b.publication_id) ||
            Number(a.sort_order) - Number(b.sort_order) ||
            Number(a.id) - Number(b.id)
        )
        .map((item) => ({ ...item }));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM PUBLICATION_MEDIA') && key.includes('ORDER BY SORT_ORDER')) {
      stats.detailMediaQueries += 1;
      const rows = media
        .filter((item) => Number(item.publication_id) === Number(params[0]))
        .sort((a, b) => Number(a.sort_order) - Number(b.sort_order) || Number(a.id) - Number(b.id))
        .map((item) => ({ ...item }));
      return { rows, rowCount: rows.length };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  return {
    stats,
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
      throw new Error('createDirectUpload must not run on list');
    },
    async head(storageKey) {
      if (typeof storageKey === 'string' && storageKey.endsWith('.thumb.jpg')) {
        return { byteSize: 80, contentType: 'image/jpeg' };
      }
      throw new Error('head must not run on list');
    },
    async delete() {
      throw new Error('delete must not run on list');
    },
    async createReadUrl(storageKey) {
      signedKeys.push(storageKey);
      return {
        method: 'GET',
        url: `https://mock-storage.local/read/${encodeURIComponent(storageKey)}`,
        expires_at: '2026-09-27T12:16:00.000Z',
      };
    },
  };
}

async function main() {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://chronique-expired-list-test/local';
  assert(PURGE_DELAY_DAYS === 30, 'retention constant');

  const realNow = Date.now;
  Date.now = () => NOW.getTime();
  try {
    const eligibleA = publicationRow({
      id: 10,
      title: 'Récente',
      expired_at: new Date('2026-09-25T10:00:00.000Z'),
    });
    const olderA = publicationRow({
      id: 9,
      title: 'Plus ancienne',
      expired_at: new Date('2026-09-22T10:00:00.000Z'),
    });
    const otherOwner = publicationRow({
      id: 8,
      user_id: OWNER_B,
      title: 'Chez B',
      expired_at: new Date('2026-09-26T10:00:00.000Z'),
    });
    const active = publicationRow({
      id: 7,
      status: 'active',
      expired_at: null,
      purge_after: null,
      is_time_limited: false,
      expires_at: null,
    });
    const archived = publicationRow({
      id: 6,
      status: 'archived',
      archived_at: new Date('2026-09-21T10:00:00.000Z'),
      expired_at: null,
      purge_after: null,
    });
    const pastRetention = publicationRow({
      id: 5,
      title: 'Hors fenêtre',
      expired_at: new Date('2026-08-01T10:00:00.000Z'),
      purge_after: new Date('2026-08-31T10:00:00.000Z'),
    });
    const nullPurgeStillInWindow = publicationRow({
      id: 4,
      title: 'Sans purge_after',
      expired_at: new Date('2026-09-10T12:00:00.000Z'),
      purge_after: null,
    });
    const deleted = publicationRow({
      id: 3,
      status: 'deleted',
      deleted_at: new Date('2026-09-26T10:00:00.000Z'),
    });

    const publications = [
      eligibleA,
      olderA,
      otherOwner,
      active,
      archived,
      pastRetention,
      nullPurgeStillInWindow,
      deleted,
    ];

    const db = createMemory({ publications, media: [] });
    const listed = await listChroniques(OWNER_A, { status: 'expired' }, { db });
    const ids = listed.items.map((item) => item.id);
    assert(ids.includes(10) && ids.includes(9) && ids.includes(4), 'own eligible expired');
    assert(!ids.includes(8), 'other user hidden');
    assert(!ids.includes(7), 'active hidden');
    assert(!ids.includes(6), 'archived hidden');
    assert(!ids.includes(5), 'retention ended hidden');
    assert(!ids.includes(3), 'deleted hidden');
    assert(listed.items[0].id === 10, 'newest expired first');
    assert(listed.items[1].id === 9, 'older expired second');
    assert(listed.items[2].id === 4, 'null purge_after still in window');
    assert(listed.items[0].expired_at === '2026-09-25T10:00:00.000Z', 'expired_at exposed');
    assert(listed.items[0].purge_after === addDays(new Date('2026-09-25T10:00:00.000Z'), 30).toISOString(), 'purge_after exposed');
    console.log('1 OK own eligible expired, isolation, statuses, retention, order');

    const pageDb = createMemory({
      publications: [eligibleA, olderA, nullPurgeStillInWindow],
      media: [],
    });
    const firstPage = await listChroniques(OWNER_A, { status: 'expired', limit: '2' }, { db: pageDb });
    assert(firstPage.items.length === 2, 'first page size');
    assert(firstPage.items[0].id === 10 && firstPage.items[1].id === 9, 'first page order');
    assert(firstPage.next && firstPage.next.before_id === 9, 'cursor before_id');
    assert(firstPage.next.before_at === olderA.expired_at.toISOString(), 'cursor before_at');
    const secondPage = await listChroniques(
      OWNER_A,
      {
        status: 'expired',
        limit: '2',
        before_at: firstPage.next.before_at,
        before_id: firstPage.next.before_id,
      },
      { db: pageDb }
    );
    assert(secondPage.items.length === 1, 'second page size');
    assert(secondPage.items[0].id === 4, 'second page remaining');
    assert(secondPage.next == null, 'second page exhausted');
    console.log('2 OK pagination newest expired first');

    const storage = createStorageSpy();
    const mediaDb = createMemory({
      publications: [eligibleA, olderA],
      media: [
        mediaRow({
          id: 101,
          publication_id: 10,
          kind: 'image',
          storage_key: 'publications/10/media/img',
        }),
        mediaRow({
          id: 102,
          publication_id: 10,
          kind: 'video',
          storage_key: 'publications/10/media/vid',
          content_type: 'video/mp4',
          original_filename: 'clip.mp4',
          sort_order: 1,
        }),
        mediaRow({
          id: 103,
          publication_id: 9,
          kind: 'audio',
          storage_key: 'publications/9/media/aud',
          content_type: 'audio/mpeg',
          original_filename: 'voix.mp3',
        }),
        mediaRow({
          id: 104,
          publication_id: 9,
          kind: 'document',
          storage_key: 'publications/9/media/doc',
          content_type: 'application/pdf',
          original_filename: 'note.pdf',
          sort_order: 1,
        }),
        mediaRow({
          id: 105,
          publication_id: 9,
          status: 'pending',
          storage_key: 'publications/9/media/pending',
        }),
      ],
    });
    const withMedia = await listChroniques(OWNER_A, { status: 'expired' }, { db: mediaDb, storage });
    assert(mediaDb.stats.mediaQueries === 1, 'single media query no N+1');
    assert(mediaDb.stats.publicationQueries === 1, 'single publication query');
    const recent = withMedia.items.find((item) => item.id === 10);
    const older = withMedia.items.find((item) => item.id === 9);
    assert(recent.media.length === 2, 'recent ready media');
    assert(older.media.length === 2, 'older ready media');
    assert(recent.media[0].kind === 'image' && recent.media[0].read_url, 'image signed');
    assert(recent.media[1].kind === 'video' && recent.media[1].read_url, 'video signed');
    assert(recent.media[1].thumbnail_url, 'video thumbnail signed');
    assert(older.media[0].kind === 'audio' && older.media[0].read_url, 'audio signed');
    assert(older.media[1].kind === 'document' && older.media[1].read_url, 'document signed');
    assert(older.media.every((item) => item.status === 'ready'), 'pending excluded');
    assert(
      storage.signedKeys.includes('publications/10/media/img') &&
        storage.signedKeys.includes('publications/10/media/vid') &&
        storage.signedKeys.includes('publications/9/media/aud') &&
        storage.signedKeys.includes('publications/9/media/doc'),
      'signed keys match feed convention'
    );
    const leaked = JSON.stringify(withMedia);
    assert(!leaked.includes('storage_key'), 'storage_key not public');
    console.log('3 OK ready media attached once with signed URLs');

    const isolated = await listChroniques(OWNER_B, { status: 'expired' }, {
      db: createMemory({ publications, media: [] }),
    });
    assert(isolated.items.length === 1, 'owner B sees own only');
    assert(isolated.items[0].id === 8, 'owner B id');
    console.log('4 OK owner B isolation');

    const detailDb = createMemory({ publications, media: [] });
    const inWindow = await getChroniqueById(OWNER_A, 10, { db: detailDb });
    assert(inWindow.id === 10, 'expired in retention get id');
    assert(inWindow.status === 'expired', 'expired in retention status');
    assert(detailDb.stats.getQueries === 1, 'one get for in-window');
    assert(detailDb.stats.detailMediaQueries === 1, 'in-window get loads media');

    await expectStatus(
      () => getChroniqueById(OWNER_A, 5, { db: detailDb }),
      404,
      'Chronique not found'
    );
    assert(detailDb.stats.getQueries === 2, 'past retention still queries get');
    assert(detailDb.stats.detailMediaQueries === 1, 'past retention skips media');

    const activeGot = await getChroniqueById(OWNER_A, 7, { db: detailDb });
    assert(activeGot.id === 7 && activeGot.status === 'active', 'active get unchanged');
    const archivedGot = await getChroniqueById(OWNER_A, 6, { db: detailDb });
    assert(archivedGot.id === 6 && archivedGot.status === 'archived', 'archived get unchanged');
    console.log('5 OK get by id retention aligned with list');
  } finally {
    Date.now = realNow;
  }

  console.log('Chronique expired list check succeeded.');
}

main().catch((err) => {
  if (err instanceof AppError) {
    console.error('Chronique expired list check failed:', err.statusCode, err.message);
  } else {
    console.error('Chronique expired list check failed:', err.message);
  }
  process.exitCode = 1;
});
