const pool = require('../db');
const AppError = require('../errors/AppError');
const { toPublicChronique } = require('./chroniqueService');

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
  if (!row || row.status !== 'scheduled') {
    return null;
  }
  const scheduledAt = asDate(row.scheduled_at);
  if (scheduledAt == null || scheduledAt.getTime() > now.getTime()) {
    return null;
  }
  return {
    ...row,
    status: 'active',
    published_at: asDate(row.published_at) || now,
    scheduled_at: row.scheduled_at,
  };
}

function applyExpiration(row, now) {
  if (!row || row.status !== 'active' || row.is_time_limited !== true) {
    return null;
  }
  const expiresAt = asDate(row.expires_at);
  if (expiresAt == null || expiresAt.getTime() > now.getTime()) {
    return null;
  }
  const expiredAt = now;
  return {
    ...row,
    status: 'expired',
    expired_at: expiredAt,
    purge_after: addDays(expiredAt, PURGE_DELAY_DAYS),
  };
}

function applyLogicalPurge(row, now) {
  if (!row || row.status !== 'expired') {
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
    status: 'deleted',
    deleted_at: now,
  };
}

function getQuery(deps) {
  if (deps.query) {
    return deps.query;
  }
  const db = deps.db || pool;
  return (sql, params) => db.query(sql, params);
}

async function runPublishScheduledJob(deps = {}) {
  requireDatabase();
  const now = deps.now || new Date();
  const limit = deps.limit || DEFAULT_LIMIT;
  const query = getQuery(deps);

  const due = await query(
    `SELECT *
     FROM publications
     WHERE status = 'scheduled'
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
         AND status = 'scheduled'
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
     WHERE status = 'active'
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
         AND status = 'active'
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
     WHERE status = 'expired'
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
         AND status = 'expired'
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
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
  runChroniqueLifecycleJobs,
};
