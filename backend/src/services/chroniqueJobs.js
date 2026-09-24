const pool = require('../db');
const AppError = require('../errors/AppError');
const { toPublicChronique } = require('./chroniqueService');
const { CHRONIQUE_STATUS } = require('../validators/chroniqueFields');

const PURGE_DELAY_DAYS = 30;
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

async function runPurgeExpiredJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const limit = deps.limit || DEFAULT_LIMIT;
  const query = getQuery(deps);

  const due = await query(
    `SELECT *
     FROM publications
     WHERE status = '${CHRONIQUE_STATUS.EXPIRED}'
       AND (
         purge_after <= $1
         OR (purge_after IS NULL AND expired_at <= $1::timestamptz - INTERVAL '30 days')
       )
     ORDER BY COALESCE(purge_after, expired_at) ASC, id ASC
     LIMIT $2`,
    [now, limit]
  );

  const updated = [];
  for (const row of due.rows) {
    const next = applyLogicalPurge(row, now);
    if (!next) {
      continue;
    }
    const saved = await query(
      `UPDATE publications
       SET status = $1,
           deleted_at = $2,
           updated_at = $3
       WHERE id = $4
         AND status = '${CHRONIQUE_STATUS.EXPIRED}'
       RETURNING *`,
      [next.status, next.deleted_at, now, row.id]
    );
    if (saved.rows[0]) {
      updated.push(toPublicChronique(saved.rows[0]));
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
  applyScheduledActivation,
  applyExpiration,
  applyLogicalPurge,
  formatChroniqueJobLogs,
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
  runChroniqueLifecycleJobs,
};
