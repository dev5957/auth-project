const pool = require('../db');
const AppError = require('../errors/AppError');
const { getStorage } = require('./storageService');
const { thumbnailStorageKey } = require('./mediaStorageKeys');
const {
  parseCreateInput,
  parsePatchInput,
  parseFeedQuery,
  parseMeQuery,
  parseId,
  STATUS,
  PURGE_DELAY_DAYS,
} = require('../validators/communityPublicationFields');
const { parseCommunityId } = require('../validators/communityFields');

const NOT_FOUND = 'Community publication not found';

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

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

async function withTransaction(db, fn) {
  const client = await db.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    committed = true;
    return result;
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // ignore
      }
    }
    throw err;
  } finally {
    client.release();
  }
}

async function loadMembership(client, communityId, userId) {
  const result = await client.query(
    `SELECT user_id, role
     FROM community_members
     WHERE community_id = $1
       AND user_id = $2
     LIMIT 1`,
    [communityId, userId]
  );
  return result.rows[0] || null;
}

async function requireActiveMembership(client, communityId, userId) {
  const membership = await loadMembership(client, communityId, userId);
  if (!membership) {
    throw new AppError(404, 'Community not found');
  }
  return membership;
}

async function loadAuthorLogin(client, userId) {
  const result = await client.query(
    `SELECT id, login FROM users WHERE id = $1 LIMIT 1`,
    [userId]
  );
  return result.rows[0] || { id: userId, login: 'unknown' };
}

function toPublicPublication(row, { isFormerMember, media = [], likedByMe = false } = {}) {
  return {
    id: formatId(row.id),
    community_id: formatId(row.community_id),
    community_name: row.community_name == null ? undefined : row.community_name,
    author: {
      user_id: formatId(row.author_user_id),
      login: row.author_login || 'unknown',
      is_former_member: Boolean(isFormerMember),
    },
    title: row.title == null ? null : row.title,
    body: row.body,
    status: row.status,
    scheduled_at: toIso(row.scheduled_at),
    published_at: toIso(row.published_at),
    expired_at: toIso(row.expired_at),
    purge_after: toIso(row.purge_after),
    deleted_at: toIso(row.deleted_at),
    is_time_limited: Boolean(row.is_time_limited),
    expires_at: toIso(row.expires_at),
    comments_enabled: Boolean(row.comments_enabled),
    deleted_by_user_id: row.deleted_by_user_id == null ? null : formatId(row.deleted_by_user_id),
    media_total_bytes: Number(row.media_total_bytes) || 0,
    like_count: Number(row.like_count) || 0,
    comment_count: Number(row.comment_count) || 0,
    liked_by_me: Boolean(likedByMe),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    media,
  };
}

function toPublicMedia(row) {
  return {
    id: formatId(row.id),
    kind: row.kind,
    source_type: row.source_type,
    content_type: row.content_type,
    byte_size: Number(row.byte_size),
    original_filename: row.original_filename == null ? null : row.original_filename,
    sort_order: Number(row.sort_order) || 0,
    status: row.status,
    created_at: toIso(row.created_at),
  };
}

async function toPublicMediaForGet(row, storage) {
  const media = toPublicMedia(row);
  if (row.status !== 'ready' || storage == null) {
    return media;
  }
  const storageKey = row.storage_key;
  if (typeof storageKey !== 'string' || storageKey.trim() === '') {
    return media;
  }
  const signed = await storage.createReadUrl(storageKey);
  if (signed && typeof signed.url === 'string' && signed.url.trim() !== '') {
    media.read_url = signed.url;
    if (signed.expires_at != null) {
      media.read_expires_at = toIso(signed.expires_at);
    }
  }
  await attachSignedThumbnail(media, row, storage);
  return media;
}

function logThumbnailReadFailure(row, err) {
  const statusCode = err && typeof err.statusCode === 'number' ? err.statusCode : null;
  const message = err && typeof err.message === 'string' ? err.message : 'thumbnail url failed';
  console.error(
    '[community-media-thumbnail] signature failed',
    `publication_id=${row && row.community_publication_id} media_id=${row && row.id}` +
      (statusCode != null ? ` status=${statusCode}` : '') +
      ` message=${message}`
  );
}

async function attachSignedThumbnail(media, row, storage) {
  if (media == null || row.kind !== 'video' || storage == null) {
    return;
  }
  const thumbKey = thumbnailStorageKey(row.storage_key);
  if (!thumbKey) {
    return;
  }
  try {
    const found = await storage.head(thumbKey);
    if (!found) {
      return;
    }
    const signed = await storage.createReadUrl(thumbKey);
    if (signed && typeof signed.url === 'string' && signed.url.trim() !== '') {
      media.thumbnail_url = signed.url;
      if (signed.expires_at != null) {
        media.thumbnail_expires_at = toIso(signed.expires_at);
      }
    }
  } catch (err) {
    logThumbnailReadFailure(row, err);
  }
}

