const AppError = require('../errors/AppError');
const { parseFeedQuery, parseId } = require('./communityPublicationFields');

const COMMENT_MIN = 2;
const COMMENT_MAX = 200;
const COMMENT_STATUS = Object.freeze({
  VISIBLE: 'visible',
  AUTHOR_DELETED: 'author_deleted',
  MODERATED: 'moderated',
});

function codePointLength(value) {
  return Array.from(value).length;
}

function hasOwn(body, field) {
  return Object.prototype.hasOwnProperty.call(body, field);
}

function assertObject(body, message) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, message);
  }
}

function parseCommentBody(value) {
  if (typeof value !== 'string') {
    throw new AppError(400, 'body is invalid');
  }
  const body = value.trim();
  const length = codePointLength(body);
  if (length < COMMENT_MIN || length > COMMENT_MAX) {
    throw new AppError(400, 'body is invalid');
  }
  return body;
}

function parseParentCommentId(value) {
  if (value == null) {
    return null;
  }
  return parseId(value, 'parent_comment_id is invalid');
}

function parseCreateCommentInput(body) {
  assertObject(body, 'body is required');
  if (hasOwn(body, 'status') || hasOwn(body, 'author_user_id') || hasOwn(body, 'id')) {
    throw new AppError(400, 'field cannot be set');
  }
  if (!hasOwn(body, 'body')) {
    throw new AppError(400, 'body is required');
  }
  const parentCommentId = hasOwn(body, 'parent_comment_id')
    ? parseParentCommentId(body.parent_comment_id)
    : null;
  return { body: parseCommentBody(body.body), parentCommentId };
}

function parsePatchCommentInput(body) {
  assertObject(body, 'body is required');
  if (hasOwn(body, 'status') || hasOwn(body, 'author_user_id') || hasOwn(body, 'id')) {
    throw new AppError(400, 'field cannot be set');
  }
  if (!hasOwn(body, 'body')) {
    throw new AppError(400, 'body is required');
  }
  return { body: parseCommentBody(body.body) };
}

function parseCommentId(value) {
  return parseId(value, 'id is invalid');
}

function parseCommentListQuery(query) {
  const parsed = parseFeedQuery(query);
  if (parsed.limit > 20) {
    throw new AppError(400, 'limit is invalid');
  }
  return parsed;
}

module.exports = {
  COMMENT_MIN,
  COMMENT_MAX,
  COMMENT_STATUS,
  parseCreateCommentInput,
  parsePatchCommentInput,
  parseCommentId,
  parseCommentListQuery,
};
