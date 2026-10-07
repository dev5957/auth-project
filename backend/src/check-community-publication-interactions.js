const AppError = require('./errors/AppError');
const { createPublication, deletePublication, listFeed, getPublication } = require('./services/communityPublicationService');
const { likePublication, unlikePublication } = require('./services/communityPublicationLikeService');
const {
  listComments,
  createComment,
  updateComment,
  deleteComment,
  restoreComment,
  listMyCommentTraces,
} = require('./services/communityPublicationCommentService');
const { leaveCommunity, removeMember } = require('./services/communityService');
const { runExpireActiveJob, runPurgeExpiredJob } = require('./services/communityPublicationJobs');
const {
  parseCreateCommentInput,
  parseCommentListQuery,
} = require('./validators/communityPublicationInteractionFields');

const OWNER_ID = 1;
const ADMIN_ID = 3;
const ADMIN_B_ID = 4;
const MEMBER_ID = 2;
const MEMBER_B_ID = 5;
const STRANGER_ID = 99;
const COMMUNITY_ID = 10;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
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

function validPub(overrides = {}) {
  return {
    title: 'Soiree jardin',
    body: 'Un texte communautaire assez long.',
    publish: 'now',
    comments_enabled: true,
    ...overrides,
  };
}

function memberVisibleComments(comments, publicationId) {
  const rows = comments.filter((item) => Number(item.community_publication_id) === Number(publicationId));
  const byId = new Map(rows.map((item) => [Number(item.id), item]));
  return rows.filter((item) => {
    if (item.status !== 'visible') {
      return false;
    }
    if (item.parent_comment_id == null) {
      return true;
    }
    const parent = byId.get(Number(item.parent_comment_id));
    return Boolean(parent && parent.status === 'visible');
  });
}

function assertCounts(db, publicationId) {
  const pub = db.state.publications.find((item) => Number(item.id) === Number(publicationId));
  const likes = db.state.likes.filter((item) => Number(item.community_publication_id) === Number(publicationId));
  const visible = memberVisibleComments(db.state.comments, publicationId);
  assert(Number(pub.like_count) === likes.length, `like_count ${pub.like_count} != ${likes.length}`);
  assert(Number(pub.comment_count) === visible.length, `comment_count ${pub.comment_count} != ${visible.length}`);
}

function createMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner1' },
    { id: MEMBER_ID, login: 'member2' },
    { id: ADMIN_ID, login: 'admin3' },
    { id: ADMIN_B_ID, login: 'admin4' },
    { id: MEMBER_B_ID, login: 'member5' },
    { id: STRANGER_ID, login: 'stranger99' },
  ];
  const state = {
    communities: [{ id: COMMUNITY_ID, name: 'Jardin secret', created_by: OWNER_ID }],
    members: [
      { community_id: COMMUNITY_ID, user_id: OWNER_ID, role: 'owner' },
      { community_id: COMMUNITY_ID, user_id: MEMBER_ID, role: 'member' },
      { community_id: COMMUNITY_ID, user_id: ADMIN_ID, role: 'admin' },
      { community_id: COMMUNITY_ID, user_id: ADMIN_B_ID, role: 'admin' },
      { community_id: COMMUNITY_ID, user_id: MEMBER_B_ID, role: 'member' },
    ],
    publications: [],
    likes: [],
    comments: [],
    traces: [],
    failTraceInsert: false,
  };
  let nextPubId = 1;
  let nextLikeId = 1;
  let nextCommentId = 1;
  let nextTraceId = 1;
  let snapshot = null;

  function cloneState() {
    return {
      publications: state.publications.map((item) => ({ ...item })),
      likes: state.likes.map((item) => ({ ...item })),
      comments: state.comments.map((item) => ({ ...item })),
      traces: state.traces.map((item) => ({ ...item })),
      members: state.members.map((item) => ({ ...item })),
      nextPubId,
      nextLikeId,
      nextCommentId,
      nextTraceId,
    };
  }

  async function query(sql, params = []) {
    const key = sqlKey(sql);
    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      if (key === 'BEGIN') {
        snapshot = cloneState();
      } else if (key === 'COMMIT') {
        snapshot = null;
      } else if (snapshot) {
        state.publications = snapshot.publications;
        state.likes = snapshot.likes;
        state.comments = snapshot.comments;
        state.traces = snapshot.traces;
        state.members = snapshot.members;
        nextPubId = snapshot.nextPubId;
        nextLikeId = snapshot.nextLikeId;
        nextCommentId = snapshot.nextCommentId;
        nextTraceId = snapshot.nextTraceId;
        snapshot = null;
      }
      return { rows: [], rowCount: 0 };
    }
    if (
      key.includes('FROM COMMUNITY_MEMBERS') &&
      key.includes('USER_ID') &&
      (key.includes('LIMIT 1') || key.includes('FOR UPDATE')) &&
      !key.includes('COUNT(*)')
    ) {
      const row = state.members.find(
        (item) => Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return {
        rows: row ? [{ user_id: row.user_id, role: row.role, role_assigned_at: null }] : [],
        rowCount: row ? 1 : 0,
      };
    }
    if (key.includes("ROLE = 'OWNER'") && key.includes('COUNT(*)')) {
      const count = state.members.filter(
        (item) => Number(item.community_id) === Number(params[0]) && item.role === 'owner'
      ).length;
      return { rows: [{ owner_count: count }], rowCount: 1 };
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
        like_count: 0,
        comment_count: 0,
        created_at: now,
        updated_at: now,
        expired_at: null,
        purge_after: null,
      };
      nextPubId += 1;
      state.publications.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATIONS P') && key.includes("P.STATUS = 'ACTIVE'")) {
      const rows = state.publications
        .filter((item) => Number(item.community_id) === Number(params[0]) && item.status === 'active')
        .map((item) => ({
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
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('WHERE ID = $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }
    if (key.startsWith('SELECT ID') && key.includes('FROM COMMUNITY_PUBLICATIONS') && key.includes('ANY($1')) {
      const ids = (Array.isArray(params[0]) ? params[0] : []).map((value) => Number(value));
      const rows = state.publications
        .filter((item) => ids.includes(Number(item.id)))
        .sort((a, b) => Number(a.id) - Number(b.id))
        .map((item) => ({ id: item.id }));
      return { rows, rowCount: rows.length };
    }
    if (
      key.startsWith('SELECT STATUS, AUTHOR_USER_ID FROM COMMUNITY_PUBLICATIONS') ||
      key.startsWith('SELECT STATUS FROM COMMUNITY_PUBLICATIONS')
    ) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.community_id) === Number(params[1])
      );
      return {
        rows: row ? [{ status: row.status, author_user_id: row.author_user_id }] : [],
        rowCount: row ? 1 : 0,
      };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATION_MEDIA')) {
      return { rows: [], rowCount: 0 };
    }
    if (key.startsWith('SELECT 1') && key.includes('FROM COMMUNITY_PUBLICATION_LIKES')) {
      const row = state.likes.find(
        (item) =>
          Number(item.community_publication_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [1] : [], rowCount: row ? 1 : 0 };
    }
    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATION_LIKES')) {
      const exists = state.likes.some(
        (item) =>
          Number(item.community_publication_id) === Number(params[1]) && Number(item.user_id) === Number(params[2])
      );
      if (exists) {
        return { rows: [], rowCount: 0 };
      }
      const row = {
        id: nextLikeId,
        community_id: params[0],
        community_publication_id: params[1],
        user_id: params[2],
      };
      nextLikeId += 1;
      state.likes.push(row);
      return { rows: [{ id: row.id }], rowCount: 1 };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('COMMUNITY_PUBLICATION_ID') && key.includes('USER_ID')) {
      const before = state.likes.length;
      const removed = state.likes.filter(
        (item) =>
          Number(item.community_publication_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      state.likes = state.likes.filter(
        (item) =>
          !(Number(item.community_publication_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: removed.map((item) => ({ id: item.id })), rowCount: before - state.likes.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('COMMUNITY_ID = $1')) {
      state.likes = state.likes.filter(
        (item) => !(Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: [], rowCount: 0 };
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
      const rows = ids.map((community_publication_id) => ({ community_publication_id }));
      return { rows, rowCount: rows.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES')) {
      state.likes = state.likes.filter((item) => Number(item.community_publication_id) !== Number(params[0]));
      return { rows: [], rowCount: 0 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = LIKE_COUNT + 1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.like_count = (Number(row.like_count) || 0) + 1;
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = GREATEST(LIKE_COUNT - 1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.like_count = Math.max((Number(row.like_count) || 0) - 1, 0);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = GREATEST(LIKE_COUNT - $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]));
      row.like_count = Math.max((Number(row.like_count) || 0) - Number(params[0]), 0);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = 0')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.like_count = 0;
      row.comment_count = 0;
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('COMMENT_COUNT = (')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.comment_count = memberVisibleComments(state.comments, params[0]).length;
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('COMMENT_COUNT = GREATEST')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]));
      row.comment_count = Math.max((Number(row.comment_count) || 0) + Number(params[0]), 0);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('DELETED_BY_USER_ID')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[3]));
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'deleted';
      row.deleted_at = params[1];
      row.deleted_by_user_id = params[2];
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'")) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[3]));
      if (!row || row.status !== 'active') {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'expired';
      row.expired_at = params[0];
      row.purge_after = params[1];
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('IS_TIME_LIMITED = TRUE')) {
      const now = params[0];
      const rows = state.publications.filter(
        (item) =>
          item.status === 'active' &&
          item.is_time_limited &&
          item.expires_at &&
          new Date(item.expires_at) <= new Date(now)
      );
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'") && key.includes('PURGE_AFTER')) {
      const now = params[0];
      const rows = state.publications.filter(
        (item) => item.status === 'expired' && item.purge_after && new Date(item.purge_after) <= new Date(now)
      );
      return { rows: rows.map((item) => ({ ...item })), rowCount: rows.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'")) {
      const before = state.publications.length;
      state.publications = state.publications.filter(
        (item) => !(Number(item.id) === Number(params[0]) && item.status === 'expired')
      );
      return { rows: before === state.publications.length ? [] : [{ id: params[0] }], rowCount: before - state.publications.length };
    }
    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATION_COMMENTS')) {
      const row = {
        id: nextCommentId,
        community_id: params[0],
        community_publication_id: params[1],
        author_user_id: params[2],
        body: params[3],
        status: params[4],
        parent_comment_id: params[5] == null ? null : params[5],
        created_at: new Date(),
        updated_at: new Date(),
        deleted_at: null,
        deleted_by_user_id: null,
        moderated_by_role: null,
      };
      nextCommentId += 1;
      state.comments.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    function hydrateComment(item) {
      return {
        ...item,
        author_login: (users.find((u) => Number(u.id) === Number(item.author_user_id)) || {}).login,
        is_former_member: !state.members.some(
          (m) => Number(m.community_id) === Number(item.community_id) && Number(m.user_id) === Number(item.author_user_id)
        ),
      };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATION_COMMENTS C') && key.includes('PARENT_COMMENT_ID = ANY')) {
      const includeModerated = key.includes("IN ('VISIBLE', 'MODERATED')");
      const parentIds = (Array.isArray(params[0]) ? params[0] : []).map((value) => Number(value));
      let rows = state.comments.filter((item) => parentIds.includes(Number(item.parent_comment_id)));
      rows = rows.filter((item) =>
        includeModerated ? item.status === 'visible' || item.status === 'moderated' : item.status === 'visible'
      );
      rows.sort((a, b) => new Date(a.created_at) - new Date(b.created_at) || Number(a.id) - Number(b.id));
      rows = rows.map(hydrateComment);
      return { rows, rowCount: rows.length };
    }
    if (
      key.includes('FROM COMMUNITY_PUBLICATION_COMMENTS C') &&
      key.includes('PARENT_COMMENT_ID IS NULL') &&
      key.includes('ORDER BY C.CREATED_AT DESC')
    ) {
      const includeModerated = key.includes("IN ('VISIBLE', 'MODERATED')");
      let rows = state.comments.filter(
        (item) => Number(item.community_publication_id) === Number(params[0]) && item.parent_comment_id == null
      );
      rows = rows.filter((item) =>
        includeModerated ? item.status === 'visible' || item.status === 'moderated' : item.status === 'visible'
      );
      rows.sort((a, b) => new Date(b.created_at) - new Date(a.created_at) || Number(b.id) - Number(a.id));
      const limit = Number(params[params.length - 1]);
      rows = rows.slice(0, limit).map(hydrateComment);
      return { rows, rowCount: rows.length };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATION_COMMENTS C') && key.includes('ORDER BY C.CREATED_AT DESC')) {
      const includeModerated = key.includes("IN ('VISIBLE', 'MODERATED')");
      let rows = state.comments.filter((item) => Number(item.community_publication_id) === Number(params[0]));
      rows = rows.filter((item) =>
        includeModerated ? item.status === 'visible' || item.status === 'moderated' : item.status === 'visible'
      );
      rows.sort((a, b) => new Date(b.created_at) - new Date(a.created_at) || Number(b.id) - Number(a.id));
      const limit = Number(params[params.length - 1]);
      rows = rows.slice(0, limit).map(hydrateComment);
      return { rows, rowCount: rows.length };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATION_COMMENTS C') && key.includes('C.ID = $1')) {
      const row = state.comments.find(
        (item) =>
          Number(item.id) === Number(params[0]) &&
          Number(item.community_id) === Number(params[1]) &&
          Number(item.community_publication_id) === Number(params[2])
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rows: [
          {
            ...row,
            author_login: (users.find((u) => Number(u.id) === Number(row.author_user_id)) || {}).login,
            is_former_member: !state.members.some(
              (m) => Number(m.community_id) === Number(row.community_id) && Number(m.user_id) === Number(row.author_user_id)
            ),
          },
        ],
        rowCount: 1,
      };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATION_COMMENTS') && key.includes('FOR UPDATE')) {
      const row = state.comments.find(
        (item) =>
          Number(item.id) === Number(params[0]) && Number(item.community_publication_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATION_COMMENTS') && key.includes('BODY = $1')) {
      const row = state.comments.find((item) => Number(item.id) === Number(params[1]));
      row.body = params[0];
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATION_COMMENTS') && key.includes("STATUS = $1") && key.includes('AUTHOR_DELETED') === false) {
      const row = state.comments.find((item) => Number(item.id) === Number(params[params.length - 1]));
      if (!row || (key.includes("STATUS = 'VISIBLE'") && row.status !== 'moderated')) {
        if (params[0] === 'visible' && row && row.status === 'moderated') {
          row.status = 'visible';
          row.deleted_at = null;
          row.deleted_by_user_id = null;
          row.moderated_by_role = null;
          return { rows: [{ id: row.id }], rowCount: 1 };
        }
      }
      if (params[0] === 'author_deleted' || params[0] === 'moderated') {
        if (row.status !== 'visible') {
          return { rows: [], rowCount: 0 };
        }
        row.status = params[0];
        row.deleted_at = params[1];
        row.deleted_by_user_id = params[2];
        row.moderated_by_role = params[0] === 'moderated' ? params[3] : null;
        return { rows: [{ ...row }], rowCount: 1 };
      }
      if (params[0] === 'visible') {
        if (row.status !== 'moderated') {
          return { rows: [], rowCount: 0 };
        }
        row.status = 'visible';
        row.deleted_at = null;
        row.deleted_by_user_id = null;
        row.moderated_by_role = null;
        return { rows: [{ id: row.id }], rowCount: 1 };
      }
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_COMMENTS')) {
      state.comments = state.comments.filter((item) => Number(item.community_publication_id) !== Number(params[0]));
      return { rows: [], rowCount: 0 };
    }
    if (key.startsWith('INSERT INTO COMMUNITY_COMMENT_EPHEMERAL_TRACES')) {
      if (state.failTraceInsert) {
        throw new Error('trace snapshot failed');
      }
      const pub = state.publications.find((item) => Number(item.id) === Number(params[0]));
      const author = users.find((item) => Number(item.id) === Number(pub.author_user_id));
      let n = 0;
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
          community_publication_id: pub.id,
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
        n += 1;
      }
      return { rows: [], rowCount: n };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_COMMENT_EPHEMERAL_TRACES')) {
      let rows = state.traces.filter((item) => Number(item.user_id) === Number(params[0]));
      rows.sort(
        (a, b) =>
          new Date(b.comment_created_at) - new Date(a.comment_created_at) || Number(b.comment_id) - Number(a.comment_id)
      );
      const limit = Number(params[params.length - 1]);
      rows = rows.slice(0, limit);
      return { rows, rowCount: rows.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_MEMBERS')) {
      state.members = state.members.filter(
        (item) => !(Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: [], rowCount: 1 };
    }
    if (key.includes('FROM COMMUNITIES') && key.includes('FOR UPDATE')) {
      const row = state.communities.find((item) => Number(item.id) === Number(params[0]));
      return { rows: row ? [{ id: row.id, created_by: row.created_by }] : [], rowCount: row ? 1 : 0 };
    }
    if (key.includes("STATUS = 'DRAFT'") && key.includes('AUTHOR_USER_ID')) {
      return { rows: [], rowCount: 0 };
    }
    if (key.includes('COMMUNITY_PUBLICATION_MEDIA')) {
      return { rows: [], rowCount: 0 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS')) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[params.length - 1]) || Number(item.id) === Number(params[0])
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      if (key.includes('DELETED_BY_USER_ID')) {
        row.status = 'deleted';
        row.deleted_at = params[1];
        row.deleted_by_user_id = params[2];
      }
      return { rows: [{ ...row }], rowCount: 1 };
    }
    throw new Error(`unexpected sql: ${key.slice(0, 180)}`);
  }

  return {
    state,
    query,
    connect: async () => ({ query, release() {} }),
  };
}

async function main() {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://community-interactions-test/local';
  expectReject;
  try {
    parseCreateCommentInput({ body: 'a' });
    throw new Error('min body');
  } catch (err) {
    assert(err.statusCode === 400, 'min body 400');
  }
  parseCreateCommentInput({ body: 'ok' });
  try {
    parseCreateCommentInput({ body: 'x'.repeat(201) });
    throw new Error('max body');
  } catch (err) {
    assert(err.statusCode === 400, 'max body 400');
  }
  try {
    parseCommentListQuery({ limit: '21' });
    throw new Error('comment limit');
  } catch (err) {
    assert(err.statusCode === 400, 'comment page max 20');
  }

  const db = createMemory();
  const deps = {
    db,
    storage: {
      async delete() {},
      async createReadUrl() {
        return { url: 'https://read.test/x' };
      },
      async head() {
        return null;
      },
      async createDirectUpload() {
        return {};
      },
    },
  };

  const pub = await createPublication(MEMBER_ID, COMMUNITY_ID, validPub(), deps);
  const disabled = await createPublication(MEMBER_ID, COMMUNITY_ID, validPub({ comments_enabled: false, title: 'Sans comments' }), deps);

  const firstLike = await likePublication(OWNER_ID, COMMUNITY_ID, pub.id, deps);
  assert(firstLike.liked === true && firstLike.like_count === 1 && firstLike.liked_by_me === true, 'like');
  const again = await likePublication(OWNER_ID, COMMUNITY_ID, pub.id, deps);
  assert(again.like_count === 1, 'idempotent like');
  assertCounts(db, pub.id);

  const un = await unlikePublication(OWNER_ID, COMMUNITY_ID, pub.id, deps);
  assert(un.liked === false && un.like_count === 0, 'unlike');
  const un2 = await unlikePublication(OWNER_ID, COMMUNITY_ID, pub.id, deps);
  assert(un2.like_count === 0, 'idempotent unlike');
  assertCounts(db, pub.id);

  await likePublication(MEMBER_B_ID, COMMUNITY_ID, pub.id, deps);
  await expectReject(likePublication(STRANGER_ID, COMMUNITY_ID, pub.id, deps), 404);

  const scheduled = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validPub({ publish: 'schedule', scheduled_at: new Date(Date.now() + 86400000).toISOString(), title: 'Plus tard' }),
    deps
  );
  await expectReject(likePublication(OWNER_ID, COMMUNITY_ID, scheduled.id, deps), 404);

  const comment = await createComment(OWNER_ID, COMMUNITY_ID, pub.id, { body: 'Super soiree' }, deps);
  assert(comment.body === 'Super soiree' && comment.status === 'visible', 'comment created');
  assertCounts(db, pub.id);
  await expectReject(createComment(OWNER_ID, COMMUNITY_ID, disabled.id, { body: 'Nope' }, deps), 400);

  const listed = await listComments(MEMBER_ID, COMMUNITY_ID, pub.id, {}, deps);
  assert(listed.items.length === 1, 'member sees visible');

  const edited = await updateComment(OWNER_ID, COMMUNITY_ID, pub.id, comment.id, { body: 'Texte edite' }, deps);
  assert(edited.body === 'Texte edite', 'author edit');
  await expectReject(updateComment(MEMBER_ID, COMMUNITY_ID, pub.id, comment.id, { body: 'Hack' }, deps), 403);

  const other = await createComment(MEMBER_B_ID, COMMUNITY_ID, pub.id, { body: 'Moi aussi' }, deps);
  await deleteComment(MEMBER_B_ID, COMMUNITY_ID, pub.id, other.id, deps);
  assert(db.state.comments.find((item) => Number(item.id) === Number(other.id)).status === 'author_deleted', 'self delete');
  assertCounts(db, pub.id);
  await expectReject(restoreComment(OWNER_ID, COMMUNITY_ID, pub.id, other.id, deps), 404);

  const third = await createComment(MEMBER_ID, COMMUNITY_ID, pub.id, { body: 'A moderer' }, deps);
  await deleteComment(ADMIN_ID, COMMUNITY_ID, pub.id, third.id, deps);
  assert(db.state.comments.find((item) => Number(item.id) === Number(third.id)).status === 'moderated', 'admin moderate');
  const restored = await restoreComment(OWNER_ID, COMMUNITY_ID, pub.id, third.id, deps);
  assert(restored.status === 'visible', 'owner restores admin moderation');
  assertCounts(db, pub.id);

  const fourth = await createComment(MEMBER_ID, COMMUNITY_ID, pub.id, { body: 'Encore' }, deps);
  await deleteComment(ADMIN_ID, COMMUNITY_ID, pub.id, fourth.id, deps);
  const restoredByAdmin = await restoreComment(ADMIN_B_ID, COMMUNITY_ID, pub.id, fourth.id, deps);
  assert(restoredByAdmin.status === 'visible', 'other admin restores');

  const fifth = await createComment(MEMBER_ID, COMMUNITY_ID, pub.id, { body: 'Staff leave' }, deps);
  await deleteComment(ADMIN_ID, COMMUNITY_ID, pub.id, fifth.id, deps);
  await leaveCommunity(ADMIN_ID, COMMUNITY_ID, deps);
  await expectReject(restoreComment(ADMIN_ID, COMMUNITY_ID, pub.id, fifth.id, deps), 404);
  const restoredAfter = await restoreComment(ADMIN_B_ID, COMMUNITY_ID, pub.id, fifth.id, deps);
  assert(restoredAfter.status === 'visible', 'active admin restores after other left');

  const byAuthor = await createComment(OWNER_ID, COMMUNITY_ID, pub.id, { body: 'Auteur pub' }, deps);
  await deleteComment(MEMBER_ID, COMMUNITY_ID, pub.id, byAuthor.id, deps);
  assert(
    db.state.comments.find((item) => Number(item.id) === Number(byAuthor.id)).moderated_by_role ===
      'publication_author',
    'publication author moderate'
  );
  assertCounts(db, pub.id);

  const thread = await createPublication(MEMBER_ID, COMMUNITY_ID, validPub({ title: 'Fil reponses' }), deps);
  const root = await createComment(OWNER_ID, COMMUNITY_ID, thread.id, { body: 'Commentaire racine' }, deps);
  assert(root.parent_comment_id == null, 'root parent null');
  const reply = await createComment(
    MEMBER_B_ID,
    COMMUNITY_ID,
    thread.id,
    { body: 'Une reponse', parent_comment_id: root.id },
    deps
  );
  assert(Number(reply.parent_comment_id) === Number(root.id), 'reply parent_comment_id');
  assertCounts(db, thread.id);
  const threadListed = await listComments(MEMBER_B_ID, COMMUNITY_ID, thread.id, {}, deps);
  assert(threadListed.items.length === 2, 'get returns root then reply');
  assert(threadListed.items[0].parent_comment_id == null, 'get root parent null');
  assert(Number(threadListed.items[1].parent_comment_id) === Number(root.id), 'get reply parent');
  const selfReply = await createComment(
    OWNER_ID,
    COMMUNITY_ID,
    thread.id,
    { body: 'Self reply ok', parent_comment_id: root.id },
    deps
  );
  assert(Number(selfReply.parent_comment_id) === Number(root.id), 'self-reply');
  assertCounts(db, thread.id);
  await expectReject(
    createComment(OWNER_ID, COMMUNITY_ID, thread.id, { body: 'missing parent', parent_comment_id: 999999 }, deps),
    404
  );
  await expectReject(
    createComment(OWNER_ID, COMMUNITY_ID, thread.id, { body: 'other pub parent', parent_comment_id: comment.id }, deps),
    404
  );
  await expectReject(
    createComment(OWNER_ID, COMMUNITY_ID, thread.id, { body: 'nested reply', parent_comment_id: reply.id }, deps),
    400
  );

  await deleteComment(MEMBER_ID, COMMUNITY_ID, thread.id, reply.id, deps);
  assert(db.state.comments.find((item) => Number(item.id) === Number(reply.id)).status === 'moderated', 'author pub moderates reply');
  const restoredReply = await restoreComment(MEMBER_ID, COMMUNITY_ID, thread.id, reply.id, deps);
  assert(restoredReply.status === 'visible', 'author pub restores reply');
  assertCounts(db, thread.id);

  await deleteComment(MEMBER_ID, COMMUNITY_ID, thread.id, selfReply.id, deps);
  assert(
    db.state.comments.find((item) => Number(item.id) === Number(selfReply.id)).status === 'moderated',
    'author pub moderates comment'
  );
  const restoredSelf = await restoreComment(MEMBER_ID, COMMUNITY_ID, thread.id, selfReply.id, deps);
  assert(restoredSelf.status === 'visible', 'author pub restores comment');
  assertCounts(db, thread.id);

  const beforeParentMod = Number(db.state.publications.find((item) => Number(item.id) === Number(thread.id)).comment_count);
  await deleteComment(MEMBER_ID, COMMUNITY_ID, thread.id, root.id, deps);
  assert(db.state.comments.find((item) => Number(item.id) === Number(root.id)).status === 'moderated', 'parent moderated');
  assert(db.state.comments.find((item) => Number(item.id) === Number(reply.id)).status === 'visible', 'child not cascaded');
  const afterParentMod = Number(db.state.publications.find((item) => Number(item.id) === Number(thread.id)).comment_count);
  assert(afterParentMod === 0, `parent moderate hides branch count got ${afterParentMod} from ${beforeParentMod}`);
  const memberHidden = await listComments(MEMBER_B_ID, COMMUNITY_ID, thread.id, {}, deps);
  assert(memberHidden.items.length === 0, 'member cannot see moderated branch');
  const authorSees = await listComments(MEMBER_ID, COMMUNITY_ID, thread.id, {}, deps);
  assert(authorSees.items.some((item) => Number(item.id) === Number(root.id) && item.status === 'moderated'), 'pub author sees moderated parent');
  assert(authorSees.items.some((item) => Number(item.id) === Number(reply.id)), 'pub author sees replies of moderated parent');
  const ownerSees = await listComments(OWNER_ID, COMMUNITY_ID, thread.id, {}, deps);
  assert(ownerSees.items.some((item) => Number(item.id) === Number(root.id)), 'owner still sees moderated branch');
  const restoredParent = await restoreComment(MEMBER_ID, COMMUNITY_ID, thread.id, root.id, deps);
  assert(restoredParent.status === 'visible', 'author pub restores parent');
  assertCounts(db, thread.id);
  const memberAfterRestore = await listComments(MEMBER_B_ID, COMMUNITY_ID, thread.id, {}, deps);
  assert(memberAfterRestore.items.length >= 2, 'branch visible again after restore');

  const adminRoot = await createComment(MEMBER_B_ID, COMMUNITY_ID, thread.id, { body: 'Admin root' }, deps);
  await deleteComment(OWNER_ID, COMMUNITY_ID, thread.id, adminRoot.id, deps);
  const adminRestored = await restoreComment(ADMIN_B_ID, COMMUNITY_ID, thread.id, adminRoot.id, deps);
  assert(adminRestored.status === 'visible', 'admin restore unchanged');
  await expectReject(restoreComment(MEMBER_B_ID, COMMUNITY_ID, thread.id, adminRoot.id, deps), 403);
  await expectReject(listComments(STRANGER_ID, COMMUNITY_ID, thread.id, {}, deps), 404);
  await expectReject(createComment(STRANGER_ID, COMMUNITY_ID, thread.id, { body: 'nope' }, deps), 404);
  await expectReject(createComment(OWNER_ID, COMMUNITY_ID, scheduled.id, { body: 'inactive' }, deps), 404);
  await expectReject(
    createComment(OWNER_ID, COMMUNITY_ID, disabled.id, { body: 'still disabled', parent_comment_id: root.id }, deps),
    400
  );
  assertCounts(db, thread.id);

  await expectReject(deleteComment(MEMBER_ID, COMMUNITY_ID, pub.id, 999999, deps), 404);
  const visibleOwn = await createComment(MEMBER_ID, COMMUNITY_ID, pub.id, { body: 'Oracle own' }, deps);
  assert((await deleteComment(MEMBER_ID, COMMUNITY_ID, pub.id, visibleOwn.id, deps)).deleted === true, 'self delete');
  assert(
    (await deleteComment(MEMBER_ID, COMMUNITY_ID, pub.id, visibleOwn.id, deps)).deleted === true,
    'self delete idempotent'
  );
  const visibleOther = await createComment(OWNER_ID, COMMUNITY_ID, pub.id, { body: 'Oracle other' }, deps);
  const visibleOtherRow = db.state.comments.find((item) => Number(item.id) === Number(visibleOther.id));
  assert(Number(visibleOtherRow.author_user_id) === OWNER_ID, 'oracle other author');
  await expectReject(deleteComment(MEMBER_B_ID, COMMUNITY_ID, pub.id, visibleOther.id, deps), 403);
  const toMod = await createComment(MEMBER_ID, COMMUNITY_ID, pub.id, { body: 'Oracle mod' }, deps);
  await deleteComment(ADMIN_B_ID, COMMUNITY_ID, pub.id, toMod.id, deps);
  await expectReject(deleteComment(MEMBER_B_ID, COMMUNITY_ID, pub.id, toMod.id, deps), 404);
  assert(
    (await deleteComment(OWNER_ID, COMMUNITY_ID, pub.id, toMod.id, deps)).deleted === true,
    'owner idempotent moderated delete'
  );
  const hiddenSelf = await createComment(OWNER_ID, COMMUNITY_ID, pub.id, { body: 'Oracle hidden' }, deps);
  await deleteComment(OWNER_ID, COMMUNITY_ID, pub.id, hiddenSelf.id, deps);
  await expectReject(deleteComment(MEMBER_B_ID, COMMUNITY_ID, pub.id, hiddenSelf.id, deps), 404);
  await expectReject(deleteComment(ADMIN_B_ID, COMMUNITY_ID, pub.id, hiddenSelf.id, deps), 404);
  await expectReject(deleteComment(ADMIN_ID, COMMUNITY_ID, pub.id, toMod.id, deps), 404);
  assertCounts(db, pub.id);

  const extraPub = await createPublication(OWNER_ID, COMMUNITY_ID, validPub({ title: 'Second fil' }), deps);
  await likePublication(MEMBER_B_ID, COMMUNITY_ID, extraPub.id, deps);
  await likePublication(MEMBER_B_ID, COMMUNITY_ID, pub.id, deps);
  assertCounts(db, extraPub.id);
  assertCounts(db, pub.id);

  await leaveCommunity(MEMBER_B_ID, COMMUNITY_ID, deps);
  assert(!db.state.likes.some((item) => Number(item.user_id) === MEMBER_B_ID), 'leave deletes likes');
  assertCounts(db, pub.id);
  assertCounts(db, extraPub.id);
  await expectReject(likePublication(MEMBER_B_ID, COMMUNITY_ID, pub.id, deps), 404);

  const feed = await listFeed(OWNER_ID, COMMUNITY_ID, {}, deps);
  const feedItem = feed.items.find((item) => Number(item.id) === Number(pub.id));
  assert(typeof feedItem.like_count === 'number', 'feed like_count');
  assert(typeof feedItem.liked_by_me === 'boolean', 'feed liked_by_me');

  const ephemeral = await createPublication(
    MEMBER_ID,
    COMMUNITY_ID,
    validPub({
      title: 'Ephemere',
      is_time_limited: true,
      expires_at: new Date(Date.now() + 60 * 1000).toISOString(),
    }),
    deps
  );
  const keep = await createComment(OWNER_ID, COMMUNITY_ID, ephemeral.id, { body: 'Visible keep' }, deps);
  const goneSelf = await createComment(OWNER_ID, COMMUNITY_ID, ephemeral.id, { body: 'Self gone' }, deps);
  await deleteComment(OWNER_ID, COMMUNITY_ID, ephemeral.id, goneSelf.id, deps);
  const goneMod = await createComment(MEMBER_ID, COMMUNITY_ID, ephemeral.id, { body: 'Mod gone' }, deps);
  await deleteComment(OWNER_ID, COMMUNITY_ID, ephemeral.id, goneMod.id, deps);
  const pubRow = db.state.publications.find((item) => Number(item.id) === Number(ephemeral.id));
  pubRow.expires_at = new Date(Date.now() - 1000);
  db.state.failTraceInsert = true;
  try {
    await runExpireActiveJob({ ...deps, now: new Date() });
    throw new Error('expire should rollback when snapshot fails');
  } catch (err) {
    assert(
      !String(err.message).includes('expire should rollback'),
      `unexpected expire success: ${err && err.message}`
    );
  }
  db.state.failTraceInsert = false;
  const rolled = db.state.publications.find((item) => Number(item.id) === Number(ephemeral.id));
  assert(rolled.status === 'active', 'failed snapshot keeps publication active');
  assert(db.state.traces.length === 0, 'no partial traces after rollback');
  await runExpireActiveJob({ ...deps, now: new Date() });
  assert(db.state.traces.length === 1, 'only visible comment traced');
  assert(Number(db.state.traces[0].comment_id) === Number(keep.id), 'trace is visible comment');
  assert(db.state.traces[0].is_ephemeral === true, 'ephemeral flag');
  await expectReject(listComments(OWNER_ID, COMMUNITY_ID, ephemeral.id, {}, deps), 404);
  const traces = await listMyCommentTraces(OWNER_ID, {}, deps);
  assert(traces.items.length === 1 && traces.items[0].comment_body === 'Visible keep', 'author sees own trace');
  const otherTraces = await listMyCommentTraces(MEMBER_ID, {}, deps);
  assert(otherTraces.items.length === 0, 'other author has no trace for moderated');

  const live = db.state.publications.find((item) => Number(item.id) === Number(ephemeral.id));
  live.purge_after = new Date(Date.now() - 1000);
  await runPurgeExpiredJob({ ...deps, now: new Date() });
  const tracesAfterPurge = await listMyCommentTraces(OWNER_ID, {}, deps);
  assert(tracesAfterPurge.items.length === 1, 'trace survives purge');

  await deletePublication(MEMBER_ID, COMMUNITY_ID, pub.id, deps);
  assert(!db.state.likes.some((item) => Number(item.community_publication_id) === Number(pub.id)), 'delete pub likes');
  assert(!db.state.comments.some((item) => Number(item.community_publication_id) === Number(pub.id)), 'delete pub comments');
  const deletedPub = db.state.publications.find((item) => Number(item.id) === Number(pub.id));
  assert(Number(deletedPub.like_count) === 0 && Number(deletedPub.comment_count) === 0, 'counters cleared');
  await expectReject(getPublication(OWNER_ID, COMMUNITY_ID, pub.id, deps), 404);

  await removeMember(OWNER_ID, COMMUNITY_ID, MEMBER_ID, deps);
  await expectReject(createComment(MEMBER_ID, COMMUNITY_ID, disabled.id, { body: 'nope' }, deps), 404);

  console.log('Community publication interactions checks succeeded.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