async function toPublicMediaList(rows, deps = {}, { readyOnly = false } = {}) {
  const selected = readyOnly ? rows.filter((item) => item.status === 'ready') : rows;
  if (selected.length === 0) {
    return [];
  }
  const needsSign = selected.some((item) => item.status === 'ready');
  const storage = needsSign ? getStorage(deps.storage) : null;
  const media = [];
  for (const row of selected) {
    media.push(await toPublicMediaForGet(row, storage));
  }
  return media;
}

async function attachAuthorAndFormer(client, row) {
  const user = await loadAuthorLogin(client, row.author_user_id);
  const membership = await loadMembership(client, row.community_id, row.author_user_id);
  return {
    ...row,
    author_login: user.login,
    isFormerMember: !membership,
  };
}

async function loadMediaRows(client, publicationId) {
  const result = await client.query(
    `SELECT *
     FROM community_publication_media
     WHERE community_publication_id = $1
     ORDER BY sort_order ASC, id ASC`,
    [publicationId]
  );
  return result.rows;
}

async function publicationLikedByMe(client, publicationId, userId) {
  const found = await client.query(
    `SELECT 1
     FROM community_publication_likes
     WHERE community_publication_id = $1
       AND user_id = $2
     LIMIT 1`,
    [publicationId, userId]
  );
  return found.rowCount === 1;
}

async function createPublication(userId, rawCommunityId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const input = parseCreateInput(body);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    let status = STATUS.DRAFT;
    let publishedAt = null;
    let scheduledAt = null;
    if (input.publish === 'now') {
      status = STATUS.ACTIVE;
      publishedAt = deps.now || new Date();
    } else if (input.publish === 'schedule') {
      status = STATUS.SCHEDULED;
      scheduledAt = input.scheduledAt;
    }

    const inserted = await client.query(
      `INSERT INTO community_publications (
         community_id,
         author_user_id,
         title,
         body,
         status,
         scheduled_at,
         published_at,
         is_time_limited,
         expires_at,
         comments_enabled,
         media_total_bytes,
         initial_media_count,
         initial_media_open
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 0, $11, $12)
       RETURNING *`,
      [
        communityId,
        userId,
        input.title,
        input.body,
        status,
        scheduledAt,
        publishedAt,
        input.isTimeLimited,
        input.expiresAt,
        input.commentsEnabled,
        input.initialMediaCount,
        input.initialMediaCount > 0,
      ]
    );
    const enriched = await attachAuthorAndFormer(client, inserted.rows[0]);
    return toPublicPublication(enriched, { isFormerMember: enriched.isFormerMember });
  });
}

async function listFeed(userId, rawCommunityId, query, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const { limit, beforeAt, beforeId } = parseFeedQuery(query);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const params = [communityId];
    let cursorSql = '';
    if (beforeAt && beforeId) {
      params.push(beforeAt, beforeId);
      cursorSql = `AND (published_at, id) < ($2::timestamptz, $3::bigint)`;
    }
    params.push(limit + 1);
    const limitPlaceholder = `$${params.length}`;
    const result = await client.query(
      `SELECT p.*, u.login AS author_login,
              (m.user_id IS NULL) AS is_former_member
       FROM community_publications p
       INNER JOIN users u ON u.id = p.author_user_id
       LEFT JOIN community_members m
         ON m.community_id = p.community_id
        AND m.user_id = p.author_user_id
       WHERE p.community_id = $1
         AND p.status = 'active'
         ${cursorSql}
       ORDER BY p.published_at DESC, p.id DESC
       LIMIT ${limitPlaceholder}`,
      params
    );
    const hasMore = result.rows.length > limit;
    const page = hasMore ? result.rows.slice(0, limit) : result.rows;
    const last = page[page.length - 1];
    const items = [];
    for (const row of page) {
      const mediaRows = await loadMediaRows(client, row.id);
      const liked = await publicationLikedByMe(client, row.id, userId);
      items.push(
        toPublicPublication(row, {
          isFormerMember: row.is_former_member,
          media: await toPublicMediaList(mediaRows, deps, { readyOnly: true }),
          likedByMe: liked,
        })
      );
    }
    return {
      items,
      next:
        hasMore && last
          ? { before_at: toIso(last.published_at), before_id: formatId(last.id) }
          : null,
    };
  });
}

function canMemberRead(row, userId, membership) {
  if (!membership) {
    return false;
  }
  if (row.status === STATUS.DELETED || row.status === STATUS.EXPIRED) {
    return false;
  }
  if (row.status === STATUS.ACTIVE) {
    return true;
  }
  if (Number(row.author_user_id) === Number(userId) && (row.status === STATUS.DRAFT || row.status === STATUS.SCHEDULED)) {
    return true;
  }
  return false;
}

