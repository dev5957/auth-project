const AppError = require('./errors/AppError');
const {
  parseCreateInput,
  parsePatchInput,
  parseFeedQuery,
  parseMeQuery,
} = require('./validators/communityPublicationFields');
const {
  createPublication,
  listFeed,
  getPublication,
  patchPublication,
  deletePublication,
  restorePublication,
  listMine,
  getMine,
} = require('./services/communityPublicationService');
const {
  createMediaUpload,
  completeMedia,
  deleteMedia,
  abandonDraftsAndPendingUploads,
} = require('./services/communityPublicationMediaService');
const {
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
} = require('./services/communityPublicationJobs');
const { leaveCommunity, removeMember } = require('./services/communityService');

const OWNER_ID = 1;
const MEMBER_ID = 2;
const ADMIN_ID = 3;
const COMMUNITY_ID = 10;

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
    assert(err.statusCode === statusCode, `status ${err.statusCode} != ${statusCode}: ${err.message}`);
    if (message) {
      assert(err.message === message, `unexpected message: ${err.message}`);
    }
  }
}

async function expectReject(promise, statusCode) {
  try {
    await promise;
    throw new Error(`expected ${statusCode}`);
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err && err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode} got ${err.statusCode}: ${err.message}`);
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function createMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner1' },
    { id: MEMBER_ID, login: 'member2' },
    { id: ADMIN_ID, login: 'admin3' },
  ];
  const state = {
    communities: [{ id: COMMUNITY_ID, name: 'Jardin secret', created_by: OWNER_ID }],
    members: [
      { community_id: COMMUNITY_ID, user_id: OWNER_ID, role: 'owner' },
      { community_id: COMMUNITY_ID, user_id: MEMBER_ID, role: 'member' },
      { community_id: COMMUNITY_ID, user_id: ADMIN_ID, role: 'admin', role_assigned_at: new Date() },
    ],
    publications: [],
    media: [],
    storageDeleted: [],
  };
  let nextPubId = 1;
  let nextMediaId = 1;
  const objects = new Map();

  const storage = {
    async createDirectUpload({ storageKey }) {
      return { url: `https://upload.test/${storageKey}`, method: 'PUT', headers: {} };
    },
    async head(storageKey) {
      const obj = objects.get(storageKey);
      if (!obj) {
        return null;
      }
      return { byteSize: obj.byteSize };
    },
    async delete(storageKey) {
      objects.delete(storageKey);
      state.storageDeleted.push(storageKey);
    },
    async createReadUrl(storageKey) {
      return { url: `https://read.test/${storageKey}`, expires_at: new Date(Date.now() + 900000) };
    },
    put(storageKey, byteSize) {
      objects.set(storageKey, { byteSize });
    },
  };

  async function query(sql, params = []) {
    const key = sqlKey(sql);
    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('FROM COMMUNITY_MEMBERS') && key.includes('COMMUNITY_ID = $1') && key.includes('USER_ID = $2') && key.includes('LIMIT 1')) {
      const row = state.members.find(
        (item) => Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [{ user_id: row.user_id, role: row.role }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('SELECT ID, LOGIN FROM USERS')) {
      const user = users.find((item) => Number(item.id) === Number(params[0]));
      return { rows: user ? [user] : [], rowCount: user ? 1 : 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATIONS')) {
      const now = new Date();
      const row = {
        id: nextPubId,
        community_id: params[0],
        author_user_id: params[1],
        title: params[2],
        body: params[3],
        status: params[4],
        scheduled_at: params[5],
        published_at: params[6],
        is_time_limited: params[7],
        expires_at: params[8],
        comments_enabled: params[9],
        media_total_bytes: 0,
        initial_media_count: Number(params[10]) || 0,
        initial_media_open: params[11] === true,
        created_at: now,
        updated_at: now,
        expired_at: null,
        purge_after: null,
        deleted_at: null,
        deleted_by_user_id: null,
      };
      nextPubId += 1;
      state.publications.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.includes('FROM COMMUNITY_PUBLICATIONS P') && key.includes("P.STATUS = 'ACTIVE'") && key.includes('P.COMMUNITY_ID = $1')) {
      let rows = state.publications.filter(
        (item) => Number(item.community_id) === Number(params[0]) && item.status === 'active'
      );
      rows.sort((a, b) => {
        const ta = a.published_at ? new Date(a.published_at).getTime() : 0;
        const tb = b.published_at ? new Date(b.published_at).getTime() : 0;
        return tb - ta || Number(b.id) - Number(a.id);
      });
      const limit = Number(params[params.length - 1]);
      rows = rows.slice(0, limit).map((item) => ({
        ...item,
        author_login: (users.find((u) => Number(u.id) === Number(item.author_user_id)) || {}).login,
        is_former_member: !state.members.some(
          (m) => Number(m.community_id) === Number(item.community_id) && Number(m.user_id) === Number(item.author_user_id)
        ),
      }));
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('ID = $1 AND COMMUNITY_ID = $2')) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.community_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('COMMUNITY_ID = $1') && key.includes("STATUS = 'DRAFT'")) {
      const rows = state.publications.filter(
        (item) =>
          Number(item.community_id) === Number(params[0]) &&
          Number(item.author_user_id) === Number(params[1]) &&
          item.status === 'draft'
      );
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('STATUS = \'SCHEDULED\'')) {
      const now = params[0];
      const rows = state.publications
        .filter((item) => item.status === 'scheduled' && item.scheduled_at && new Date(item.scheduled_at) <= new Date(now))
        .slice(0, Number(params[1]) || 100);
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('IS_TIME_LIMITED = TRUE')) {
      const now = params[0];
      const rows = state.publications
        .filter(
          (item) =>
            item.status === 'active' &&
            item.is_time_limited &&
            item.expires_at &&
            new Date(item.expires_at) <= new Date(now)
        )
        .slice(0, Number(params[1]) || 100);
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'") && key.includes('PURGE_AFTER')) {
      const now = params[0];
      const rows = state.publications
        .filter((item) => item.status === 'expired' && item.purge_after && new Date(item.purge_after) <= new Date(now))
        .slice(0, Number(params[1]) || 100);
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }

    if (key.startsWith('SELECT P.*, C.NAME AS COMMUNITY_NAME') && key.includes('P.ID = $1 AND P.AUTHOR_USER_ID = $2')) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.author_user_id) === Number(params[1])
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rows: [{ ...row, community_name: 'Jardin secret' }],
        rowCount: 1,
      };
    }

    if (key.includes('FROM COMMUNITY_PUBLICATIONS P') && key.includes('P.AUTHOR_USER_ID = $1')) {
      const scopeExpired = key.includes("P.STATUS = 'EXPIRED'");
      const scopeLeft = key.includes('NOT EXISTS');
      const scopeCurrent = key.includes("STATUS IN ('SCHEDULED', 'ACTIVE')") && key.includes('EXISTS') && !scopeLeft;
      let rows = state.publications.filter((item) => Number(item.author_user_id) === Number(params[0]));
      rows = rows.filter((item) => item.status !== 'draft' && item.status !== 'deleted');
      const isMember = (pub) =>
        state.members.some(
          (m) => Number(m.community_id) === Number(pub.community_id) && Number(m.user_id) === Number(params[0])
        );
      if (scopeExpired) {
        rows = rows.filter((item) => item.status === 'expired');
      } else if (scopeLeft) {
        rows = rows.filter((item) => (item.status === 'scheduled' || item.status === 'active') && !isMember(item));
      } else if (scopeCurrent) {
        rows = rows.filter((item) => (item.status === 'scheduled' || item.status === 'active') && isMember(item));
      } else {
        rows = rows.filter((item) => (item.status === 'scheduled' || item.status === 'active') && !isMember(item));
      }
      const limit = Number(params[params.length - 1]);
      rows = rows.slice(0, limit).map((item) => ({
        ...item,
        author_login: (users.find((u) => Number(u.id) === Number(item.author_user_id)) || {}).login,
        community_name: 'Jardin secret',
        is_former_member: !isMember(item),
      }));
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('TITLE = $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[2]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.title = params[0];
      row.body = params[1];
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes("STATUS = $1") && key.includes('DELETED_BY_USER_ID')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[3]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = params[0];
      row.deleted_at = params[1];
      row.deleted_by_user_id = params[2];
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('DELETED_AT = NULL')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[3]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = params[0];
      row.published_at = params[1];
      row.deleted_at = null;
      row.deleted_by_user_id = null;
      row.updated_at = params[2];
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'ACTIVE'") && key.includes('COALESCE(PUBLISHED_AT')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]) && item.status === 'scheduled');
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'active';
      row.published_at = row.published_at || params[0];
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'")) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[3]) && item.status === 'active');
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'expired';
      row.expired_at = params[0];
      row.purge_after = params[1];
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('INITIAL_MEDIA_OPEN = FALSE')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      if (row) {
        row.initial_media_open = false;
      }
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('MEDIA_TOTAL_BYTES')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]));
      if (row) {
        row.media_total_bytes = params[0];
      }
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('SELECT INITIAL_MEDIA_COUNT, INITIAL_MEDIA_OPEN')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      return {
        rows: row
          ? [{ initial_media_count: row.initial_media_count || 0, initial_media_open: Boolean(row.initial_media_open) }]
          : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS WHERE ID = $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATION_MEDIA')) {
      const row = {
        id: nextMediaId,
        community_publication_id: params[0],
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

    if (key.includes('AS PENDING_COUNT') && key.includes('FROM COMMUNITY_PUBLICATION_MEDIA')) {
      const items = state.media.filter((item) => Number(item.community_publication_id) === Number(params[0]));
      return {
        rows: [
          {
            pending_count: items.filter((item) => item.status === 'pending_upload').length,
            ready_count: items.filter((item) => item.status === 'ready').length,
            failed_count: items.filter((item) => item.status === 'failed').length,
          },
        ],
        rowCount: 1,
      };
    }

    if (key.includes('FROM COMMUNITY_PUBLICATION_MEDIA') && key.includes('COUNT(*)')) {
      const items = state.media.filter(
        (item) =>
          Number(item.community_publication_id) === Number(params[0]) &&
          (item.status === 'pending_upload' || item.status === 'ready')
      );
      return {
        rows: [
          {
            media_count: items.length,
            media_bytes: items.reduce((sum, item) => sum + Number(item.byte_size), 0),
          },
        ],
        rowCount: 1,
      };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATION_MEDIA') && key.includes('ID = $1 AND COMMUNITY_PUBLICATION_ID = $2')) {
      const row = state.media.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.community_publication_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATION_MEDIA') && key.includes('COMMUNITY_PUBLICATION_ID = $1')) {
      const rows = state.media
        .filter((item) => Number(item.community_publication_id) === Number(params[0]))
        .sort((a, b) => a.sort_order - b.sort_order || a.id - b.id);
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }

    if (key.includes('FROM COMMUNITY_PUBLICATION_MEDIA M') && key.includes('PENDING_UPLOAD')) {
      const rows = state.media.filter((item) => {
        if (item.status !== 'pending_upload') {
          return false;
        }
        const pub = state.publications.find((p) => Number(p.id) === Number(item.community_publication_id));
        return (
          pub &&
          Number(pub.community_id) === Number(params[0]) &&
          Number(pub.author_user_id) === Number(params[1])
        );
      });
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATION_MEDIA') && key.includes("STATUS = 'READY'")) {
      const row = state.media.find((item) => Number(item.id) === Number(params[1]));
      if (row) {
        row.status = 'ready';
        row.sort_order = params[0];
      }
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATION_MEDIA') && key.includes("STATUS = 'FAILED'")) {
      const row = state.media.find((item) => Number(item.id) === Number(params[0]));
      if (row) {
        row.status = 'failed';
      }
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('MAX(SORT_ORDER)')) {
      const items = state.media.filter(
        (item) => Number(item.community_publication_id) === Number(params[0]) && item.status === 'ready'
      );
      const max = items.reduce((acc, item) => Math.max(acc, item.sort_order), -1);
      return { rows: [{ max_order: max }], rowCount: 1 };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_MEDIA WHERE ID = $1')) {
      const before = state.media.length;
      state.media = state.media.filter((item) => Number(item.id) !== Number(params[0]));
      return { rows: [], rowCount: before - state.media.length };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_MEDIA WHERE COMMUNITY_PUBLICATION_ID')) {
      const before = state.media.length;
      state.media = state.media.filter((item) => Number(item.community_publication_id) !== Number(params[0]));
      return { rows: [], rowCount: before - state.media.length };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'DRAFT'")) {
      const before = state.publications.length;
      state.publications = state.publications.filter(
        (item) => !(Number(item.id) === Number(params[0]) && item.status === 'draft')
      );
      return { rows: [], rowCount: before - state.publications.length };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'")) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]) && item.status === 'expired');
      state.publications = state.publications.filter((item) => item !== row);
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_MEMBERS')) {
      const before = state.members.length;
      state.members = state.members.filter(
        (item) => !(Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: [], rowCount: before - state.members.length };
    }

    if (key.includes('FROM COMMUNITIES') && key.includes('FOR UPDATE')) {
      const row = state.communities.find((item) => Number(item.id) === Number(params[0]));
      return { rows: row ? [{ id: row.id, created_by: row.created_by }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM COMMUNITY_MEMBERS') && key.includes('FOR UPDATE') && params.length === 2) {
      const row = state.members.find(
        (item) => Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return {
        rows: row ? [{ user_id: row.user_id, role: row.role, role_assigned_at: row.role_assigned_at || null }] : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes("ROLE = 'OWNER'") && key.includes('COUNT(*)')) {
      const count = state.members.filter(
        (item) => Number(item.community_id) === Number(params[0]) && item.role === 'owner'
      ).length;
      return { rows: [{ owner_count: count }], rowCount: 1 };
    }

    throw new Error(`unexpected sql: ${key.slice(0, 180)}`);
  }

  return {
    state,
    storage,
    query,
    connect: async () => ({
      query,
      release() {},
    }),
  };
}

function validBody(overrides = {}) {
  return {
    title: 'Soirée jardin',
    body: 'Un texte communautaire assez long.',
    publish: 'now',
    comments_enabled: true,
    ...overrides,
  };
}

async function main() {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousUrl || 'postgres://community-pub-test/local';

  expectAppError(() => parseCreateInput({}), 400, 'body is required');
  parseCreateInput(validBody());
  parseCreateInput(validBody({ initial_media_count: 3 }));
  expectAppError(() => parseCreateInput(validBody({ initial_media_count: 6 })), 400, 'initial_media_count is invalid');
  expectAppError(() => parsePatchInput({ initial_media_count: 1 }), 400, 'initial_media_count cannot be set');
  expectAppError(() => parsePatchInput({ comments_enabled: false }), 400, 'comments_enabled cannot be set');
  expectAppError(() => parsePatchInput({ scheduled_at: new Date().toISOString() }), 400, 'scheduled_at cannot be set');
  parseFeedQuery({});
  parseMeQuery({ scope: 'left' });

  const db = createMemory();
  const deps = { db, storage: db.storage };

  const created = await createPublication(MEMBER_ID, COMMUNITY_ID, validBody(), deps);
  assert(created.status === 'active', 'now creates active');
  assert(created.comments_enabled === true, 'comments stored');
  const feed = await listFeed(OWNER_ID, COMMUNITY_ID, {}, deps);
  assert(feed.items.length === 1, 'active on feed');
  assert(feed.items[0].author.login === 'member2', 'author login');

  const scheduledAt = new Date(Date.now() + 86400000).toISOString();
  const scheduled = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ publish: 'schedule', scheduled_at: scheduledAt, comments_enabled: false }),
    deps
  );
  assert(scheduled.status === 'scheduled', 'schedule status');
  const feed2 = await listFeed(OWNER_ID, COMMUNITY_ID, {}, deps);
  assert(feed2.items.length === 1, 'scheduled hidden from feed');
  assert(feed2.items[0].id === created.id, 'only active listed');

  await expectReject(deletePublication(ADMIN_ID, COMMUNITY_ID, scheduled.id, deps), 403);
  await expectReject(deletePublication(OWNER_ID, COMMUNITY_ID, scheduled.id, deps), 403);

  const ephemeral = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({
      title: 'Ephémère jardin',
      is_time_limited: true,
      expires_at: new Date(Date.now() + 3600000).toISOString(),
    }),
    deps
  );
  assert(ephemeral.status === 'active', 'ephemeral active');

  await expectReject(
    patchPublication(OWNER_ID, COMMUNITY_ID, created.id, { title: 'Hack' }, deps),
    403
  );
  const patched = await patchPublication(MEMBER_ID, COMMUNITY_ID, created.id, { title: 'Titre auteur' }, deps);
  assert(patched.title === 'Titre auteur', 'author patch title');

  await deletePublication(OWNER_ID, COMMUNITY_ID, created.id, deps);
  await expectReject(restorePublication(OWNER_ID, COMMUNITY_ID, created.id, deps), 403);
  await expectReject(restorePublication(ADMIN_ID, COMMUNITY_ID, created.id, deps), 403);

  const ownActive = await createPublication(MEMBER_ID, COMMUNITY_ID, validBody({ title: 'Pour restore' }), deps);
  await deletePublication(MEMBER_ID, COMMUNITY_ID, ownActive.id, deps);
  const restored = await restorePublication(MEMBER_ID, COMMUNITY_ID, ownActive.id, deps);
  assert(restored.status === 'active', 'author restore active');

  const future = new Date(Date.now() + 86400000);
  const sched2 = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ publish: 'schedule', scheduled_at: future.toISOString(), title: 'Prog restore' }),
    deps
  );
  await deletePublication(MEMBER_ID, COMMUNITY_ID, sched2.id, deps);
  const restoredSched = await restorePublication(MEMBER_ID, COMMUNITY_ID, sched2.id, deps);
  assert(restoredSched.status === 'scheduled', 'restore future stays scheduled');

  const pastSched = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({
      publish: 'schedule',
      scheduled_at: new Date(Date.now() + 60000).toISOString(),
      title: 'Prog passee',
    }),
    deps
  );
  await deletePublication(MEMBER_ID, COMMUNITY_ID, pastSched.id, deps);
  const restoredPast = await restorePublication(MEMBER_ID, COMMUNITY_ID, pastSched.id, {
    ...deps,
    now: new Date(Date.now() + 120000),
  });
  assert(restoredPast.status === 'active', 'restore past scheduled becomes active');

  const draft = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ publish: 'draft', title: 'Brouillon', initial_media_count: 1 }),
    deps
  );
  assert(draft.status === 'draft', 'draft status');
  const upload = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    draft.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 1000 },
    deps
  );
  assert(upload.media.status === 'pending_upload', 'pending media');
  db.storage.put(db.state.media[0].storage_key, 1000);

  async function completeCreatedUpload(authorId, publicationId, mediaPayload) {
    db.storage.put(
      db.state.media.find((item) => Number(item.id) === Number(mediaPayload.media.id)).storage_key,
      mediaPayload.media.byte_size || 1
    );
    return completeMedia(authorId, COMMUNITY_ID, publicationId, mediaPayload.media.id, deps);
  }

  const multi = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Multi media', initial_media_count: 3 }),
    deps
  );
  const m1 = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    multi.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, multi.id, m1);
  const m2 = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    multi.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, multi.id, m2);
  const m3 = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    multi.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, multi.id, m3);
  await expectReject(
    createMediaUpload(
      MEMBER_ID,
      COMMUNITY_ID,
      multi.id,
      { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
      deps
    ),
    400
  );

  const textOnly = await createPublication(MEMBER_ID, COMMUNITY_ID, validBody({ title: 'Sans media' }), deps);
  await expectReject(
    createMediaUpload(
      MEMBER_ID,
      COMMUNITY_ID,
      textOnly.id,
      { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
      deps
    ),
    400
  );

  const scheduledLocked = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({
      publish: 'schedule',
      scheduled_at: future.toISOString(),
      title: 'Prog media lock',
      initial_media_count: 1,
    }),
    deps
  );
  const schedMedia = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    scheduledLocked.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, scheduledLocked.id, schedMedia);
  await expectReject(
    createMediaUpload(
      MEMBER_ID,
      COMMUNITY_ID,
      scheduledLocked.id,
      { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
      deps
    ),
    400
  );

  const cancelPub = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Cancel pending', initial_media_count: 2 }),
    deps
  );
  const cancelPending = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    cancelPub.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 50 },
    deps
  );
  const cancelKeep = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    cancelPub.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 50 },
    deps
  );
  await deleteMedia(MEMBER_ID, COMMUNITY_ID, cancelPub.id, cancelPending.media.id, deps);
  assert(
    !db.state.media.some((item) => Number(item.id) === Number(cancelPending.media.id)),
    'author can cancel initial pending'
  );
  db.storage.put(
    db.state.media.find((item) => Number(item.id) === Number(cancelKeep.media.id)).storage_key,
    50
  );
  await completeMedia(MEMBER_ID, COMMUNITY_ID, cancelPub.id, cancelKeep.media.id, deps);

  const readyPub = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Avec media', initial_media_count: 2 }),
    deps
  );
  const up2 = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    readyPub.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 2000 },
    deps
  );
  db.storage.put(
    db.state.media.find((item) => Number(item.id) === Number(up2.media.id)).storage_key,
    2000
  );
  await completeMedia(MEMBER_ID, COMMUNITY_ID, readyPub.id, up2.media.id, deps);
  const readyKey = db.state.media.find((item) => Number(item.id) === Number(up2.media.id)).storage_key;
  assert(readyKey, 'ready storage key');

  const pendingOnActive = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    readyPub.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 500 },
    deps
  );
  await deleteMedia(MEMBER_ID, COMMUNITY_ID, multi.id, m1.media.id, deps);
  assert(
    !db.state.media.some((item) => Number(item.id) === Number(m1.media.id)),
    'author can delete ready media'
  );
  await expectReject(
    createMediaUpload(
      MEMBER_ID,
      COMMUNITY_ID,
      multi.id,
      { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 100 },
      deps
    ),
    400
  );

  await leaveCommunity(MEMBER_ID, COMMUNITY_ID, deps);
  assert(!db.state.publications.some((item) => item.status === 'draft'), 'draft abandoned');
  assert(
    !db.state.media.some((item) => Number(item.id) === Number(pendingOnActive.media.id)),
    'pending cleaned on leave'
  );
  assert(
    db.state.media.some((item) => Number(item.id) === Number(up2.media.id) && item.status === 'ready'),
    'ready media kept'
  );
  assert(db.state.storageDeleted.some((key) => key.includes('media')), 'temp r2 cleaned');
  assert(
    db.state.publications.some((item) => Number(item.id) === Number(scheduled.id) && item.status === 'scheduled'),
    'scheduled kept after leave'
  );
  assert(
    db.state.publications.some((item) => Number(item.id) === Number(ephemeral.id) && item.status === 'active'),
    'active kept after leave'
  );

  await expectReject(listFeed(MEMBER_ID, COMMUNITY_ID, {}, deps), 404);
  await expectReject(patchPublication(MEMBER_ID, COMMUNITY_ID, readyPub.id, { title: 'x' }, deps), 404);
  const mineLeft = await listMine(MEMBER_ID, { scope: 'left' }, deps);
  assert(mineLeft.items.some((item) => Number(item.id) === Number(readyPub.id)), 'left scope has kept pub');
  assert(mineLeft.items.every((item) => item.status !== 'draft'), 'no drafts in me');

  await runPublishScheduledJob({ ...deps, now: new Date(Date.now() + 2 * 86400000) });
  const stillScheduled = db.state.publications.find((item) => Number(item.id) === Number(scheduled.id));
  assert(stillScheduled.status === 'active', 'job activates after leave');
  const feedAfter = await listFeed(OWNER_ID, COMMUNITY_ID, {}, deps);
  assert(feedAfter.items.some((item) => Number(item.id) === Number(scheduled.id)), 'activated visible to members');
  assert(feedAfter.items.find((item) => Number(item.id) === Number(scheduled.id)).author.is_former_member, 'former member flag');

  await runExpireActiveJob({ ...deps, now: new Date(Date.now() + 2 * 3600000) });
  const expiredRow = db.state.publications.find((item) => Number(item.id) === Number(ephemeral.id));
  assert(expiredRow.status === 'expired', 'ephemeral expired');
  const feedExpired = await listFeed(OWNER_ID, COMMUNITY_ID, {}, deps);
  assert(!feedExpired.items.some((item) => Number(item.id) === Number(ephemeral.id)), 'expired off feed');
  await expectReject(deletePublication(OWNER_ID, COMMUNITY_ID, ephemeral.id, deps), 400);
  await expectReject(deletePublication(ADMIN_ID, COMMUNITY_ID, ephemeral.id, deps), 400);

  const mineExpired = await listMine(MEMBER_ID, { scope: 'expired' }, deps);
  assert(mineExpired.items.some((item) => Number(item.id) === Number(ephemeral.id)), 'expired in me');

  expiredRow.purge_after = new Date(Date.now() - 1000);
  await runPurgeExpiredJob(deps);
  assert(!db.state.publications.some((item) => Number(item.id) === Number(ephemeral.id)), 'purged after 30d window');

  const tooMany = await createPublication(
    ADMIN_ID,
    COMMUNITY_ID,
    validBody({ title: 'Quota media', initial_media_count: 5 }),
    deps
  );
  for (let i = 0; i < 5; i += 1) {
    await createMediaUpload(
      ADMIN_ID,
      COMMUNITY_ID,
      tooMany.id,
      { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 10 },
      deps
    );
  }
  await expectReject(
    createMediaUpload(
      ADMIN_ID,
      COMMUNITY_ID,
      tooMany.id,
      { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 10 },
      deps
    ),
    400
  );
  const oversized = await createPublication(
    ADMIN_ID,
    COMMUNITY_ID,
    validBody({ title: 'Quota octets', initial_media_count: 1 }),
    deps
  );
  await expectReject(
    createMediaUpload(
      ADMIN_ID,
      COMMUNITY_ID,
      oversized.id,
      { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 209715201 },
      deps
    ),
    400
  );

  await expectReject(getPublication(OWNER_ID, COMMUNITY_ID, 999999, deps), 404);
  await deleteMedia(ADMIN_ID, COMMUNITY_ID, tooMany.id, db.state.media.filter((m) => Number(m.community_publication_id) === Number(tooMany.id))[0].id, deps);

  console.log('Community publications checks succeeded.');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
