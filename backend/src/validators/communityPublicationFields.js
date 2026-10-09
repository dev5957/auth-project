const AppError = require('../errors/AppError');

const BODY_MIN_NON_WHITESPACE = 10;
const BODY_MAX = 1000;
const TITLE_MAX = 200;
const PURGE_DELAY_DAYS = 30;
const MAX_MEDIA = 5;
const MAX_BYTES = 209715200;
const DEFAULT_LIST_LIMIT = 20;
const MAX_LIST_LIMIT = 50;

const STATUS = Object.freeze({
  DRAFT: 'draft',
  SCHEDULED: 'scheduled',
  ACTIVE: 'active',
  EXPIRED: 'expired',
  DELETED: 'deleted',
});

const PUBLISH_MODES = ['draft', 'now', 'schedule'];
const ME_SCOPES = ['current', 'left', 'expired'];

const FORBIDDEN_CREATE_FIELDS = [
  'author_user_id',
  'community_id',
  'user_id',
  'theme_id',
  'is_public',
  'audience',
  'media',
  'status',
  'deleted_by_user_id',
];

const FORBIDDEN_PATCH_FIELDS = [
  ...FORBIDDEN_CREATE_FIELDS,
  'comments_enabled',
  'publish',
  'scheduled_at',
  'is_time_limited',
  'expires_at',
  'created_at',
  'updated_at',
  'published_at',
  'expired_at',
  'purge_after',
  'deleted_at',
  'initial_media_count',
  'initial_media_open',
];

function codePointLength(value) {
  return Array.from(value).length;
}

function nonWhitespaceLength(value) {
  return codePointLength(String(value).replace(/\s/gu, ''));
}

function hasOwn(body, field) {
  return Object.prototype.hasOwnProperty.call(body, field);
}

function assertObject(body, message) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, message);
  }
}

function rejectFields(body, fields) {
  for (const field of fields) {
    if (hasOwn(body, field)) {
      if (field === 'status') {
        throw new AppError(400, 'status cannot be set');
      }
      if (field === 'media') {
        throw new AppError(400, 'media cannot be set');
      }
      throw new AppError(400, `${field} cannot be set`);
    }
  }
}

function parseDate(value, message) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new AppError(400, message);
  }
  return date;
}

function parseTitle(value) {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new AppError(400, 'title is invalid');
  }
  const title = value.trim();
  if (title === '') {
    return null;
  }
  if (codePointLength(title) > TITLE_MAX) {
    throw new AppError(400, 'title is invalid');
  }
  return title;
}

function parseBody(value) {
  if (typeof value !== 'string') {
    throw new AppError(400, 'body is required');
  }
  const body = value.trim();
  if (body === '') {
    throw new AppError(400, 'body is required');
  }
  if (nonWhitespaceLength(body) < BODY_MIN_NON_WHITESPACE) {
    throw new AppError(400, 'body is too short');
  }
  if (codePointLength(body) > BODY_MAX) {
    throw new AppError(400, 'body is too long');
  }
  return body;
}

function parseId(value, message) {
  const id = Number(value);
  if (!Number.isInteger(id) || id < 1) {
    throw new AppError(400, message);
  }
  return id;
}

function parseCreateInput(body) {
  assertObject(body, 'body is required');
  rejectFields(body, FORBIDDEN_CREATE_FIELDS);

  const title = parseTitle(body.title);
  const text = parseBody(body.body);
  const commentsEnabled = body.comments_enabled === true;

  const hasPublish = hasOwn(body, 'publish');
  const hasScheduled = body.scheduled_at != null && body.scheduled_at !== '';
  if (!hasPublish && !hasScheduled) {
    throw new AppError(400, 'publish is required');
  }
  const publish = hasPublish ? body.publish : 'schedule';
  if (typeof publish !== 'string' || !PUBLISH_MODES.includes(publish)) {
    throw new AppError(400, 'publish is invalid');
  }

  let scheduledAt = null;
  if (publish === 'now') {
    if (hasScheduled) {
      throw new AppError(400, 'publish is invalid');
    }
  } else if (publish === 'draft') {
    if (hasScheduled) {
      throw new AppError(400, 'publish is invalid');
    }
  } else if (publish === 'schedule') {
    if (!hasScheduled) {
      throw new AppError(400, 'scheduled_at is required');
    }
    scheduledAt = parseDate(body.scheduled_at, 'scheduled_at must be in the future');
    if (scheduledAt.getTime() <= Date.now()) {
      throw new AppError(400, 'scheduled_at must be in the future');
    }
  }

  let initialMediaCount = 0;
  if (hasOwn(body, 'initial_media_count')) {
    const parsedCount = Number(body.initial_media_count);
    if (!Number.isInteger(parsedCount) || parsedCount < 0 || parsedCount > MAX_MEDIA) {
      throw new AppError(400, 'initial_media_count is invalid');
    }
    initialMediaCount = parsedCount;
  }

  const isTimeLimited = body.is_time_limited === true;
  let expiresAt = null;
  if (isTimeLimited) {
    expiresAt = parseDate(body.expires_at, 'expires_at is required');
    const activationMs = publish === 'schedule' ? scheduledAt.getTime() : Date.now();
    if (expiresAt.getTime() <= activationMs) {
      throw new AppError(400, 'expires_at must be after activation time');
    }
  }

  return {
    title,
    body: text,
    commentsEnabled,
    publish,
    scheduledAt,
    isTimeLimited,
    expiresAt,
    initialMediaCount,
  };
}

function parsePatchInput(body) {
  assertObject(body, 'body is required');
  rejectFields(body, FORBIDDEN_PATCH_FIELDS);
  const hasTitle = hasOwn(body, 'title');
  const hasBody = hasOwn(body, 'body');
  if (!hasTitle && !hasBody) {
    throw new AppError(400, 'title or body is required');
  }
  const input = {};
  if (hasTitle) {
    input.title = parseTitle(body.title);
  }
  if (hasBody) {
    input.body = parseBody(body.body);
  }
  return input;
}

function parseFeedQuery(query) {
  const raw = query || {};
  let limit = DEFAULT_LIST_LIMIT;
  if (raw.limit != null && raw.limit !== '') {
    const parsed = Number(raw.limit);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_LIST_LIMIT) {
      throw new AppError(400, 'limit is invalid');
    }
    limit = parsed;
  }
  const hasAt = raw.before_at != null && String(raw.before_at).trim() !== '';
  const hasId = raw.before_id != null && String(raw.before_id).trim() !== '';
  if (hasAt !== hasId) {
    throw new AppError(400, 'cursor is incomplete');
  }
  let beforeAt = null;
  let beforeId = null;
  if (hasAt) {
    beforeAt = parseDate(String(raw.before_at), 'before_at is invalid');
    beforeId = parseId(raw.before_id, 'before_id is invalid');
  }
  return { limit, beforeAt, beforeId };
}

function parseMeQuery(query) {
  const raw = query || {};
  let scope = raw.scope;
  if (scope == null || scope === '') {
    scope = 'current';
  }
  if (typeof scope !== 'string' || !ME_SCOPES.includes(scope)) {
    throw new AppError(400, 'scope is invalid');
  }
  const feed = parseFeedQuery(raw);
  return { scope, ...feed };
}

module.exports = {
  BODY_MIN_NON_WHITESPACE,
  BODY_MAX,
  TITLE_MAX,
  PURGE_DELAY_DAYS,
  MAX_MEDIA,
  MAX_BYTES,
  DEFAULT_LIST_LIMIT,
  STATUS,
  parseCreateInput,
  parsePatchInput,
  parseFeedQuery,
  parseMeQuery,
  parseId,
};
