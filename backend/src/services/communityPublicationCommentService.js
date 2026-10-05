const pool = require('../db');
const AppError = require('../errors/AppError');
const { parseCommunityId } = require('../validators/communityFields');
const { parseId, STATUS } = require('../validators/communityPublicationFields');
const {
  parseCreateCommentInput,
  parsePatchCommentInput,
  parseCommentId,
  parseCommentListQuery,
  COMMENT_STATUS,
} = require('../validators/communityPublicationInteractionFields');
const {
  withTransaction,
  requireActiveMembership,
  NOT_FOUND,
} = require('./communityPublicationService');
const { lockActivePublication } = require('./communityPublicationLikeService');

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function formatId(value) {
  if (typeof value === 'bigint') {
    const asNumber = Number(value);
    return Number.isSafeInteger(asNumber) ? asNumber : value.toString();
  }
  if (typeof value === 'string' && /^\d+$/.test(value)) {
    const asNumber = Number(value);
    return Number.isSafeInteger(asNumber) ? asNumber : value;
  }
  return value;
}

function toIso(value) {
  if (value == null) {
    return null;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toISOString();
}

function isModerator(membership) {
  return membership && (membership.role === 'owner' || membership.role === 'admin');
}

function toPublicComment(row) {
  return {
    id: formatId(row.id),
    community_id: formatId(row.community_id),
    community_publication_id: formatId(row.community_publication_id),
    body: row.body,
    status: row.status,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    deleted_at: toIso(row.deleted_at),
    author: {
      user_id: formatId(row.author_user_id),
      login: row.author_login || 'unknown',
      is_former_member: Boolean(row.is_former_member),
    },
  };
}

function toPublicTrace(row) {
  return {
    id: formatId(row.id),
    community_id: formatId(row.community_id),
    community_publication_id:
      row.community_publication_id == null ? null : formatId(row.community_publication_id),
    publication_author: {
      user_id: formatId(row.publication_author_user_id),
      login: row.publication_author_login || 'unknown',
    },
    published_at: toIso(row.published_at),
    expired_at: toIso(row.expired_at),
    comment_id: formatId(row.comment_id),
    comment_body: row.comment_body,
    comment_created_at: toIso(row.comment_created_at),
    is_ephemeral: row.is_ephemeral !== false,
    created_at: toIso(row.created_at),
  };
}

async function loadComment(client, communityId, publicationId, commentId) {
  const found = await client.query(
    `SELECT c.*, u.login AS author_login,
            (m.user_id IS NULL) AS is_former_member
     FROM community_publication_comments c
     INNER JOIN users u ON u.id = c.author_user_id
     LEFT JOIN community_members m
       ON m.community_id = c.community_id
      AND m.user_id = c.author_user_id
     WHERE c.id = $1
       AND c.community_id = $2
       AND c.community_publication_id = $3
     LIMIT 1`,
    [commentId, communityId, publicationId]
  );
  return found.rows[0] || null;
}

async function bumpCommentCount(client, publicationId, delta) {
  if (delta === 0) {
    return;
  }
  await client.query(
    `UPDATE community_publications
     SET comment_count = GREATEST(comment_count + $1, 0),
         updated_at = NOW()
     WHERE id = $2`,
    [delta, publicationId]
  );
}

async function listComments(userId, rawCommunityId, rawPublicationId, query, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  const { limit, beforeAt, beforeId } = parseCommentListQuery(query);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const membership = await requireActiveMembership(client, communityId, userId);
    const publication = await client.query(
      `SELECT status FROM community_publications WHERE id = $1 AND community_id = $2 LIMIT 1`,
      [publicationId, communityId]
    );
    if (!publication.rows[0] || publication.rows[0].status !== STATUS.ACTIVE) {
      throw new AppError(404, NOT_FOUND);
    }
    const includeModerated = isModerator(membership);
    const params = [publicationId];
    let cursorSql = '';
    if (beforeAt && beforeId) {
      params.push(beforeAt, beforeId);
      cursorSql = `AND (c.created_at, c.id) < ($2::timestamptz, $3::bigint)`;
    }
    params.push(limit + 1);
    const statusSql = includeModerated
      ? `AND c.status IN ('visible', 'moderated')`
      : `AND c.status = 'visible'`;
    const result = await client.query(
      `SELECT c.*, u.login AS author_login,
              (m.user_id IS NULL) AS is_former_member
       FROM community_publication_comments c
       INNER JOIN users u ON u.id = c.author_user_id
       LEFT JOIN community_members m
         ON m.community_id = c.community_id
        AND m.user_id = c.author_user_id
       WHERE c.community_publication_id = $1
         ${statusSql}
         ${cursorSql}
       ORDER BY c.created_at DESC, c.id DESC
       LIMIT $${params.length}`,
      params
    );
    const hasMore = result.rows.length > limit;
    const page = hasMore ? result.rows.slice(0, limit) : result.rows;
    const last = page[page.length - 1];
    return {
      items: page.map(toPublicComment),
      next:
        hasMore && last
          ? { before_at: toIso(last.created_at), before_id: formatId(last.id) }
          : null,
    };
  });
}