async function getPublication(userId, rawCommunityId, rawId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const id = parseId(rawId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const membership = await requireActiveMembership(client, communityId, userId);
    const found = await client.query(
      `SELECT * FROM community_publications
       WHERE id = $1 AND community_id = $2
       LIMIT 1`,
      [id, communityId]
    );
    const row = found.rows[0];
    if (!row || !canMemberRead(row, userId, membership)) {
      throw new AppError(404, NOT_FOUND);
    }
    const enriched = await attachAuthorAndFormer(client, row);
    const mediaRows = await loadMediaRows(client, row.id);
    const liked = await publicationLikedByMe(client, row.id, userId);
    return toPublicPublication(enriched, {
      isFormerMember: enriched.isFormerMember,
      media: await toPublicMediaList(mediaRows, deps),
      likedByMe: liked,
    });
  });
}

async function patchPublication(userId, rawCommunityId, rawId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const id = parseId(rawId, 'id is invalid');
  const input = parsePatchInput(body);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const found = await client.query(
      `SELECT * FROM community_publications
       WHERE id = $1 AND community_id = $2
       FOR UPDATE`,
      [id, communityId]
    );
    const row = found.rows[0];
    if (!row || row.status === STATUS.DELETED || row.status === STATUS.EXPIRED) {
      throw new AppError(404, NOT_FOUND);
    }
    if (Number(row.author_user_id) !== Number(userId)) {
      throw new AppError(403, 'Forbidden');
    }
    const nextTitle = Object.prototype.hasOwnProperty.call(input, 'title') ? input.title : row.title;
    const nextBody = Object.prototype.hasOwnProperty.call(input, 'body') ? input.body : row.body;
    const saved = await client.query(
      `UPDATE community_publications
       SET title = $1,
           body = $2,
           updated_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [nextTitle, nextBody, id]
    );
    const enriched = await attachAuthorAndFormer(client, saved.rows[0]);
    const mediaRows = await loadMediaRows(client, id);
    return toPublicPublication(enriched, {
      isFormerMember: enriched.isFormerMember,
      media: mediaRows.map(toPublicMedia),
    });
  });
}

function assertCanDelete(row, userId, membership) {
  const isAuthor = Number(row.author_user_id) === Number(userId);
  const isMod = membership.role === 'owner' || membership.role === 'admin';
  if (row.status === STATUS.EXPIRED || row.status === STATUS.DELETED || row.status === STATUS.DRAFT) {
    throw new AppError(400, 'publication cannot be deleted in this status');
  }
  if (row.status === STATUS.SCHEDULED) {
    if (!isAuthor) {
      throw new AppError(403, 'Forbidden');
    }
    return;
  }
  if (row.status === STATUS.ACTIVE) {
    if (isAuthor || isMod) {
      return;
    }
    throw new AppError(403, 'Forbidden');
  }
  throw new AppError(403, 'Forbidden');
}

async function deletePublication(userId, rawCommunityId, rawId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const id = parseId(rawId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const membership = await requireActiveMembership(client, communityId, userId);
    const found = await client.query(
      `SELECT * FROM community_publications
       WHERE id = $1 AND community_id = $2
       FOR UPDATE`,
      [id, communityId]
    );
    const row = found.rows[0];
    if (!row) {
      throw new AppError(404, NOT_FOUND);
    }
    assertCanDelete(row, userId, membership);
    const { deleteInteractionsForPublication } = require('./communityPublicationLikeService');
    await deleteInteractionsForPublication(client, id);
    const now = deps.now || new Date();
    await client.query(
      `UPDATE community_publications
       SET status = $1,
           deleted_at = $2,
           deleted_by_user_id = $3,
           updated_at = $2
       WHERE id = $4`,
      [STATUS.DELETED, now, userId, id]
    );
    return { deleted: true };
  });
}

function restoreStatus(row, now) {
  if (row.published_at) {
    return STATUS.ACTIVE;
  }
  if (row.scheduled_at) {
    const scheduledAt = new Date(row.scheduled_at);
    if (scheduledAt.getTime() > now.getTime()) {
      return STATUS.SCHEDULED;
    }
    return STATUS.ACTIVE;
  }
  return STATUS.ACTIVE;
}

async function restorePublication(userId, rawCommunityId, rawId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const id = parseId(rawId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;
  const now = deps.now || new Date();

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const found = await client.query(
      `SELECT * FROM community_publications
       WHERE id = $1 AND community_id = $2
       FOR UPDATE`,
      [id, communityId]
    );
    const row = found.rows[0];
    if (!row || row.status !== STATUS.DELETED) {
      throw new AppError(404, NOT_FOUND);
    }
    if (
      Number(row.author_user_id) !== Number(userId) ||
      Number(row.deleted_by_user_id) !== Number(userId)
    ) {
      throw new AppError(403, 'Forbidden');
    }
    const nextStatus = restoreStatus(row, now);
    let publishedAt = row.published_at;
    if (nextStatus === STATUS.ACTIVE && !publishedAt) {
      publishedAt = now;
    }
    const saved = await client.query(
      `UPDATE community_publications
       SET status = $1,
           published_at = $2,
           deleted_at = NULL,
           deleted_by_user_id = NULL,
           updated_at = $3
       WHERE id = $4
       RETURNING *`,
      [nextStatus, publishedAt, now, id]
    );
    const enriched = await attachAuthorAndFormer(client, saved.rows[0]);
    return toPublicPublication(enriched, { isFormerMember: enriched.isFormerMember });
  });
}

async function listMine(userId, query, deps = {}) {
  const { scope, limit, beforeAt, beforeId } = parseMeQuery(query);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const params = [userId];
    let scopeSql = '';
    if (scope === 'expired') {
      scopeSql = `AND p.status = 'expired'`;
    } else if (scope === 'current') {
      scopeSql = `AND p.status IN ('scheduled', 'active')
         AND EXISTS (
           SELECT 1 FROM community_members m
           WHERE m.community_id = p.community_id AND m.user_id = $1
         )`;
    } else {
      scopeSql = `AND p.status IN ('scheduled', 'active')
         AND NOT EXISTS (
           SELECT 1 FROM community_members m
           WHERE m.community_id = p.community_id AND m.user_id = $1
         )`;
    }
    let cursorSql = '';
    if (beforeAt && beforeId) {
      params.push(beforeAt, beforeId);
      cursorSql = `AND (COALESCE(p.published_at, p.created_at), p.id) < ($2::timestamptz, $3::bigint)`;
    }
    params.push(limit + 1);
    const limitPlaceholder = `$${params.length}`;
    const result = await client.query(
      `SELECT p.*, u.login AS author_login, c.name AS community_name,
              (m.user_id IS NULL) AS is_former_member
       FROM community_publications p
       INNER JOIN users u ON u.id = p.author_user_id
       INNER JOIN communities c ON c.id = p.community_id
       LEFT JOIN community_members m
         ON m.community_id = p.community_id
        AND m.user_id = p.author_user_id
       WHERE p.author_user_id = $1
         AND p.status <> 'draft'
         AND p.status <> 'deleted'
         ${scopeSql}
         ${cursorSql}
       ORDER BY COALESCE(p.published_at, p.created_at) DESC, p.id DESC
       LIMIT ${limitPlaceholder}`,
      params
    );
    const hasMore = result.rows.length > limit;
    const page = hasMore ? result.rows.slice(0, limit) : result.rows;
    const last = page[page.length - 1];
    const items = [];
    for (const row of page) {
      const mediaRows = await loadMediaRows(client, row.id);
      const liked = await publicationLikedByMe(client, row.id, userId);
      items.push(
        toPublicPublication(row, {
          isFormerMember: row.is_former_member,
          media: await toPublicMediaList(mediaRows, deps, { readyOnly: true }),
          likedByMe: liked,
        })
      );
    }
    return {
      items,
      next:
        hasMore && last
          ? {
              before_at: toIso(last.published_at || last.created_at),
              before_id: formatId(last.id),
            }
          : null,
    };
  });
}

async function getMine(userId, rawId, deps = {}) {
  const id = parseId(rawId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const found = await client.query(
      `SELECT p.*, c.name AS community_name
       FROM community_publications p
       INNER JOIN communities c ON c.id = p.community_id
       WHERE p.id = $1 AND p.author_user_id = $2
       LIMIT 1`,
      [id, userId]
    );
    const row = found.rows[0];
    if (!row || row.status === STATUS.DRAFT || row.status === STATUS.DELETED) {
      throw new AppError(404, NOT_FOUND);
    }
    const enriched = await attachAuthorAndFormer(client, row);
    const mediaRows = await loadMediaRows(client, row.id);
    const liked = await publicationLikedByMe(client, row.id, userId);
    return toPublicPublication(
      { ...enriched, community_name: row.community_name },
      {
        isFormerMember: enriched.isFormerMember,
        media: await toPublicMediaList(mediaRows, deps, { readyOnly: true }),
        likedByMe: liked,
      }
    );
  });
}

module.exports = {
  NOT_FOUND,
  createPublication,
  listFeed,
  getPublication,
  patchPublication,
  deletePublication,
  restorePublication,
  listMine,
  getMine,
  toPublicPublication,
  toPublicMedia,
  loadMembership,
  loadMediaRows,
  withTransaction,
  requireActiveMembership,
};
