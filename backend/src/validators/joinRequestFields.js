const AppError = require('../errors/AppError');

const JOIN_REQUEST_STATUSES = Object.freeze([
  'pending',
  'accepted',
  'declined',
  'cancelled',
]);

const FORBIDDEN_JOIN_REQUEST_FIELDS = [
  'id',
  'community_id',
  'user_id',
  'status',
  'login',
  'phone',
  'phone_number',
  'email',
  'role',
  'created_at',
  'updated_at',
];

function hasOwn(body, field) {
  return Object.prototype.hasOwnProperty.call(body, field);
}

function parseJoinRequestCreateBody(body) {
  if (body == null) {
    return {};
  }
  if (typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'invalid body');
  }
  for (const field of FORBIDDEN_JOIN_REQUEST_FIELDS) {
    if (hasOwn(body, field)) {
      throw new AppError(400, `${field} cannot be set`);
    }
  }
  return {};
}

function parseJoinRequestId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id < 1) {
    throw new AppError(400, 'id is invalid');
  }
  return id;
}

module.exports = {
  JOIN_REQUEST_STATUSES,
  parseJoinRequestCreateBody,
  parseJoinRequestId,
};
