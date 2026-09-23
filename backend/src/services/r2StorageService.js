const { S3Client, PutObjectCommand, GetObjectCommand, HeadObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const AppError = require('../errors/AppError');

const DEFAULT_UPLOAD_TTL_SECONDS = 15 * 60;
const DEFAULT_READ_TTL_SECONDS = 15 * 60;
const REQUIRED_R2_VARS = [
  'R2_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET',
  'R2_ENDPOINT',
  'R2_REGION',
];

function storageNotConfigured() {
  return new AppError(503, 'Storage is not configured');
}

function readTrimmed(env, name) {
  const value = env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function parseTtlSeconds(raw, fallback) {
  if (raw == null || String(raw).trim() === '') {
    return fallback;
  }
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 7 * 24 * 60 * 60) {
    throw storageNotConfigured();
  }
  return parsed;
}

function readR2Config(env) {
  const config = {};
  for (const name of REQUIRED_R2_VARS) {
    const value = readTrimmed(env, name);
    if (!value) {
      throw storageNotConfigured();
    }
    config[name] = value;
  }
  config.uploadTtlSeconds = parseTtlSeconds(
    env.R2_SIGNED_UPLOAD_TTL_SECONDS,
    DEFAULT_UPLOAD_TTL_SECONDS
  );
  config.readTtlSeconds = parseTtlSeconds(
    env.R2_SIGNED_READ_TTL_SECONDS,
    DEFAULT_READ_TTL_SECONDS
  );
  return config;
}

function isAbsentObjectError(err) {
  if (err == null || typeof err !== 'object') {
    return false;
  }
  const status = err.$metadata && err.$metadata.httpStatusCode;
  const name = err.name || err.Code || err.code;
  return (
    status === 404 ||
    name === 'NotFound' ||
    name === 'NoSuchKey' ||
    name === 'NotFoundError'
  );
}

function createS3Client(config) {
  return new S3Client({
    region: config.R2_REGION,
    endpoint: config.R2_ENDPOINT,
    credentials: {
      accessKeyId: config.R2_ACCESS_KEY_ID,
      secretAccessKey: config.R2_SECRET_ACCESS_KEY,
    },
  });
}

function createR2Storage(options = {}) {
  const env = options.env || process.env;
  const signUrl = options.signUrl || getSignedUrl;

  let cached = null;
  function context() {
    if (cached) {
      return cached;
    }
    const config = readR2Config(env);
    const client = options.client || createS3Client(config);
    cached = { config, client };
    return cached;
  }

  async function createDirectUpload({ storageKey, contentType }) {
    if (typeof storageKey !== 'string' || storageKey.trim() === '') {
      throw storageNotConfigured();
    }
    const { config, client } = context();
    try {
      const expiresIn = config.uploadTtlSeconds;
      const url = await signUrl(
        client,
        new PutObjectCommand({
          Bucket: config.R2_BUCKET,
          Key: storageKey,
          ContentType: contentType,
        }),
        { expiresIn }
      );
      return {
        method: 'PUT',
        url,
        headers: {
          'Content-Type': contentType,
        },
        expires_at: new Date(Date.now() + expiresIn * 1000).toISOString(),
      };
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      throw storageNotConfigured();
    }
  }

  async function head(storageKey) {
    const { config, client } = context();
    try {
      const result = await client.send(
        new HeadObjectCommand({
          Bucket: config.R2_BUCKET,
          Key: storageKey,
        })
      );
      return {
        byteSize: Number(result.ContentLength),
        contentType: result.ContentType || null,
      };
    } catch (err) {
      if (isAbsentObjectError(err)) {
        return null;
      }
      if (err instanceof AppError) {
        throw err;
      }
      throw storageNotConfigured();
    }
  }

  async function deleteObject(storageKey) {
    const { config, client } = context();
    try {
      await client.send(
        new DeleteObjectCommand({
          Bucket: config.R2_BUCKET,
          Key: storageKey,
        })
      );
    } catch (err) {
      if (isAbsentObjectError(err)) {
        return;
      }
      if (err instanceof AppError) {
        throw err;
      }
      throw storageNotConfigured();
    }
  }

  async function createReadUrl(storageKey) {
    if (typeof storageKey !== 'string' || storageKey.trim() === '') {
      throw storageNotConfigured();
    }
    const { config, client } = context();
    try {
      const expiresIn = config.readTtlSeconds;
      const url = await signUrl(
        client,
        new GetObjectCommand({
          Bucket: config.R2_BUCKET,
          Key: storageKey,
        }),
        { expiresIn }
      );
      return {
        method: 'GET',
        url,
        expires_at: new Date(Date.now() + expiresIn * 1000).toISOString(),
      };
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      throw storageNotConfigured();
    }
  }

  return {
    createDirectUpload,
    head,
    delete: deleteObject,
    createReadUrl,
  };
}

const r2StorageService = createR2Storage();

module.exports = r2StorageService;
module.exports.createR2Storage = createR2Storage;
module.exports.readR2Config = readR2Config;
module.exports.REQUIRED_R2_VARS = REQUIRED_R2_VARS;
