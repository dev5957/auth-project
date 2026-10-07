const AppError = require('../errors/AppError');

const SLOTS = Object.freeze(['avatar', 'banner']);
const IMAGE_TYPES = Object.freeze(['image/jpeg', 'image/png', 'image/webp']);
const MAX_BYTES = 10 * 1024 * 1024;
const SESSION_TTL_MS = 15 * 60 * 1000;

const FORBIDDEN_INIT_FIELDS = [
  'id',
  'user_id',
  'created_by',
  'storage_key',
  'avatar_storage_key',
  'banner_storage_key',
  'upload_id',
  'read_url',
  'avatar_read_url',
  'banner_read_url',
  'url',
  'key',
];

const FORBIDDEN_COMPLETE_FIELDS = [
  'id',
  'user_id',
  'storage_key',
  'avatar_storage_key',
  'banner_storage_key',
  'read_url',
  'avatar_read_url',
  'banner_read_url',
  'url',
  'key',
  'content_type',
  'byte_size',
];

function hasOwn(body, field) {
  return Object.prototype.hasOwnProperty.call(body, field);
}

function assertObject(body, requiredField) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, `${requiredField} is required`);
  }
}

function rejectFields(body, fields) {
  for (const field of fields) {
    if (hasOwn(body, field)) {
      throw new AppError(400, `${field} cannot be set`);
    }
  }
}

function parseIdentitySlot(raw) {
  if (typeof raw !== 'string' || !SLOTS.includes(raw)) {
    throw new AppError(400, 'slot is invalid');
  }
  return raw;
}

function parseIdentityUploadInput(body) {
  assertObject(body, 'content_type');
  rejectFields(body, FORBIDDEN_INIT_FIELDS);
  if (typeof body.content_type !== 'string' || body.content_type.trim() === '') {
    throw new AppError(400, 'content_type is invalid');
  }
  const contentType = body.content_type.trim().toLowerCase();
  if (!IMAGE_TYPES.includes(contentType)) {
    throw new AppError(400, 'content_type is invalid');
  }
  const byteSize = Number(body.byte_size);
  if (!Number.isInteger(byteSize) || byteSize < 1) {
    throw new AppError(400, 'byte_size is invalid');
  }
  if (byteSize > MAX_BYTES) {
    throw new AppError(400, 'Media quota exceeded');
  }
  return { contentType, byteSize };
}

function parseIdentityCompleteInput(body) {
  assertObject(body, 'upload_id');
  rejectFields(body, FORBIDDEN_COMPLETE_FIELDS);
  if (typeof body.upload_id !== 'string' || body.upload_id.trim() === '') {
    throw new AppError(400, 'upload_id is required');
  }
  return { uploadId: body.upload_id.trim() };
}

function columnForSlot(slot) {
  return slot === 'banner' ? 'banner_storage_key' : 'avatar_storage_key';
}

module.exports = {
  SLOTS,
  IMAGE_TYPES,
  MAX_BYTES,
  SESSION_TTL_MS,
  parseIdentitySlot,
  parseIdentityUploadInput,
  parseIdentityCompleteInput,
  columnForSlot,
};
