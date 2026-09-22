const AppError = require('../errors/AppError');

const BODY_MIN = 20;
const BODY_MAX = 5000;
const TITLE_MAX = 200;
const LIST_STATUSES = ['draft', 'scheduled', 'active', 'archived', 'expired'];
const PUBLISH_MODES = ['draft', 'now', 'schedule'];
const FORBIDDEN_CREATE_FIELDS = [
  'user_id',
  'theme_id',
  'is_public',
  'audience',
  'comments_enabled',
  'media',
  'status',
];

function codePointLength(value) {
  return Array.from(value).length;
}

function assertObject(body) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'body is required');
  }
}

function rejectForbiddenCreateFields(body) {
  for (const field of FORBIDDEN_CREATE_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(body, field)) {
      if (field === 'status') {
        throw new AppError(400, 'status cannot be set');
      }
      if (field === 'media') {
        throw new AppError(400, 'media cannot be set on create');
      }
      throw new AppError(400, `${field} cannot be set`);
    }
  }
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
  const length = codePointLength(body);
  if (length < BODY_MIN) {
    throw new AppError(400, 'body is too short');
  }
  if (length > BODY_MAX) {
    throw new AppError(400, 'body is too long');
  }
  return body;
}

function parseDate(value, invalidMessage) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, invalidMessage);
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new AppError(400, invalidMessage);
  }
  return date;
}

function parseCreateInput(body) {
  assertObject(body);
  rejectForbiddenCreateFields(body);

  const title = parseTitle(body.title);
  const text = parseBody(body.body);

  const hasPublish = Object.prototype.hasOwnProperty.call(body, 'publish');
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
    publish,
    scheduledAt,
    isTimeLimited,
    expiresAt,
  };
}

function parseListQuery(query) {
  const raw = query || {};
  let status = raw.status;
  if (status == null || status === '') {
    status = 'active';
  }
  if (typeof status !== 'string' || !LIST_STATUSES.includes(status)) {
    throw new AppError(400, 'status is invalid');
  }

  let limit = 20;
  if (raw.limit != null && raw.limit !== '') {
    const parsed = Number(raw.limit);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 50) {
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
    const id = Number(raw.before_id);
    if (!Number.isInteger(id) || id < 1) {
      throw new AppError(400, 'before_id is invalid');
    }
    beforeId = id;
  }

  return { status, limit, beforeAt, beforeId };
}

function parseChroniqueId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id < 1) {
    throw new AppError(400, 'id is invalid');
  }
  return id;
}

module.exports = {
  BODY_MIN,
  BODY_MAX,
  TITLE_MAX,
  LIST_STATUSES,
  parseCreateInput,
  parseListQuery,
  parseChroniqueId,
};
