const pool = require('../db');
const AppError = require('../errors/AppError');
const { parseCommunityId } = require('../validators/communityFields');
const { parseId, STATUS } = require('../validators/communityPublicationFields');
const {
  withTransaction,
  requireActiveMembership,
  NOT_FOUND,
} = require('./communityPublicationService');

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

async function lockActivePublication(client, communityId, publicationId) {
  const found = await client.query(
    `SELECT *
     FROM community_publications
     WHERE id = $1 AND community_id = $2
     FOR UPDATE`,
    [publicationId, communityId]
  );
  const row = found.rows[0];
  if (!row || row.status !== STATUS.ACTIVE) {
    throw new AppError(404, NOT_FOUND);
  }
  return row;
}

function toLikeState(publication, liked) {
  return {
    liked: Boolean(liked),
    like_count: Number(publication.like_count) || 0,
    liked_by_me: Boolean(liked),
  };
}

async function likePublication(userId, rawCommunityId, rawPublicationId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const publication = await lockActivePublication(client, communityId, publicationId);
    await requireActiveMembership(client, communityId, userId);
    const inserted = await client.query(
      `INSERT INTO community_publication_likes (
         community_id,
         community_publication_id,
         user_id
       )
       VALUES ($1, $2, $3)
       ON CONFLICT (community_publication_id, user_id) DO NOTHING
       RETURNING id`,
      [communityId, publicationId, userId]
    );
    if (inserted.rowCount === 1) {
      const updated = await client.query(
        `UPDATE community_publications
         SET like_count = like_count + 1,
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [publicationId]
      );
      return toLikeState(updated.rows[0], true);
    }
    return toLikeState(publication, true);
  });
}

async function unlikePublication(userId, rawCommunityId, rawPublicationId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawPublicationId, 'id is invalid');
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireActiveMembership(client, communityId, userId);
    const publication = await lockActivePublication(client, communityId, publicationId);
    await requireActiveMembership(client, communityId, userId);
    const removed = await client.query(
      `DELETE FROM community_publication_likes
       WHERE community_publication_id = $1
         AND user_id = $2
       RETURNING id`,
      [publicationId, userId]
    );
    if (removed.rowCount === 1) {
      const updated = await client.query(
        `UPDATE community_publications
         SET like_count = GREATEST(like_count - 1, 0),
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [publicationId]
      );
      return toLikeState(updated.rows[0], false);
    }
    return toLikeState(publication, false);
  });
}

async function deleteLikesForMember(client, communityId, userId) {
  for (;;) {
    const found = await client.query(
      `SELECT DISTINCT community_publication_id
       FROM community_publication_likes
       WHERE community_id = $1
         AND user_id = $2
       ORDER BY community_publication_id ASC`,
      [communityId, userId]
    );
    if (found.rows.length === 0) {
      return;
    }
    const publicationIds = found.rows.map((row) => row.community_publication_id);
    await client.query(
      `SELECT id
       FROM community_publications
       WHERE id = ANY($1::bigint[])
       ORDER BY id ASC
       FOR UPDATE`,
      [publicationIds]
    );
    for (const publicationId of publicationIds) {
      const removed = await client.query(
        `DELETE FROM community_publication_likes
         WHERE community_publication_id = $1
           AND user_id = $2
         RETURNING id`,
        [publicationId, userId]
      );
      if (removed.rowCount > 0) {
        await client.query(
          `UPDATE community_publications
           SET like_count = GREATEST(like_count - $1, 0),
               updated_at = NOW()
           WHERE id = $2`,
          [removed.rowCount, publicationId]
        );
      }
    }
  }
}

async function deleteInteractionsForPublication(client, publicationId) {
  await client.query(
    `DELETE FROM community_publication_likes WHERE community_publication_id = $1`,
    [publicationId]
  );
  await client.query(
    `DELETE FROM community_publication_comments WHERE community_publication_id = $1`,
    [publicationId]
  );
  await client.query(
    `UPDATE community_publications
     SET like_count = 0,
         comment_count = 0,
         updated_at = NOW()
     WHERE id = $1`,
    [publicationId]
  );
}

async function likedByMe(client, publicationId, userId) {
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

module.exports = {
  likePublication,
  unlikePublication,
  deleteLikesForMember,
  deleteInteractionsForPublication,
  likedByMe,
  lockActivePublication,
};
