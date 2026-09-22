const pool = require('../db');
const AppError = require('../errors/AppError');
const {
  parseCreateInput,
  parseListQuery,
  parseChroniqueId,
} = require('../validators/chroniqueFields');

const SORT_COLUMN = {
  active: 'published_at',
  archived: 'archived_at',
  expired: 'expired_at',
  scheduled: 'scheduled_at',
  draft: 'updated_at',
};

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
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toISOString();
}

function toPublicChronique(row) {
  return {
    id: formatId(row.id),
    theme_id: row.theme_id == null ? null : formatId(row.theme_id),
    title: row.title,
    body: row.body,
    status: row.status,
    scheduled_at: toIso(row.scheduled_at),
    published_at: toIso(row.published_at),
    is_time_limited: row.is_time_limited,
    expires_at: toIso(row.expires_at),
    archived_at: toIso(row.archived_at),
    expired_at: toIso(row.expired_at),
    purge_after: toIso(row.purge_after),
    is_public: row.is_public,
    audience: row.audience,
    comments_enabled: row.comments_enabled,
    media_total_bytes: Number(row.media_total_bytes) || 0,
    media: [],
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

function sortValue(row, status) {
  return row[SORT_COLUMN[status]];
}

async function createChronique(userId, body) {
  const input = parseCreateInput(body);
  requireDatabase();

  let status = 'draft';
  let publishedAt = null;
  let scheduledAt = null;
  if (input.publish === 'now') {
    status = 'active';
    publishedAt = new Date();
  } else if (input.publish === 'schedule') {
    status = 'scheduled';
    scheduledAt = input.scheduledAt;
  }

  const result = await pool.query(
    `INSERT INTO publications (
       user_id,
       theme_id,
       title,
       body,
       status,
       scheduled_at,
       published_at,
       is_time_limited,
       expires_at,
       is_public,
       audience,
       comments_enabled,
       media_total_bytes
     )
     VALUES ($1, NULL, $2, $3, $4, $5, $6, $7, $8, FALSE, 'private', FALSE, 0)
     RETURNING *`,
    [
      userId,
      input.title,
      input.body,
      status,
      scheduledAt,
      publishedAt,
      input.isTimeLimited,
      input.expiresAt,
    ]
  );

  return toPublicChronique(result.rows[0]);
}

async function listChroniques(userId, query) {
  const { status, limit, beforeAt, beforeId } = parseListQuery(query);
  requireDatabase();

  const column = SORT_COLUMN[status];
  const params = [userId, status];
  let cursorSql = '';

  if (beforeAt != null) {
    params.push(beforeAt.toISOString(), beforeId);
    if (status === 'scheduled') {
      cursorSql = `AND (${column}, id) > ($3::timestamptz, $4::bigint)`;
    } else {
      cursorSql = `AND (${column}, id) < ($3::timestamptz, $4::bigint)`;
    }
  }

  params.push(limit + 1);
  const limitPlaceholder = `$${params.length}`;

  const orderSql =
    status === 'scheduled'
      ? `${column} ASC, id ASC`
      : `${column} DESC, id DESC`;

  const result = await pool.query(
    `SELECT *
     FROM publications
     WHERE user_id = $1
       AND status = $2
       ${cursorSql}
     ORDER BY ${orderSql}
     LIMIT ${limitPlaceholder}`,
    params
  );

  const rows = result.rows;
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const last = page[page.length - 1];

  let next = null;
  if (hasMore && last) {
    next = {
      before_at: toIso(sortValue(last, status)),
      before_id: formatId(last.id),
    };
  }

  return {
    items: page.map(toPublicChronique),
    next,
  };
}

async function getChroniqueById(userId, rawId) {
  const id = parseChroniqueId(rawId);
  requireDatabase();

  const result = await pool.query(
    `SELECT *
     FROM publications
     WHERE id = $1
       AND user_id = $2
       AND status <> 'deleted'
     LIMIT 1`,
    [id, userId]
  );

  const row = result.rows[0];
  if (!row) {
    throw new AppError(404, 'Chronique not found');
  }

  return toPublicChronique(row);
}

module.exports = {
  createChronique,
  listChroniques,
  getChroniqueById,
  toPublicChronique,
};
