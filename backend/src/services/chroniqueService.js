const pool = require('../db');
const AppError = require('../errors/AppError');
const {
  parseCreateInput,
  parsePatchInput,
  parseRestoreInput,
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

function inertSocial(next) {
  next.theme_id = null;
  next.is_public = false;
  next.audience = 'private';
  next.comments_enabled = false;
}

function applyEphemeral(next, input, now) {
  let isTimeLimited = Boolean(next.is_time_limited);
  let expiresAt = asDate(next.expires_at);

  if (input.hasTimeLimited) {
    isTimeLimited = input.isTimeLimited;
    if (!isTimeLimited) {
      expiresAt = null;
    }
  }
  if (input.hasExpires) {
    expiresAt = input.expiresAt;
  }

  if (isTimeLimited) {
    if (expiresAt == null) {
      throw new AppError(400, 'expires_at is required');
    }
    const activationMs =
      next.status === 'scheduled' ? asDate(next.scheduled_at).getTime() : now.getTime();
    if (expiresAt.getTime() <= activationMs) {
      throw new AppError(400, 'expires_at must be after activation time');
    }
  } else {
    expiresAt = null;
  }

  next.is_time_limited = isTimeLimited;
  next.expires_at = expiresAt;
}

function applyPatchToRow(row, input, now) {
  if (row.status === 'archived' || row.status === 'expired') {
    throw new AppError(400, 'Chronique cannot be edited in this status');
  }
  if (row.status !== 'draft' && row.status !== 'scheduled' && row.status !== 'active') {
    throw new AppError(400, 'Chronique cannot be edited in this status');
  }

  const next = { ...row };
  if (input.hasTitle) {
    next.title = input.title;
  }
  if (input.hasBody) {
    next.body = input.body;
  }

  let status = row.status;
  let scheduledAt = asDate(row.scheduled_at);
  let publishedAt = asDate(row.published_at);

  if (input.hasPublish) {
    if (status === 'active') {
      if (input.publish === 'draft' || input.publish === 'schedule') {
        throw new AppError(409, 'Invalid status transition');
      }
    } else if (status === 'draft') {
      if (input.publish === 'now') {
        status = 'active';
        publishedAt = now;
        scheduledAt = null;
      } else if (input.publish === 'schedule') {
        status = 'scheduled';
        scheduledAt = input.scheduledAt;
        publishedAt = null;
      } else {
        status = 'draft';
        scheduledAt = null;
      }
    } else if (status === 'scheduled') {
      if (input.publish === 'now') {
        status = 'active';
        publishedAt = now;
        scheduledAt = null;
      } else if (input.publish === 'draft') {
        status = 'draft';
        scheduledAt = null;
      } else {
        status = 'scheduled';
        scheduledAt = input.scheduledAt;
      }
    }
  } else if (input.hasScheduled) {
    if (status === 'scheduled') {
      if (input.scheduledAt == null) {
        throw new AppError(400, 'scheduled_at is required');
      }
      scheduledAt = input.scheduledAt;
    } else if (status === 'draft') {
      throw new AppError(400, 'publish is invalid');
    } else {
      throw new AppError(409, 'Invalid status transition');
    }
  }

  next.status = status;
  next.scheduled_at = scheduledAt;
  next.published_at = publishedAt;
  applyEphemeral(next, input, now);
  inertSocial(next);
  return next;
}

async function withOwnedPublication(userId, rawId, deps, fn) {
  const id = parseChroniqueId(rawId);
  requireDatabase();
  const db = deps.db || pool;
  const client = await db.connect();
  let committed = false;

  try {
    await client.query('BEGIN');
    const found = await client.query(
      `SELECT *
       FROM publications
       WHERE id = $1
         AND user_id = $2
       FOR UPDATE`,
      [id, userId]
    );
    const row = found.rows[0];
    if (!row || row.status === 'deleted') {
      throw new AppError(404, 'Chronique not found');
    }

    const result = await fn(client, row);
    await client.query('COMMIT');
    committed = true;
    return result;
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // ignore rollback errors
      }
    }
    throw err;
  } finally {
    client.release();
  }
}

async function savePublication(client, userId, next) {
  const result = await client.query(
    `UPDATE publications
     SET title = $1,
         body = $2,
         status = $3,
         scheduled_at = $4,
         published_at = $5,
         archived_at = $6,
         expired_at = $7,
         purge_after = $8,
         deleted_at = $9,
         is_time_limited = $10,
         expires_at = $11,
         theme_id = NULL,
         is_public = FALSE,
         audience = 'private',
         comments_enabled = FALSE,
         updated_at = NOW()
     WHERE id = $12
       AND user_id = $13
     RETURNING *`,
    [
      next.title,
      next.body,
      next.status,
      next.scheduled_at,
      next.published_at,
      next.archived_at,
      next.expired_at,
      next.purge_after,
      next.deleted_at,
      next.is_time_limited,
      next.expires_at,
      next.id,
      userId,
    ]
  );
  if (result.rowCount !== 1) {
    throw new AppError(404, 'Chronique not found');
  }
  return result.rows[0];
}

async function updateChronique(userId, rawId, body, deps = {}) {
  const input = parsePatchInput(body);
  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    const next = applyPatchToRow(row, input, new Date());
    const saved = await savePublication(client, userId, next);
    return toPublicChronique(saved);
  });
}

async function archiveChronique(userId, rawId, deps = {}) {
  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    if (row.status === 'archived') {
      return toPublicChronique(row);
    }
    if (row.status === 'draft' || row.status === 'expired') {
      throw new AppError(400, 'Chronique cannot be archived in this status');
    }
    if (row.status !== 'active' && row.status !== 'scheduled') {
      throw new AppError(400, 'Chronique cannot be archived in this status');
    }

    const next = {
      ...row,
      status: 'archived',
      archived_at: new Date(),
      scheduled_at: null,
      is_time_limited: false,
      expires_at: null,
    };
    inertSocial(next);
    const saved = await savePublication(client, userId, next);
    return toPublicChronique(saved);
  });
}

async function restoreChronique(userId, rawId, body, deps = {}) {
  const input = parseRestoreInput(body);
  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    if (row.status !== 'archived') {
      throw new AppError(400, 'Chronique cannot be restored in this status');
    }

    const publishedAt = asDate(row.published_at) || new Date();
    const next = {
      ...row,
      status: 'active',
      archived_at: null,
      scheduled_at: null,
      published_at: publishedAt,
      is_time_limited: input.isTimeLimited,
      expires_at: input.expiresAt,
    };
    inertSocial(next);
    const saved = await savePublication(client, userId, next);
    return toPublicChronique(saved);
  });
}

async function deleteChronique(userId, rawId, deps = {}) {
  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    const next = {
      ...row,
      status: 'deleted',
      deleted_at: new Date(),
    };
    inertSocial(next);
    await savePublication(client, userId, next);
    return true;
  });
}

module.exports = {
  createChronique,
  listChroniques,
  getChroniqueById,
  updateChronique,
  archiveChronique,
  restoreChronique,
  deleteChronique,
  toPublicChronique,
  withOwnedPublication,
};
