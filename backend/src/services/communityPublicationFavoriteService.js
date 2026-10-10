const pool = require('../db');
const AppError = require('../errors/AppError');
const { parseCommunityId } = require('../validators/communityFields');
const { parseId, parseFeedQuery, STATUS } = require('../validators/communityPublicationFields');
const {
  withTransaction,
  requireActiveMembership,
  NOT_FOUND,
  toPublicPublication,
  loadMediaRows,
  toPublicMediaList,
} = require('./communityPublicationService');
const { lockActivePublication } = require('./communityPublicationLikeService');

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function toFavoriteState(favoriteCount, favorited) {
  return {
    favorited: Boolean(favorited),
    favorite_count: Number(favoriteCount) || 0,
    favorited_by_me: Boolean(favorited),
  };
}

async function countFavorites(client, publicationId) {
  const result = await client.query(
    `SELECT COUNT(*)::int AS favorite_count
     FROM community_publication_favorites
     WHERE community_publication_id = $1`,
    [publicationId]
  );
  return Number(result.rows[0] && result.rows[0].favorite_count) || 0;
}

async function loadFavoriteStats(client, publicationIds, userId) {
  const ids = [...new Set((publicationIds || []).map((value) => Number(value)).filter((value) => Number.isFinite(value)))];
  const stats = new Map();
  if (ids.length === 0) {
    return stats;
  }
  const result = await client.query(
    `SELECT community_publication_id,
            COUNT(*)::int AS favorite_count,
            BOOL_OR(user_id = $2) AS favorited_by_me
     FROM community_publication_favorites
     WHERE community_publication_id = ANY($1::bigint[])
     GROUP BY community_publication_id`,
    [ids, userId]
  );
  for (const row of result.rows) {
    stats.set(Number(row.community_publication_id), {
      favoriteCount: Number(row.favorite_count) || 0,
      favoritedByMe: Boolean(row.favorited_by_me),
    });
  }
  return stats;
}

function assertNotOwnPublication(row, userId) {
  if (Number(row.author_user_id) === Number(userId)) {
    throw new AppError(403, 'Forbidden');
  }
}

async function favoritePublication(userId, rawCommunityId, rawPublicationId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const publication = await lockActivePublication(client, communityId, publicationId);
    await requireActiveMembership(client, communityId, userId);
    assertNotOwnPublication(publication, userId);
    await client.query(
      `INSERT INTO community_publication_favorites (
         community_id,
         community_publication_id,
         user_id
       )
       VALUES ($1, $2, $3)
       ON CONFLICT (community_publication_id, user_id) DO NOTHING`,
      [communityId, publicationId, userId]
    );
    const favoriteCount = await countFavorites(client, publicationId);
    return toFavoriteState(favoriteCount, true);
  });
}

async function unfavoritePublication(userId, rawCommunityId, rawPublicationId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const publication = await lockActivePublication(client, communityId, publicationId);
    await requireActiveMembership(client, communityId, userId);
    assertNotOwnPublication(publication, userId);
    await client.query(
      `DELETE FROM community_publication_favorites
       WHERE community_publication_id = $1
         AND user_id = $2`,
      [publicationId, userId]
    );
    const favoriteCount = await countFavorites(client, publicationId);
    return toFavoriteState(favoriteCount, false);
  });
}

async function deleteFavoritesForMember(client, communityId, userId) {
  await client.query(
    `DELETE FROM community_publication_favorites
     WHERE community_id = $1
       AND user_id = $2`,
    [communityId, userId]
  );
}

async function deleteFavoritesForPublication(client, publicationId) {
  await client.query(
    `DELETE FROM community_publication_favorites
     WHERE community_publication_id = $1`,
    [publicationId]
  );
}

async function listMyFavorites(userId, query, deps = {}) {
  const { limit, beforeAt, beforeId } = parseFeedQuery(query);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const params = [userId];
    let cursorSql = '';
    if (beforeAt && beforeId) {
      params.push(beforeAt, beforeId);
      cursorSql = `AND (fav.favorited_at, fav.id) < ($2::timestamptz, $3::bigint)`;
    }
    params.push(limit + 1);
    const limitPlaceholder = `$${params.length}`;
    const result = await client.query(
      `SELECT pub.*, u.login AS author_login, c.name AS community_name,
              (m.user_id IS NULL) AS is_former_member,
              fav.id AS favorite_id,
              fav.favorited_at
       FROM community_publication_favorites fav
       INNER JOIN community_publications pub ON pub.id = fav.community_publication_id
       INNER JOIN users u ON u.id = pub.author_user_id
       INNER JOIN communities c ON c.id = pub.community_id
       LEFT JOIN community_members m
         ON m.community_id = pub.community_id
        AND m.user_id = pub.author_user_id
       WHERE fav.user_id = $1
         AND pub.status = '${STATUS.ACTIVE}'
         AND pub.author_user_id <> $1
         AND EXISTS (
           SELECT 1 FROM community_members cm
           WHERE cm.community_id = pub.community_id
             AND cm.user_id = $1
         )
         ${cursorSql}
       ORDER BY fav.favorited_at DESC, fav.id DESC
       LIMIT ${limitPlaceholder}`,
      params
    );
    const hasMore = result.rows.length > limit;
    const page = hasMore ? result.rows.slice(0, limit) : result.rows;
    const last = page[page.length - 1];
    const stats = await loadFavoriteStats(
      client,
      page.map((row) => row.id),
      userId
    );
    const items = [];
    for (const row of page) {
      const mediaRows = await loadMediaRows(client, row.id);
      const favorite = stats.get(Number(row.id)) || { favoriteCount: 0, favoritedByMe: true };
      const liked = await client.query(
        `SELECT 1
         FROM community_publication_likes
         WHERE community_publication_id = $1
           AND user_id = $2
         LIMIT 1`,
        [row.id, userId]
      );
      items.push(
        toPublicPublication(row, {
          isFormerMember: row.is_former_member,
          media: await toPublicMediaList(mediaRows, deps, { readyOnly: true }),
          likedByMe: liked.rowCount === 1,
          favoriteCount: favorite.favoriteCount,
          favoritedByMe: true,
        })
      );
    }
    return {
      items,
      next:
        hasMore && last
          ? { before_at: last.favorited_at instanceof Date ? last.favorited_at.toISOString() : last.favorited_at, before_id: Number(last.favorite_id) }
          : null,
    };
  });
}

module.exports = {
  favoritePublication,
  unfavoritePublication,
  listMyFavorites,
  deleteFavoritesForMember,
  deleteFavoritesForPublication,
  loadFavoriteStats,
  countFavorites,
};
