const AppError = require('../errors/AppError');

const NAME_MIN = 10;
const NAME_MAX = 100;
const DESCRIPTION_MAX = 500;
const SEARCH_Q_MAX = 100;
const MEMBER_ROLES = Object.freeze(['owner', 'admin', 'member']);
const ASSIGNABLE_ROLES = Object.freeze(['admin', 'member']);
const VISIBILITY_PRIVATE = 'private';

const FORBIDDEN_CREATE_FIELDS = [
  'id',
  'user_id',
  'created_by',
  'visibility',
  'role',
  'avatar_storage_key',
  'banner_storage_key',
  'storage_key',
  'created_at',
  'updated_at',
  'member_count',
  'my_role',
];

function codePointLength(value) {
  return Array.from(value).length;
}

function hasOwn(body, field) {
  return Object.prototype.hasOwnProperty.call(body, field);
}

function assertObject(body, requiredField) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, `${requiredField} is required`);
  }
}

function rejectForbidden(body) {
  for (const field of FORBIDDEN_CREATE_FIELDS) {
    if (hasOwn(body, field)) {
      throw new AppError(400, `${field} cannot be set`);
    }
  }
}

function parseCommunityId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id < 1) {
    throw new AppError(400, 'id is invalid');
  }
  return id;
}

function parseTargetUserId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id < 1) {
    throw new AppError(400, 'user_id is invalid');
  }
  return id;
}

function parseName(raw) {
  if (raw == null || typeof raw !== 'string') {
    throw new AppError(400, 'name is required');
  }
  const name = raw.trim();
  if (name === '') {
    throw new AppError(400, 'name is required');
  }
  const length = codePointLength(name);
  if (length < NAME_MIN) {
    throw new AppError(400, 'name is too short');
  }
  if (length > NAME_MAX) {
    throw new AppError(400, 'name is too long');
  }
  return name;
}

function parseDescription(raw) {
  if (raw == null) {
    return null;
  }
  if (typeof raw !== 'string') {
    throw new AppError(400, 'description is invalid');
  }
  const description = raw.trim();
  if (description === '') {
    return null;
  }
  if (codePointLength(description) > DESCRIPTION_MAX) {
    throw new AppError(400, 'description is too long');
  }
  return description;
}

function parseCreateCommunityInput(body) {
  assertObject(body, 'name');
  rejectForbidden(body);
  if (!hasOwn(body, 'name')) {
    throw new AppError(400, 'name is required');
  }
  return {
    name: parseName(body.name),
    description: hasOwn(body, 'description') ? parseDescription(body.description) : null,
    visibility: VISIBILITY_PRIVATE,
  };
}

function parseSearchQuery(query) {
  const raw = query || {};
  const qRaw = raw.q;
  if (qRaw == null || typeof qRaw !== 'string') {
    throw new AppError(400, 'q is required');
  }
  const q = qRaw.trim();
  if (q === '') {
    throw new AppError(400, 'q is required');
  }
  if (codePointLength(q) > SEARCH_Q_MAX) {
    throw new AppError(400, 'q is invalid');
  }

  let limit = 20;
  if (raw.limit != null && raw.limit !== '') {
    const parsed = Number(raw.limit);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 50) {
      throw new AppError(400, 'limit is invalid');
    }
    limit = parsed;
  }

  return { q, limit };
}

function parseListQuery(query) {
  const raw = query || {};
  let limit = 20;
  if (raw.limit != null && raw.limit !== '') {
    const parsed = Number(raw.limit);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 50) {
      throw new AppError(400, 'limit is invalid');
    }
    limit = parsed;
  }
  return { limit };
}

function parseRolePatch(body) {
  assertObject(body, 'role');
  if (hasOwn(body, 'owner') || hasOwn(body, 'user_id') || hasOwn(body, 'community_id')) {
    throw new AppError(400, 'role cannot be set');
  }
  if (!hasOwn(body, 'role') || body.role == null || body.role === '') {
    throw new AppError(400, 'role is required');
  }
  if (typeof body.role !== 'string' || !ASSIGNABLE_ROLES.includes(body.role)) {
    throw new AppError(400, 'role is invalid');
  }
  return { role: body.role };
}

function escapeIlikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

module.exports = {
  NAME_MIN,
  NAME_MAX,
  DESCRIPTION_MAX,
  MEMBER_ROLES,
  ASSIGNABLE_ROLES,
  VISIBILITY_PRIVATE,
  parseCommunityId,
  parseTargetUserId,
  parseCreateCommunityInput,
  parseSearchQuery,
  parseListQuery,
  parseRolePatch,
  escapeIlikePattern,
};
