const pool = require('../db');
const AppError = require('../errors/AppError');
const { toPublicChronique } = require('./chroniqueService');
const { getStorage } = require('./storageService');
const { thumbnailStorageKey } = require('./mediaStorageKeys');
const { CHRONIQUE_STATUS, PURGE_DELAY_DAYS } = require('../validators/chroniqueFields');

const DEFAULT_LIMIT = 100;
/** Pages de `limit` par lancement ; le curseur avance aussi après un échec R2. */
const DEFAULT_PURGE_PAGES = 10;

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

function applyScheduledActivation(row, now) {
  if (!row || row.status !== CHRONIQUE_STATUS.SCHEDULED) {
    return null;
  }
  const scheduledAt = asDate(row.scheduled_at);
  if (scheduledAt == null || scheduledAt.getTime() > now.getTime()) {
    return null;
  }
  return {
    ...row,
    status: CHRONIQUE_STATUS.ACTIVE,
    published_at: asDate(row.published_at) || now,
    scheduled_at: row.scheduled_at,
  };
}

function applyExpiration(row, now) {
  if (!row || row.status !== CHRONIQUE_STATUS.ACTIVE || row.is_time_limited !== true) {
    return null;
  }
  const expiresAt = asDate(row.expires_at);
  if (expiresAt == null || expiresAt.getTime() > now.getTime()) {
    return null;
  }
  const expiredAt = asDate(row.expired_at) || now;
  const purgeAfter = asDate(row.purge_after) || addDays(expiredAt, PURGE_DELAY_DAYS);
  return {
    ...row,
    status: CHRONIQUE_STATUS.EXPIRED,
    expired_at: expiredAt,
    purge_after: purgeAfter,
  };
}

function applyLogicalPurge(row, now) {
  if (!row || row.status !== CHRONIQUE_STATUS.EXPIRED) {
    return null;
  }
  const purgeAfter =
    asDate(row.purge_after) ||
    (asDate(row.expired_at) ? addDays(asDate(row.expired_at), PURGE_DELAY_DAYS) : null);
  if (purgeAfter == null || purgeAfter.getTime() > now.getTime()) {
    return null;
  }
  return {
    ...row,
    status: CHRONIQUE_STATUS.DELETED,
    deleted_at: asDate(row.deleted_at) || now,
  };
}

function getQuery(deps) {
  if (deps.query) {
    return deps.query;
  }
  const db = deps.db || pool;
  return (sql, params) => db.query(sql, params);
}

function collectMediaStorageKeys(mediaRow) {
  const keys = [];
  if (mediaRow == null) {
    return keys;
  }
  const storageKey = typeof mediaRow.storage_key === 'string' ? mediaRow.storage_key.trim() : '';
  if (storageKey) {
    keys.push(storageKey);
  }
  if (mediaRow.kind === 'video') {
    const thumbKey = thumbnailStorageKey(storageKey);
    if (thumbKey && !keys.includes(thumbKey)) {
      keys.push(thumbKey);
    }
  }
  return keys;
}

function logHardPurgeFailure(row, err) {
  const message = err && typeof err.message === 'string' ? err.message : 'hard purge failed';
  console.error('[chronique-job] hard purge failed', `publication_id=${row && row.id} message=${message}`);
}

async function deleteStorageKeys(storage, keys) {
  const unique = [];
  for (const key of keys) {
    if (typeof key === 'string' && key && !unique.includes(key)) {
      unique.push(key);
    }
  }
  for (const key of unique) {
    await storage.delete(key);
  }
  return unique;
}

async function withDbClient(deps, fn) {
  const db = deps.db || pool;
  if (db && typeof db.connect === 'function') {
    const client = await db.connect();
    try {
      return await fn(client);
    } finally {
      if (client && typeof client.release === 'function') {
        client.release();
      }
    }
  }
  return fn({ query: getQuery(deps) });
}

async function hardPurgeExpiredPublication(row, deps) {
  const query = getQuery(deps);
  const mediaResult = await query(
    `SELECT id, kind, storage_key
     FROM publication_media
     WHERE publication_id = $1
     ORDER BY id ASC`,
    [row.id]
  );
  const keys = [];
  for (const media of mediaResult.rows || []) {
    keys.push(...collectMediaStorageKeys(media));
  }
  if (keys.length > 0) {
    await deleteStorageKeys(getStorage(deps.storage), keys);
  }

  return withDbClient(deps, async (client) => {
    await client.query('BEGIN');
    try {
      await client.query(`DELETE FROM publication_media WHERE publication_id = $1`, [row.id]);
      const deleted = await client.query(
        `DELETE FROM publications
         WHERE id = $1
           AND status = '${CHRONIQUE_STATUS.EXPIRED}'
         RETURNING *`,
        [row.id]
      );
      if (!deleted.rows[0]) {
        throw new Error('expired publication was not deleted');
      }
      await client.query('COMMIT');
      return deleted.rows[0];
    } catch (err) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackErr) {
        // keep original error
      }
      throw err;
    }
  });
}

