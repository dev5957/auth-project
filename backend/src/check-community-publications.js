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
const { thumbnailStorageKey } = require('./services/mediaStorageKeys');

const OWNER_ID = 1;
const MEMBER_ID = 2;
const ADMIN_ID = 3;
const STRANGER_ID = 99;
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

function sameMediaId(left, right) {
  if (left === right) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  return String(left) === String(right);
}

function createMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner1' },
    { id: MEMBER_ID, login: 'member2' },
    { id: ADMIN_ID, login: 'admin3' },
    { id: STRANGER_ID, login: 'stranger99' },
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
    likes: [],
    comments: [],
    traces: [],
    storageDeleted: [],
    readUrlCalls: [],
    ops: [],
    deleteRowCountOverride: null,
    failSqlDelete: false,
    failStorageDelete: false,
  };
  let nextPubId = 1;
  let nextMediaId = 1;
  let nextLikeId = 1;
  let nextCommentId = 1;
  let nextTraceId = 1;
  let snapshot = null;
  const objects = new Map();

  function cloneState() {
    return {
      publications: state.publications.map((item) => ({ ...item })),
      media: state.media.map((item) => ({ ...item })),
      likes: state.likes.map((item) => ({ ...item })),
      comments: state.comments.map((item) => ({ ...item })),
      traces: state.traces.map((item) => ({ ...item })),
    };
  }

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
      state.ops.push('storage-delete');
      if (state.failStorageDelete) {
        throw new Error('r2 delete failed');
      }
      objects.delete(storageKey);
      state.storageDeleted.push(storageKey);
    },
    async createReadUrl(storageKey) {
      state.readUrlCalls.push(storageKey);
      return { url: `https://read.test/${storageKey}`, expires_at: new Date(Date.now() + 900000) };
    },
    put(storageKey, byteSize) {
      objects.set(storageKey, { byteSize });
    },
  };

  async function query(sql, params = []) {
    const key = sqlKey(sql);
    if (key === 'BEGIN') {
      snapshot = cloneState();
      state.ops.push('begin');
      return { rows: [], rowCount: 0 };
    }
    if (key === 'COMMIT') {
      snapshot = null;
      state.ops.push('commit');
      return { rows: [], rowCount: 0 };
    }
    if (key === 'ROLLBACK') {
      if (snapshot) {
        state.publications = snapshot.publications;
        state.media = snapshot.media;
        state.likes = snapshot.likes;
        state.comments = snapshot.comments;
        state.traces = snapshot.traces;
        snapshot = null;
      }
      state.ops.push('rollback');
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
        like_count: 0,
        comment_count: 0,
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

    if (
      key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_MEDIA WHERE ID = $1') &&
      key.includes('COMMUNITY_PUBLICATION_ID = $2')
    ) {
      if (state.failSqlDelete) {
        state.ops.push('sql-delete-error');
        throw new Error('sql delete failed');
      }
      state.ops.push('sql-delete');
      if (state.deleteRowCountOverride != null) {
        const rowCount = state.deleteRowCountOverride;
        state.deleteRowCountOverride = null;
        return { rows: [], rowCount };
      }
      const before = state.media.length;
      state.media = state.media.filter(
        (item) =>
          !(sameMediaId(item.id, params[0]) && sameMediaId(item.community_publication_id, params[1]))
      );
      return { rows: [], rowCount: before - state.media.length };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_MEDIA WHERE ID = $1')) {
      const before = state.media.length;
      state.media = state.media.filter((item) => !sameMediaId(item.id, params[0]));
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

    if (key.includes('FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('DISTINCT')) {
      const ids = [
        ...new Set(
          state.likes
            .filter(
              (item) => Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
            )
            .map((item) => Number(item.community_publication_id))
        ),
      ].sort((a, b) => a - b);
      return {
        rows: ids.map((community_publication_id) => ({ community_publication_id })),
        rowCount: ids.length,
      };
    }

    if (key.startsWith('SELECT ID') && key.includes('FROM COMMUNITY_PUBLICATIONS') && key.includes('ANY($1')) {
      const ids = (Array.isArray(params[0]) ? params[0] : []).map((value) => Number(value));
      const rows = state.publications
        .filter((item) => ids.includes(Number(item.id)))
        .sort((a, b) => Number(a.id) - Number(b.id))
        .map((item) => ({ id: item.id }));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('GROUP BY COMMUNITY_PUBLICATION_ID')) {
      const grouped = new Map();
      for (const item of state.likes) {
        if (Number(item.community_id) !== Number(params[0]) || Number(item.user_id) !== Number(params[1])) {
          continue;
        }
        const id = Number(item.community_publication_id);
        grouped.set(id, (grouped.get(id) || 0) + 1);
      }
      const rows = [...grouped.entries()].map(([community_publication_id, n]) => ({
        community_publication_id,
        n,
      }));
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('SELECT 1') && key.includes('FROM COMMUNITY_PUBLICATION_LIKES')) {
      const row = state.likes.find(
        (item) =>
          Number(item.community_publication_id) === Number(params[0]) &&
          Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [{ '?column?': 1 }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATION_LIKES')) {
      const exists = state.likes.some(
        (item) =>
          Number(item.community_publication_id) === Number(params[1]) &&
          Number(item.user_id) === Number(params[2])
      );
      if (exists) {
        return { rows: [], rowCount: 0 };
      }
      const row = {
        id: nextLikeId,
        community_id: params[0],
        community_publication_id: params[1],
        user_id: params[2],
        created_at: new Date(),
      };
      nextLikeId += 1;
      state.likes.push(row);
      return { rows: [{ id: row.id }], rowCount: 1 };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('USER_ID = $2') && key.includes('COMMUNITY_PUBLICATION_ID')) {
      const before = state.likes.length;
      const removed = state.likes.filter(
        (item) =>
          Number(item.community_publication_id) === Number(params[0]) &&
          Number(item.user_id) === Number(params[1])
      );
      state.likes = state.likes.filter(
        (item) =>
          !(
            Number(item.community_publication_id) === Number(params[0]) &&
            Number(item.user_id) === Number(params[1])
          )
      );
      return { rows: removed.map((item) => ({ id: item.id })), rowCount: before - state.likes.length };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('COMMUNITY_ID = $1') && key.includes('USER_ID = $2')) {
      const before = state.likes.length;
      state.likes = state.likes.filter(
        (item) => !(Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: [], rowCount: before - state.likes.length };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('COMMUNITY_PUBLICATION_ID = $1')) {
      const before = state.likes.length;
      state.likes = state.likes.filter((item) => Number(item.community_publication_id) !== Number(params[0]));
      return { rows: [], rowCount: before - state.likes.length };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_COMMENTS') && key.includes('COMMUNITY_PUBLICATION_ID = $1') && params.length === 1) {
      const before = state.comments.length;
      state.comments = state.comments.filter((item) => Number(item.community_publication_id) !== Number(params[0]));
      return { rows: [], rowCount: before - state.comments.length };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = GREATEST(LIKE_COUNT - $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.like_count = Math.max((Number(row.like_count) || 0) - Number(params[0]), 0);
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = LIKE_COUNT + 1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.like_count = (Number(row.like_count) || 0) + 1;
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = GREATEST(LIKE_COUNT - 1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.like_count = Math.max((Number(row.like_count) || 0) - 1, 0);
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = 0') && key.includes('COMMENT_COUNT = 0')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.like_count = 0;
      row.comment_count = 0;
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('COMMENT_COUNT = GREATEST(COMMENT_COUNT + $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.comment_count = Math.max((Number(row.comment_count) || 0) + Number(params[0]), 0);
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_COMMENT_EPHEMERAL_TRACES')) {
      const pub = state.publications.find((item) => Number(item.id) === Number(params[0]));
      if (!pub) {
        return { rows: [], rowCount: 0 };
      }
      const author = users.find((item) => Number(item.id) === Number(pub.author_user_id)) || { login: 'unknown' };
      let inserted = 0;
      for (const comment of state.comments) {
        if (Number(comment.community_publication_id) !== Number(pub.id) || comment.status !== 'visible') {
          continue;
        }
        if (state.traces.some((item) => Number(item.comment_id) === Number(comment.id))) {
          continue;
        }
        state.traces.push({
          id: nextTraceId,
          user_id: comment.author_user_id,
          community_id: comment.community_id,
          community_publication_id: comment.community_publication_id,
          publication_author_user_id: pub.author_user_id,
          publication_author_login: author.login,
          published_at: pub.published_at,
          expired_at: pub.expired_at,
          comment_id: comment.id,
          comment_body: comment.body,
          comment_created_at: comment.created_at,
          is_ephemeral: true,
          created_at: new Date(),
        });
        nextTraceId += 1;
        inserted += 1;
      }
      return { rows: [], rowCount: inserted };
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

function assertNoStorageKey(payload) {
  const text = JSON.stringify(payload);
  assert(!text.includes('"storage_key"'), 'storage_key json');
}

function assertSignedReadyMedia(item, storageKey) {
  assert(item.status === 'ready', 'ready media');
  assert(typeof item.read_url === 'string' && item.read_url === `https://read.test/${storageKey}`, 'read_url from storage');
  assert(typeof item.read_expires_at === 'string' && item.read_expires_at.length > 0, 'read_expires_at');
  assert(!Object.prototype.hasOwnProperty.call(item, 'storage_key'), 'storage_key field');
}

function assertNoThumbnail(item, label) {
  assert(!Object.prototype.hasOwnProperty.call(item, 'thumbnail_url'), `${label} no thumbnail_url`);
  assert(!Object.prototype.hasOwnProperty.call(item, 'thumbnail_expires_at'), `${label} no thumbnail_expires_at`);
}

function assertSignedThumbnail(item, thumbKey) {
  assert(
    typeof item.thumbnail_url === 'string' && item.thumbnail_url === `https://read.test/${thumbKey}`,
    'thumbnail_url from storage'
  );
  assert(
    typeof item.thumbnail_expires_at === 'string' && item.thumbnail_expires_at.length > 0,
    'thumbnail_expires_at'
  );
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

  const strangerReads = db.state.readUrlCalls.length;
  await expectReject(listFeed(STRANGER_ID, COMMUNITY_ID, {}, deps), 404);
  await expectReject(getPublication(STRANGER_ID, COMMUNITY_ID, readyPub.id, deps), 404);
  assert(db.state.readUrlCalls.length === strangerReads, 'non-member does not sign urls');

  const feedHydrated = await listFeed(OWNER_ID, COMMUNITY_ID, {}, deps);
  const textFeed = feedHydrated.items.find((item) => Number(item.id) === Number(textOnly.id));
  assert(textFeed, 'text-only still on feed');
  assert(Array.isArray(textFeed.media) && textFeed.media.length === 0, 'no media still works');
  assertNoStorageKey(textFeed);

  const multiFeed = feedHydrated.items.find((item) => Number(item.id) === Number(multi.id));
  assert(multiFeed && multiFeed.media.length === 3, 'three ready media on feed');
  const multiKeys = db.state.media
    .filter((item) => Number(item.community_publication_id) === Number(multi.id) && item.status === 'ready')
    .sort((a, b) => Number(a.sort_order) - Number(b.sort_order) || Number(a.id) - Number(b.id))
    .map((item) => item.storage_key);
  assert(multiKeys.length === 3, 'three ready keys');
  multiFeed.media.forEach((item, index) => {
    assertSignedReadyMedia(item, multiKeys[index]);
    assertNoThumbnail(item, 'image');
  });
  assert(new Set(multiFeed.media.map((item) => item.read_url)).size === 3, 'distinct read_url');
  assertNoStorageKey(multiFeed);

  const readyFeed = feedHydrated.items.find((item) => Number(item.id) === Number(readyPub.id));
  assert(readyFeed && readyFeed.media.length === 1, 'feed ready-only omits pending');
  assertSignedReadyMedia(readyFeed.media[0], readyKey);
  assertNoThumbnail(readyFeed.media[0], 'image');
  assertNoStorageKey(readyFeed);

  const gotMulti = await getPublication(OWNER_ID, COMMUNITY_ID, multi.id, deps);
  assert(gotMulti.media.length === 3, 'get hydrates all ready');
  gotMulti.media.forEach((item, index) => {
    assertSignedReadyMedia(item, multiKeys[index]);
    assertNoThumbnail(item, 'image');
  });
  assertNoStorageKey(gotMulti);

  const gotReady = await getPublication(MEMBER_ID, COMMUNITY_ID, readyPub.id, deps);
  const gotReadyItem = gotReady.media.find((item) => item.status === 'ready');
  const gotPendingItem = gotReady.media.find((item) => item.status === 'pending_upload');
  assert(gotReadyItem, 'get includes ready');
  assertSignedReadyMedia(gotReadyItem, readyKey);
  assertNoThumbnail(gotReadyItem, 'image');
  assert(gotPendingItem, 'get includes pending');
  assert(!Object.prototype.hasOwnProperty.call(gotPendingItem, 'read_url'), 'pending omits read_url');
  assertNoStorageKey(gotReady);

  const mineCurrent = await listMine(MEMBER_ID, { scope: 'current' }, deps);
  const mineMulti = mineCurrent.items.find((item) => Number(item.id) === Number(multi.id));
  assert(mineMulti && mineMulti.media.length === 3, 'listMine hydrates ready');
  mineMulti.media.forEach((item, index) => {
    assertSignedReadyMedia(item, multiKeys[index]);
    assertNoThumbnail(item, 'image');
  });
  assertNoStorageKey(mineMulti);

  const mineOne = await getMine(MEMBER_ID, multi.id, deps);
  assert(mineOne.media.length === 3, 'getMine hydrates ready');
  mineOne.media.forEach((item, index) => {
    assertSignedReadyMedia(item, multiKeys[index]);
    assertNoThumbnail(item, 'image');
  });
  assertNoStorageKey(mineOne);

  const kindsPub = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Kinds media', initial_media_count: 5 }),
    deps
  );
  const kindsImage = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    kindsPub.id,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: 80 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, kindsPub.id, kindsImage);
  const kindsVideoThumb = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    kindsPub.id,
    { kind: 'video', source_type: 'gallery', content_type: 'video/mp4', byte_size: 400 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, kindsPub.id, kindsVideoThumb);
  const videoThumbRow = db.state.media.find((item) => Number(item.id) === Number(kindsVideoThumb.media.id));
  const videoThumbKey = thumbnailStorageKey(videoThumbRow.storage_key);
  assert(videoThumbKey, 'video thumbnail key');
  db.storage.put(videoThumbKey, 12);
  const kindsVideoBare = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    kindsPub.id,
    { kind: 'video', source_type: 'gallery', content_type: 'video/mp4', byte_size: 300 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, kindsPub.id, kindsVideoBare);
  const kindsAudio = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    kindsPub.id,
    { kind: 'audio', source_type: 'upload', content_type: 'audio/mpeg', byte_size: 60 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, kindsPub.id, kindsAudio);
  const kindsDocument = await createMediaUpload(
    MEMBER_ID,
    COMMUNITY_ID,
    kindsPub.id,
    { kind: 'document', source_type: 'upload', content_type: 'application/pdf', byte_size: 40 },
    deps
  );
  await completeCreatedUpload(MEMBER_ID, kindsPub.id, kindsDocument);

  const kindsFeed = await listFeed(OWNER_ID, COMMUNITY_ID, {}, deps);
  const kindsItem = kindsFeed.items.find((item) => Number(item.id) === Number(kindsPub.id));
  assert(kindsItem && kindsItem.media.length === 5, 'five ready kinds on feed');
  const imageItem = kindsItem.media.find((item) => item.kind === 'image');
  const videos = kindsItem.media.filter((item) => item.kind === 'video');
  const audioItem = kindsItem.media.find((item) => item.kind === 'audio');
  const documentItem = kindsItem.media.find((item) => item.kind === 'document');
  const imageRow = db.state.media.find((item) => Number(item.id) === Number(kindsImage.media.id));
  const videoBareRow = db.state.media.find((item) => Number(item.id) === Number(kindsVideoBare.media.id));
  const audioRow = db.state.media.find((item) => Number(item.id) === Number(kindsAudio.media.id));
  const documentRow = db.state.media.find((item) => Number(item.id) === Number(kindsDocument.media.id));
  assertSignedReadyMedia(imageItem, imageRow.storage_key);
  assertNoThumbnail(imageItem, 'image');
  const videoWithThumb = videos.find((item) => Number(item.id) === Number(kindsVideoThumb.media.id));
  const videoWithoutThumb = videos.find((item) => Number(item.id) === Number(kindsVideoBare.media.id));
  assertSignedReadyMedia(videoWithThumb, videoThumbRow.storage_key);
  assertSignedThumbnail(videoWithThumb, videoThumbKey);
  assertSignedReadyMedia(videoWithoutThumb, videoBareRow.storage_key);
  assertNoThumbnail(videoWithoutThumb, 'video without thumb');
  assertSignedReadyMedia(audioItem, audioRow.storage_key);
  assertNoThumbnail(audioItem, 'audio');
  assertSignedReadyMedia(documentItem, documentRow.storage_key);
  assertNoThumbnail(documentItem, 'document');
  assertNoStorageKey(kindsItem);

  const strangerAfterKinds = db.state.readUrlCalls.length;
  await expectReject(listFeed(STRANGER_ID, COMMUNITY_ID, {}, deps), 404);
  assert(db.state.readUrlCalls.length === strangerAfterKinds, 'non-member does not sign thumbnail');

  await deleteMedia(MEMBER_ID, COMMUNITY_ID, multi.id, m1.media.id, deps);
  assert(
    !db.state.media.some((item) => Number(item.id) === Number(m1.media.id)),
    'author can delete ready media'
  );
  const multiAfterDelete = db.state.publications.find((item) => Number(item.id) === Number(multi.id));
  const remainingMultiBytes = db.state.media
    .filter(
      (item) =>
        Number(item.community_publication_id) === Number(multi.id) &&
        (item.status === 'ready' || item.status === 'pending_upload')
    )
    .reduce((sum, item) => sum + Number(item.byte_size), 0);
  assert(Number(multiAfterDelete.media_total_bytes) === remainingMultiBytes, 'quota after one delete');
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

  const formerMemberReads = db.state.readUrlCalls.length;
  await expectReject(listFeed(MEMBER_ID, COMMUNITY_ID, {}, deps), 404);
  await expectReject(getPublication(MEMBER_ID, COMMUNITY_ID, readyPub.id, deps), 404);
  await expectReject(patchPublication(MEMBER_ID, COMMUNITY_ID, readyPub.id, { title: 'x' }, deps), 404);
  assert(db.state.readUrlCalls.length === formerMemberReads, 'former member feed does not sign urls');
  const mineLeft = await listMine(MEMBER_ID, { scope: 'left' }, deps);
  assert(mineLeft.items.some((item) => Number(item.id) === Number(readyPub.id)), 'left scope has kept pub');
  assert(mineLeft.items.every((item) => item.status !== 'draft'), 'no drafts in me');
  const leftReady = mineLeft.items.find((item) => Number(item.id) === Number(readyPub.id));
  assert(leftReady.media.length === 1, 'left mine still hydrates ready');
  assertSignedReadyMedia(leftReady.media[0], readyKey);
  assertNoThumbnail(leftReady.media[0], 'image');
  assertNoStorageKey(leftReady);
  const getMineLeft = await getMine(MEMBER_ID, readyPub.id, deps);
  assertSignedReadyMedia(getMineLeft.media[0], readyKey);
  assertNoThumbnail(getMineLeft.media[0], 'image');
  assertNoStorageKey(getMineLeft);

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

  const expiredLive = db.state.publications.find((item) => Number(item.id) === Number(ephemeral.id));
  expiredLive.purge_after = new Date(Date.now() - 1000);
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

  await runDeleteMediaContractChecks();

  console.log('Community publications checks succeeded.');
}

async function uploadReadyImage(authorId, publicationId, byteSize, deps, db) {
  const payload = await createMediaUpload(
    authorId,
    COMMUNITY_ID,
    publicationId,
    { kind: 'image', source_type: 'gallery', content_type: 'image/jpeg', byte_size: byteSize },
    deps
  );
  db.storage.put(
    db.state.media.find((item) => Number(item.id) === Number(payload.media.id)).storage_key,
    byteSize
  );
  await completeMedia(authorId, COMMUNITY_ID, publicationId, payload.media.id, deps);
  return payload;
}

async function runDeleteMediaContractChecks() {
  const db = createMemory();
  const deps = { db, storage: db.storage };

  const last = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete last media', initial_media_count: 1 }),
    deps
  );
  const lastUpload = await uploadReadyImage(MEMBER_ID, last.id, 157908, deps, db);
  db.state.ops = [];
  const lastResult = await deleteMedia(MEMBER_ID, COMMUNITY_ID, last.id, lastUpload.media.id, deps);
  assert(lastResult.deleted === true, 'A deleted true');
  assert(
    !db.state.media.some((item) => sameMediaId(item.id, lastUpload.media.id)),
    'A media row gone'
  );
  const lastPub = db.state.publications.find((item) => Number(item.id) === Number(last.id));
  assert(Number(lastPub.media_total_bytes) === 0, 'A media_total_bytes 0');
  const lastSql = db.state.ops.indexOf('sql-delete');
  const lastCommit = db.state.ops.indexOf('commit');
  const lastR2 = db.state.ops.indexOf('storage-delete');
  assert(lastSql !== -1 && lastCommit !== -1 && lastR2 !== -1, 'A ops present');
  assert(lastSql < lastCommit, 'A sql before commit');
  assert(lastCommit < lastR2, 'A commit before r2');

  const many = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete one of many', initial_media_count: 2 }),
    deps
  );
  const keepUpload = await uploadReadyImage(MEMBER_ID, many.id, 100, deps, db);
  const dropUpload = await uploadReadyImage(MEMBER_ID, many.id, 250, deps, db);
  db.state.ops = [];
  const manyResult = await deleteMedia(MEMBER_ID, COMMUNITY_ID, many.id, dropUpload.media.id, deps);
  assert(manyResult.deleted === true, 'B deleted true');
  assert(
    !db.state.media.some((item) => sameMediaId(item.id, dropUpload.media.id)),
    'B targeted media gone'
  );
  assert(
    db.state.media.some(
      (item) => sameMediaId(item.id, keepUpload.media.id) && item.status === 'ready'
    ),
    'B other media kept'
  );
  const manyPub = db.state.publications.find((item) => Number(item.id) === Number(many.id));
  assert(Number(manyPub.media_total_bytes) === 100, 'B remaining bytes');

  const zero = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete rowcount 0', initial_media_count: 1 }),
    deps
  );
  const zeroUpload = await uploadReadyImage(MEMBER_ID, zero.id, 40, deps, db);
  db.state.deleteRowCountOverride = 0;
  db.state.ops = [];
  await expectReject(deleteMedia(MEMBER_ID, COMMUNITY_ID, zero.id, zeroUpload.media.id, deps), 404);
  assert(
    db.state.media.some((item) => sameMediaId(item.id, zeroUpload.media.id)),
    'C media row kept'
  );
  assert(!db.state.ops.includes('storage-delete'), 'C no r2 after rowCount 0');
  assert(db.state.ops.includes('rollback'), 'C sql not committed as success');

  const big = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete bigint string id', initial_media_count: 1 }),
    deps
  );
  const bigUpload = await uploadReadyImage(MEMBER_ID, big.id, 80, deps, db);
  const bigRow = db.state.media.find((item) => Number(item.id) === Number(bigUpload.media.id));
  bigRow.id = String(bigRow.id);
  bigRow.community_publication_id = String(bigRow.community_publication_id);
  db.state.ops = [];
  const bigResult = await deleteMedia(MEMBER_ID, COMMUNITY_ID, big.id, bigUpload.media.id, deps);
  assert(bigResult.deleted === true, 'D deleted true with string bigint id');
  assert(
    !db.state.media.some((item) => String(item.id) === String(bigUpload.media.id)),
    'D string id row gone'
  );
  const bigPub = db.state.publications.find((item) => Number(item.id) === Number(big.id));
  assert(Number(bigPub.media_total_bytes) === 0, 'D bytes 0');

  const authPub = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete authz', initial_media_count: 1 }),
    deps
  );
  const authUpload = await uploadReadyImage(MEMBER_ID, authPub.id, 15, deps, db);
  await expectReject(
    deleteMedia(OWNER_ID, COMMUNITY_ID, authPub.id, authUpload.media.id, deps),
    403
  );
  await expectReject(deleteMedia(99, COMMUNITY_ID, authPub.id, authUpload.media.id, deps), 404);
  const authorDelete = await deleteMedia(MEMBER_ID, COMMUNITY_ID, authPub.id, authUpload.media.id, deps);
  assert(authorDelete.deleted === true, 'E author can delete');

  const orderPub = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete order', initial_media_count: 1 }),
    deps
  );
  const orderUpload = await uploadReadyImage(MEMBER_ID, orderPub.id, 20, deps, db);
  db.state.ops = [];
  await deleteMedia(MEMBER_ID, COMMUNITY_ID, orderPub.id, orderUpload.media.id, deps);
  const sqlAt = db.state.ops.indexOf('sql-delete');
  const commitAt = db.state.ops.indexOf('commit');
  const r2At = db.state.ops.indexOf('storage-delete');
  assert(sqlAt !== -1 && commitAt !== -1 && r2At !== -1, 'F ops recorded');
  assert(sqlAt < commitAt && commitAt < r2At, 'F sql then commit then r2');

  const failSqlPub = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete sql fail', initial_media_count: 1 }),
    deps
  );
  const failSqlUpload = await uploadReadyImage(MEMBER_ID, failSqlPub.id, 30, deps, db);
  db.state.failSqlDelete = true;
  db.state.ops = [];
  try {
    await deleteMedia(MEMBER_ID, COMMUNITY_ID, failSqlPub.id, failSqlUpload.media.id, deps);
    throw new Error('expected sql delete failure');
  } catch (err) {
    assert(!(err instanceof AppError), 'G not treated as success');
    assert(err && err.message === 'sql delete failed', 'G sql error message');
  }
  db.state.failSqlDelete = false;
  assert(
    db.state.media.some((item) => sameMediaId(item.id, failSqlUpload.media.id)),
    'G media row remains after rollback'
  );
  const failSqlPubRow = db.state.publications.find((item) => Number(item.id) === Number(failSqlPub.id));
  assert(Number(failSqlPubRow.media_total_bytes) === 30, 'G bytes unchanged');
  assert(!db.state.ops.includes('storage-delete'), 'G no r2 before sql validation');
  assert(db.state.ops.includes('rollback'), 'G rolled back');
  assert(!db.state.ops.includes('commit'), 'G no commit');

  const failR2Pub = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validBody({ title: 'Delete r2 fail', initial_media_count: 1 }),
    deps
  );
  const failR2Upload = await uploadReadyImage(MEMBER_ID, failR2Pub.id, 45, deps, db);
  db.state.failStorageDelete = true;
  db.state.ops = [];
  const logged = [];
  const originalError = console.error;
  console.error = (...args) => {
    logged.push(args.map((item) => String(item)).join(' '));
  };
  let failR2Result;
  try {
    failR2Result = await deleteMedia(MEMBER_ID, COMMUNITY_ID, failR2Pub.id, failR2Upload.media.id, deps);
  } finally {
    console.error = originalError;
    db.state.failStorageDelete = false;
  }
  assert(failR2Result && failR2Result.deleted === true, 'H sql success despite r2');
  assert(
    !db.state.media.some((item) => sameMediaId(item.id, failR2Upload.media.id)),
    'H media row stays deleted'
  );
  const failR2PubRow = db.state.publications.find((item) => Number(item.id) === Number(failR2Pub.id));
  assert(Number(failR2PubRow.media_total_bytes) === 0, 'H bytes remain 0');
  assert(
    logged.some((line) => line.includes('[community-media] storage delete failed')),
    'H r2 failure logged'
  );
  const hSql = db.state.ops.indexOf('sql-delete');
  const hCommit = db.state.ops.indexOf('commit');
  const hR2 = db.state.ops.indexOf('storage-delete');
  assert(hSql !== -1 && hCommit !== -1 && hR2 !== -1, 'H ops present');
  assert(hSql < hCommit && hCommit < hR2, 'H r2 only after commit');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