async function createComment(userId, rawCommunityId, rawPublicationId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  const input = parseCreateCommentInput(body);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const publication = await lockActivePublication(client, communityId, publicationId);
    if (!publication.comments_enabled) {
      throw new AppError(400, 'comments are disabled');
    }
    const inserted = await client.query(
      `INSERT INTO community_publication_comments (
         community_id,
         community_publication_id,
         author_user_id,
         body,
         status
       )
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [communityId, publicationId, userId, input.body, COMMENT_STATUS.VISIBLE]
    );
    await bumpCommentCount(client, publicationId, 1);
    const row = await loadComment(client, communityId, publicationId, inserted.rows[0].id);
    return toPublicComment(row);
  });
}

async function updateComment(userId, rawCommunityId, rawPublicationId, rawCommentId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  const commentId = parseCommentId(rawCommentId);
  const input = parsePatchCommentInput(body);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    await lockActivePublication(client, communityId, publicationId);
    const comment = await client.query(
      `SELECT * FROM community_publication_comments
       WHERE id = $1 AND community_publication_id = $2
       FOR UPDATE`,
      [commentId, publicationId]
    );
    const row = comment.rows[0];
    if (!row || row.status !== COMMENT_STATUS.VISIBLE) {
      throw new AppError(404, 'Comment not found');
    }
    if (Number(row.author_user_id) !== Number(userId)) {
      throw new AppError(403, 'Forbidden');
    }
    await client.query(
      `UPDATE community_publication_comments
       SET body = $1,
           updated_at = NOW()
       WHERE id = $2`,
      [input.body, commentId]
    );
    return toPublicComment(await loadComment(client, communityId, publicationId, commentId));
  });
}

function moderationRole(membership, publication, userId) {
  if (membership.role === 'owner' || membership.role === 'admin') {
    return membership.role;
  }
  if (Number(publication.author_user_id) === Number(userId)) {
    return 'publication_author';
  }
  return null;
}

async function deleteComment(userId, rawCommunityId, rawPublicationId, rawCommentId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  const commentId = parseCommentId(rawCommentId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const membership = await requireActiveMembership(client, communityId, userId);
    const publication = await lockActivePublication(client, communityId, publicationId);
    const comment = await client.query(
      `SELECT * FROM community_publication_comments
       WHERE id = $1 AND community_publication_id = $2 AND community_id = $3
       FOR UPDATE`,
      [commentId, publicationId, communityId]
    );
    const row = comment.rows[0];
    if (!row) {
      throw new AppError(404, 'Comment not found');
    }
    const isAuthor = Number(row.author_user_id) === Number(userId);
    if (row.status !== COMMENT_STATUS.VISIBLE) {
      if (isAuthor && row.status === COMMENT_STATUS.AUTHOR_DELETED) {
        return { deleted: true };
      }
      if (isModerator(membership) && row.status === COMMENT_STATUS.MODERATED) {
        return { deleted: true };
      }
      throw new AppError(404, 'Comment not found');
    }
    const now = deps.now || new Date();
    const role = moderationRole(membership, publication, userId);
    if (isAuthor) {
      await client.query(
        `UPDATE community_publication_comments
         SET status = $1,
             deleted_at = $2,
             deleted_by_user_id = $3,
             moderated_by_role = NULL,
             updated_at = $2
         WHERE id = $4 AND status = 'visible'`,
        [COMMENT_STATUS.AUTHOR_DELETED, now, userId, commentId]
      );
    } else if (role) {
      await client.query(
        `UPDATE community_publication_comments
         SET status = $1,
             deleted_at = $2,
             deleted_by_user_id = $3,
             moderated_by_role = $4,
             updated_at = $2
         WHERE id = $5 AND status = 'visible'`,
        [COMMENT_STATUS.MODERATED, now, userId, role, commentId]
      );
    } else {
      throw new AppError(403, 'Forbidden');
    }
    await bumpCommentCount(client, publicationId, -1);
    return { deleted: true };
  });
}

async function restoreComment(userId, rawCommunityId, rawPublicationId, rawCommentId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  const commentId = parseCommentId(rawCommentId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const membership = await requireActiveMembership(client, communityId, userId);
    if (!isModerator(membership)) {
      throw new AppError(403, 'Forbidden');
    }
    await lockActivePublication(client, communityId, publicationId);
    const comment = await client.query(
      `SELECT * FROM community_publication_comments
       WHERE id = $1 AND community_publication_id = $2 AND community_id = $3
       FOR UPDATE`,
      [commentId, publicationId, communityId]
    );
    const row = comment.rows[0];
    if (!row || row.status === COMMENT_STATUS.AUTHOR_DELETED) {
      throw new AppError(404, 'Comment not found');
    }
    if (row.status === COMMENT_STATUS.VISIBLE) {
      return toPublicComment(await loadComment(client, communityId, publicationId, commentId));
    }
    const restored = await client.query(
      `UPDATE community_publication_comments
       SET status = $1,
           deleted_at = NULL,
           deleted_by_user_id = NULL,
           moderated_by_role = NULL,
           updated_at = NOW()
       WHERE id = $2 AND status = 'moderated'
       RETURNING id`,
      [COMMENT_STATUS.VISIBLE, commentId]
    );
    if (restored.rowCount === 1) {
      await bumpCommentCount(client, publicationId, 1);
    }
    return toPublicComment(await loadComment(client, communityId, publicationId, commentId));
  });
}

async function listMyCommentTraces(userId, query, deps = {}) {
  const { limit, beforeAt, beforeId } = parseCommentListQuery(query);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const params = [userId];
    let cursorSql = '';
    if (beforeAt && beforeId) {
      params.push(beforeAt, beforeId);
      cursorSql = `AND (comment_created_at, comment_id) < ($2::timestamptz, $3::bigint)`;
    }
    params.push(limit + 1);
    const result = await client.query(
      `SELECT *
       FROM community_comment_ephemeral_traces
       WHERE user_id = $1
         ${cursorSql}
       ORDER BY comment_created_at DESC, comment_id DESC
       LIMIT $${params.length}`,
      params
    );
    const hasMore = result.rows.length > limit;
    const page = hasMore ? result.rows.slice(0, limit) : result.rows;
    const last = page[page.length - 1];
    return {
      items: page.map(toPublicTrace),
      next:
        hasMore && last
          ? { before_at: toIso(last.comment_created_at), before_id: formatId(last.comment_id) }
          : null,
    };
  });
}

async function snapshotVisibleCommentTraces(query, publication) {
  await query(
    `INSERT INTO community_comment_ephemeral_traces (
       user_id,
       community_id,
       community_publication_id,
       publication_author_user_id,
       publication_author_login,
       published_at,
       expired_at,
       comment_id,
       comment_body,
       comment_created_at,
       is_ephemeral
     )
     SELECT
       c.author_user_id,
       c.community_id,
       c.community_publication_id,
       p.author_user_id,
       u.login,
       p.published_at,
       p.expired_at,
       c.id,
       c.body,
       c.created_at,
       TRUE
     FROM community_publication_comments c
     INNER JOIN community_publications p ON p.id = c.community_publication_id
     INNER JOIN users u ON u.id = p.author_user_id
     WHERE c.community_publication_id = $1
       AND c.status = 'visible'
     ON CONFLICT (comment_id) DO NOTHING`,
    [publication.id]
  );
}

module.exports = {
  listComments,
  createComment,
  updateComment,
  deleteComment,
  restoreComment,
  listMyCommentTraces,
  snapshotVisibleCommentTraces,
  toPublicComment,
};
