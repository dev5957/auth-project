const AppError = require('../errors/AppError');

const BODY_MIN = 20;
const BODY_MAX = 5000;
const TITLE_MAX = 200;
const CHRONIQUE_STATUS = Object.freeze({
  DRAFT: 'draft',
  SCHEDULED: 'scheduled',
  ACTIVE: 'active',
  ARCHIVED: 'archived',
  EXPIRED: 'expired',
  DELETED: 'deleted',
});
const LIST_STATUSES = [
  CHRONIQUE_STATUS.DRAFT,
  CHRONIQUE_STATUS.SCHEDULED,
  CHRONIQUE_STATUS.ACTIVE,
  CHRONIQUE_STATUS.ARCHIVED,
  CHRONIQUE_STATUS.EXPIRED,
];
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
const FORBIDDEN_MUTATION_FIELDS = [
  ...FORBIDDEN_CREATE_FIELDS,
  'created_at',
  'updated_at',
  'published_at',
  'archived_at',
  'expired_at',
  'purge_after',
  'deleted_at',
];
const PATCH_FIELDS = [
  'title',
  'body',
  'publish',
  'scheduled_at',
  'is_time_limited',
  'expires_at',
];

function codePointLength(value) {
  return Array.from(value).length;
}

function assertObject(body) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'body is required');
  }
}

function rejectForbiddenFields(body, fields, mediaMessage) {
  for (const field of fields) {
    if (Object.prototype.hasOwnProperty.call(body, field)) {
      if (field === 'status') {
        throw new AppError(400, 'status cannot be set');
      }
      if (field === 'media') {
        throw new AppError(400, mediaMessage);
      }
      throw new AppError(400, `${field} cannot be set`);
    }
  }
}

function rejectForbiddenCreateFields(body) {
  rejectForbiddenFields(body, FORBIDDEN_CREATE_FIELDS, 'media cannot be set on create');
}

function rejectForbiddenMutationFields(body) {
  rejectForbiddenFields(body, FORBIDDEN_MUTATION_FIELDS, 'media cannot be set');
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

function hasOwn(body, field) {
  return Object.prototype.hasOwnProperty.call(body, field);
}

function parsePublishMode(value) {
  if (typeof value !== 'string' || !PUBLISH_MODES.includes(value)) {
    throw new AppError(400, 'publish is invalid');
  }
  return value;
}

function parsePatchInput(body) {
  assertObject(body);
  rejectForbiddenMutationFields(body);

  const recognized = PATCH_FIELDS.some((field) => hasOwn(body, field));
  if (!recognized) {
    throw new AppError(400, 'No fields to update');
  }

  const input = {
    hasTitle: hasOwn(body, 'title'),
    title: undefined,
    hasBody: hasOwn(body, 'body'),
    body: undefined,
    hasPublish: hasOwn(body, 'publish'),
    publish: undefined,
    hasScheduled: hasOwn(body, 'scheduled_at'),
    scheduledAt: null,
    hasTimeLimited: hasOwn(body, 'is_time_limited'),
    isTimeLimited: false,
    hasExpires: hasOwn(body, 'expires_at'),
    expiresAt: null,
  };

  if (input.hasTitle) {
    input.title = parseTitle(body.title);
  }
  if (input.hasBody) {
    input.body = parseBody(body.body);
  }

  const hasScheduledValue = body.scheduled_at != null && body.scheduled_at !== '';

  if (input.hasPublish) {
    input.publish = parsePublishMode(body.publish);
    if (input.publish === 'now' || input.publish === 'draft') {
      if (hasScheduledValue) {
        throw new AppError(400, 'publish is invalid');
      }
    } else if (!hasScheduledValue) {
      throw new AppError(400, 'scheduled_at is required');
    }
  }

  if (hasScheduledValue) {
    input.scheduledAt = parseDate(body.scheduled_at, 'scheduled_at must be in the future');
    if (input.scheduledAt.getTime() <= Date.now()) {
      throw new AppError(400, 'scheduled_at must be in the future');
    }
  } else if (input.hasPublish && input.publish === 'schedule') {
    throw new AppError(400, 'scheduled_at is required');
  }

  if (input.hasTimeLimited) {
    input.isTimeLimited = body.is_time_limited === true;
    if (input.isTimeLimited && (body.expires_at == null || body.expires_at === '')) {
      throw new AppError(400, 'expires_at is required');
    }
  }

  if (input.hasExpires && body.expires_at != null && body.expires_at !== '') {
    input.expiresAt = parseDate(body.expires_at, 'expires_at is required');
  } else if (input.hasTimeLimited && input.isTimeLimited) {
    input.expiresAt = parseDate(body.expires_at, 'expires_at is required');
  }

  return input;
}

function parseRestoreInput(body) {
  if (body == null || body === '') {
    return { isTimeLimited: false, expiresAt: null };
  }
  assertObject(body);
  rejectForbiddenMutationFields(body);

  const isTimeLimited = body.is_time_limited === true;
  if (!isTimeLimited) {
    return { isTimeLimited: false, expiresAt: null };
  }

  const expiresAt = parseDate(body.expires_at, 'expires_at is required');
  if (expiresAt.getTime() <= Date.now()) {
    throw new AppError(400, 'expires_at must be after activation time');
  }
  return { isTimeLimited: true, expiresAt };
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
  CHRONIQUE_STATUS,
  LIST_STATUSES,
  parseCreateInput,
  parsePatchInput,
  parseRestoreInput,
  parseListQuery,
  parseChroniqueId,
};
