const AppError = require('../errors/AppError');
const { parseTargetUserId } = require('./communityFields');

const INVITATION_STATUSES = Object.freeze([
  'pending',
  'accepted',
  'declined',
  'replaced',
  'cancelled',
]);

const DECLINE_LIMIT = 5;

const FORBIDDEN_INVITE_FIELDS = [
  'id',
  'community_id',
  'invitee_user_id',
  'invited_by_user_id',
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

function parseInviteBody(body) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'user_id is required');
  }
  for (const field of FORBIDDEN_INVITE_FIELDS) {
    if (hasOwn(body, field)) {
      throw new AppError(400, `${field} cannot be set`);
    }
  }
  if (!hasOwn(body, 'user_id')) {
    throw new AppError(400, 'user_id is required');
  }
  return { userId: parseTargetUserId(body.user_id) };
}

function parseInvitationId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id < 1) {
    throw new AppError(400, 'id is invalid');
  }
  return id;
}

module.exports = {
  INVITATION_STATUSES,
  DECLINE_LIMIT,
  parseInviteBody,
  parseInvitationId,
};
