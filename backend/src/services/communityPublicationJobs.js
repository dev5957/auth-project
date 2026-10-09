const pool = require('../db');
const AppError = require('../errors/AppError');
const { getStorage } = require('./storageService');
const { STATUS, PURGE_DELAY_DAYS } = require('../validators/communityPublicationFields');
const { collectStorageKeys } = require('./communityPublicationMediaService');
const { withTransaction } = require('./communityPublicationService');

const DEFAULT_LIMIT = 100;

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function asDate(value) {
  if (value == null) {
    return null;
  }
  if (value instanceof Date) {
    return value;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function getQuery(deps) {
  if (deps.query) {
    return deps.query;
  }
  const db = deps.db || pool;
  return (sql, params) => db.query(sql, params);
}

async function deleteStorageKeys(storage, keys) {
  const unique = [];
  for (const key of keys) {
    if (typeof key === 'string' && key && !unique.includes(key)) {
      unique.push(key);
    }
  }
  for (const key of unique) {
    try {
      await storage.delete(key);
    } catch (_) {
      // continue
    }
  }
}

async function runPublishScheduledJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const limit = deps.limit || DEFAULT_LIMIT;
  const query = getQuery(deps);
  const due = await query(
    `SELECT *
     FROM community_publications
     WHERE status = 'scheduled'
       AND scheduled_at <= $1
     ORDER BY scheduled_at ASC, id ASC
     LIMIT $2`,
    [now, limit]
  );
  const updated = [];
  for (const row of due.rows) {
    const saved = await query(
      `UPDATE community_publications
       SET status = 'active',
           published_at = COALESCE(published_at, $1),
           updated_at = $1
       WHERE id = $2
         AND status = 'scheduled'
       RETURNING *`,
      [now, row.id]
    );
    if (saved.rows[0]) {
      updated.push(saved.rows[0]);
    }
  }
  return updated;
}

async function expireLockedPublication(client, row, now, snapshotVisibleCommentTraces) {
  const locked = await client.query(
    `SELECT *
     FROM community_publications
     WHERE id = $1
     FOR UPDATE`,
    [row.id]
  );
  const current = locked.rows[0];
  if (!current || current.status !== STATUS.ACTIVE || !current.is_time_limited) {
    return null;
  }
  const expiresAt = asDate(current.expires_at);
  if (!expiresAt || expiresAt.getTime() > now.getTime()) {
    return null;
  }
  const expiredAt = asDate(current.expired_at) || now;
  const purgeAfter = asDate(current.purge_after) || addDays(expiredAt, PURGE_DELAY_DAYS);
  const saved = await client.query(
    `UPDATE community_publications
     SET status = 'expired',
         expired_at = $1,
         purge_after = $2,
         updated_at = $3
     WHERE id = $4
       AND status = 'active'
     RETURNING *`,
    [expiredAt, purgeAfter, now, current.id]
  );
  if (!saved.rows[0]) {
    return null;
  }
  await snapshotVisibleCommentTraces((sql, params) => client.query(sql, params), saved.rows[0]);
  return saved.rows[0];
}

async function runExpireActiveJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const limit = deps.limit || DEFAULT_LIMIT;
  const query = getQuery(deps);
  const db = deps.db || pool;
  const due = await query(
    `SELECT *
     FROM community_publications
     WHERE status = 'active'
       AND is_time_limited = TRUE
       AND expires_at <= $1
     ORDER BY expires_at ASC, id ASC
     LIMIT $2`,
    [now, limit]
  );
  const { snapshotVisibleCommentTraces } = require('./communityPublicationCommentService');
  const updated = [];
  for (const row of due.rows) {
    const saved = await withTransaction(db, async (client) =>
      expireLockedPublication(client, row, now, snapshotVisibleCommentTraces)
    );
    if (saved) {
      updated.push(saved);
    }
  }
  return updated;
}

async function runPurgeExpiredJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const limit = deps.limit || DEFAULT_LIMIT;
  const query = getQuery(deps);
  const storage = getStorage(deps.storage);
  const due = await query(
    `SELECT *
     FROM community_publications
     WHERE status = 'expired'
       AND purge_after <= $1
     ORDER BY purge_after ASC, id ASC
     LIMIT $2`,
    [now, limit]
  );
  const deleted = [];
  for (const row of due.rows) {
    const media = await query(
      `SELECT * FROM community_publication_media WHERE community_publication_id = $1`,
      [row.id]
    );
    const keys = [];
    for (const item of media.rows) {
      keys.push(...collectStorageKeys(item));
    }
    await deleteStorageKeys(storage, keys);
    await query(`DELETE FROM community_publication_media WHERE community_publication_id = $1`, [row.id]);
    const removed = await query(
      `DELETE FROM community_publications
       WHERE id = $1 AND status = 'expired'
       RETURNING *`,
      [row.id]
    );
    if (removed.rows[0]) {
      deleted.push(removed.rows[0]);
    }
  }
  return deleted;
}

async function runPendingUploadCleanupJob(deps = {}) {
  requireDatabase();
  const query = getQuery(deps);
  const storage = getStorage(deps.storage);
  const stale = await query(
    `SELECT m.*
     FROM community_publication_media m
     INNER JOIN community_publications p ON p.id = m.community_publication_id
     WHERE m.status = 'pending_upload'
       AND NOT EXISTS (
         SELECT 1 FROM community_members cm
         WHERE cm.community_id = p.community_id
           AND cm.user_id = p.author_user_id
       )`
  );
  const cleaned = [];
  for (const media of stale.rows) {
    await deleteStorageKeys(storage, collectStorageKeys(media));
    await query(`DELETE FROM community_publication_media WHERE id = $1`, [media.id]);
    cleaned.push(media);
  }
  return cleaned;
}

async function runCommunityPublicationJobs(deps = {}) {
  const published = await runPublishScheduledJob(deps);
  const expired = await runExpireActiveJob(deps);
  const purged = await runPurgeExpiredJob(deps);
  return {
    published: published.length,
    expired: expired.length,
    deleted: purged.length,
  };
}

module.exports = {
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
  runPendingUploadCleanupJob,
  runCommunityPublicationJobs,
};
