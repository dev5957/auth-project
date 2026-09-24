const AppError = require('../errors/AppError');

const KINDS = ['image', 'video', 'audio', 'document'];
const SOURCE_BY_KIND = {
  image: ['camera', 'gallery'],
  video: ['camera', 'gallery', 'upload'],
  audio: ['microphone', 'upload'],
  document: ['upload'],
};
const MIME_BY_KIND = {
  image: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'],
  video: ['video/mp4', 'video/quicktime', 'video/webm'],
  audio: ['audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/ogg'],
  document: [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain',
  ],
};
const FORBIDDEN_FIELDS = [
  'user_id',
  'publication_id',
  'storage_key',
  'status',
  'sort_order',
  'id',
];
const FILENAME_MAX = 255;

function hasOwn(body, field) {
  return Object.prototype.hasOwnProperty.call(body, field);
}

function assertObject(body) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'kind is required');
  }
}

function rejectForbidden(body) {
  for (const field of FORBIDDEN_FIELDS) {
    if (hasOwn(body, field)) {
      throw new AppError(400, `${field} cannot be set`);
    }
  }
}

function parseMediaId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id < 1) {
    throw new AppError(400, 'id is invalid');
  }
  return id;
}

function parseOriginalFilename(value) {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new AppError(400, 'original_filename is invalid');
  }
  const name = value.trim();
  if (name === '') {
    return null;
  }
  if (Array.from(name).length > FILENAME_MAX) {
    throw new AppError(400, 'original_filename is invalid');
  }
  return name;
}

function parseUploadInput(body) {
  assertObject(body);
  rejectForbidden(body);

  if (!hasOwn(body, 'kind') || body.kind == null || body.kind === '') {
    throw new AppError(400, 'kind is required');
  }
  if (typeof body.kind !== 'string' || !KINDS.includes(body.kind)) {
    throw new AppError(400, 'kind is invalid');
  }
  const kind = body.kind;

  if (!hasOwn(body, 'source_type') || body.source_type == null || body.source_type === '') {
    throw new AppError(400, 'source_type is required');
  }
  if (typeof body.source_type !== 'string' || !SOURCE_BY_KIND[kind].includes(body.source_type)) {
    throw new AppError(400, 'source_type is invalid');
  }
  const sourceType = body.source_type;

  if (typeof body.content_type !== 'string' || body.content_type.trim() === '') {
    throw new AppError(400, 'content_type is invalid');
  }
  const contentType = body.content_type.trim().toLowerCase();
  if (!MIME_BY_KIND[kind].includes(contentType)) {
    throw new AppError(400, 'content_type is invalid');
  }

  const byteSize = Number(body.byte_size);
  if (!Number.isInteger(byteSize) || byteSize < 1) {
    throw new AppError(400, 'byte_size is invalid');
  }

  return {
    kind,
    sourceType,
    contentType,
    byteSize,
    originalFilename: parseOriginalFilename(body.original_filename),
  };
}

function parseMediaOrder(body) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'media_ids is invalid');
  }
  rejectForbidden(body);
  if (!Array.isArray(body.media_ids) || body.media_ids.length === 0) {
    throw new AppError(400, 'media_ids is invalid');
  }

  const ids = [];
  const seen = new Set();
  for (const value of body.media_ids) {
    const id = Number(value);
    if (!Number.isInteger(id) || id < 1 || seen.has(id)) {
      throw new AppError(400, 'media_ids is invalid');
    }
    seen.add(id);
    ids.push(id);
  }
  return ids;
}

module.exports = {
  KINDS,
  SOURCE_BY_KIND,
  MIME_BY_KIND,
  parseMediaId,
  parseUploadInput,
  parseMediaOrder,
};