function formatChroniqueJobLogs(
  { published = 0, expired = 0, deleted = 0 } = {},
  jobName = 'all'
) {
  const parts = ['[chronique-job]'];
  const includePublish = jobName === 'all' || jobName === 'publish';
  const includeExpire = jobName === 'all' || jobName === 'expire';
  const includePurge = jobName === 'all' || jobName === 'purge';

  if (includePublish) {
    parts.push('publish:', `${published} publications activated`);
  }
  if (includeExpire) {
    if (includePublish) {
      parts.push('');
    }
    parts.push('expire:', `${expired} publications expired`);
  }
  if (includePurge) {
    if (includePublish || includeExpire) {
      parts.push('');
    }
    parts.push('purge:', `${deleted} publications deleted`);
  }
  return parts.join('\n');
}

async function runPublishScheduledJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const limit = deps.limit || DEFAULT_LIMIT;
  const query = getQuery(deps);

  const due = await query(
    `SELECT *
     FROM publications
     WHERE status = '${CHRONIQUE_STATUS.SCHEDULED}'
       AND scheduled_at <= $1
     ORDER BY scheduled_at ASC, id ASC
     LIMIT $2`,
    [now, limit]
  );

  const updated = [];
  for (const row of due.rows) {
    const next = applyScheduledActivation(row, now);
    if (!next) {
      continue;
    }
    const saved = await query(
      `UPDATE publications
       SET status = $1,
           published_at = $2,
           updated_at = $3
       WHERE id = $4
         AND status = '${CHRONIQUE_STATUS.SCHEDULED}'
       RETURNING *`,
      [next.status, next.published_at, now, row.id]
    );
    if (saved.rows[0]) {
      updated.push(toPublicChronique(saved.rows[0]));
    }
  }
  return updated;
}

async function runExpireActiveJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const limit = deps.limit || DEFAULT_LIMIT;
  const query = getQuery(deps);

  const due = await query(
    `SELECT *
     FROM publications
     WHERE status = '${CHRONIQUE_STATUS.ACTIVE}'
       AND is_time_limited = TRUE
       AND expires_at <= $1
     ORDER BY expires_at ASC, id ASC
     LIMIT $2`,
    [now, limit]
  );

  const updated = [];
  for (const row of due.rows) {
    const next = applyExpiration(row, now);
    if (!next) {
      continue;
    }
    const saved = await query(
      `UPDATE publications
       SET status = $1,
           expired_at = $2,
           purge_after = $3,
           updated_at = $4
       WHERE id = $5
         AND status = '${CHRONIQUE_STATUS.ACTIVE}'
       RETURNING *`,
      [next.status, next.expired_at, next.purge_after, now, row.id]
    );
    if (saved.rows[0]) {
      updated.push(toPublicChronique(saved.rows[0]));
    }
  }
  return updated;
}

function purgeSortValue(row) {
  return asDate(row && row.purge_after) || asDate(row && row.expired_at);
}

async function runPurgeExpiredJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const pageSize = deps.limit || DEFAULT_LIMIT;
  const maxPages = deps.maxPages || DEFAULT_PURGE_PAGES;
  const query = getQuery(deps);

  const updated = [];
  let afterAt = null;
  let afterId = null;

  for (let page = 0; page < maxPages; page += 1) {
    const params = [now];
    let cursorSql = '';
    if (afterAt != null && afterId != null) {
      params.push(afterAt.toISOString(), afterId);
      cursorSql = `AND (COALESCE(purge_after, expired_at), id) > ($2::timestamptz, $3::bigint)`;
    }
    params.push(pageSize);
    const limitPlaceholder = `$${params.length}`;

    const due = await query(
      `SELECT *
       FROM publications
       WHERE status = '${CHRONIQUE_STATUS.EXPIRED}'
         AND (
           purge_after <= $1
           OR (
             purge_after IS NULL
             AND expired_at <= $1::timestamptz - INTERVAL '${PURGE_DELAY_DAYS} days'
           )
         )
         ${cursorSql}
       ORDER BY COALESCE(purge_after, expired_at) ASC, id ASC
       LIMIT ${limitPlaceholder}`,
      params
    );

    const rows = due.rows || [];
    if (rows.length === 0) {
      break;
    }

    for (const row of rows) {
      if (!applyLogicalPurge(row, now)) {
        continue;
      }
      try {
        const removed = await hardPurgeExpiredPublication(row, deps);
        updated.push(
          toPublicChronique({
            ...removed,
            status: CHRONIQUE_STATUS.DELETED,
            deleted_at: asDate(removed.deleted_at) || now,
          })
        );
      } catch (err) {
        logHardPurgeFailure(row, err);
      }
    }

    const last = rows[rows.length - 1];
    const sortAt = purgeSortValue(last);
    if (sortAt == null || last.id == null) {
      break;
    }
    afterAt = sortAt;
    afterId = last.id;
    if (rows.length < pageSize) {
      break;
    }
  }

  return updated;
}

async function runChroniqueLifecycleJobs(deps = {}) {
  const published = await runPublishScheduledJob(deps);
  const expired = await runExpireActiveJob(deps);
  const deleted = await runPurgeExpiredJob(deps);
  return {
    published: published.length,
    expired: expired.length,
    deleted: deleted.length,
  };
}

module.exports = {
  PURGE_DELAY_DAYS,
  DEFAULT_LIMIT,
  DEFAULT_PURGE_PAGES,
  applyScheduledActivation,
  applyExpiration,
  applyLogicalPurge,
  collectMediaStorageKeys,
  formatChroniqueJobLogs,
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
  runChroniqueLifecycleJobs,
};
