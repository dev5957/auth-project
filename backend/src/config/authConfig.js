const AppError = require('../errors/AppError');

const JWT_SECRET_MIN_LENGTH = 16;
const DEFAULT_JWT_EXPIRES_IN = '15m';
const DEFAULT_REFRESH_TOKEN_EXPIRES_DAYS = 90;
const MAX_ACCESS_TOKEN_MS = 24 * 60 * 60 * 1000;
const MIN_REFRESH_DAYS = 1;
const MAX_REFRESH_DAYS = 365;

function readTrimmed(name) {
  const value = process.env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function parseExpiresIn(value) {
  if (value == null) {
    return null;
  }
  const raw = String(value).trim();
  if (/^\d+$/.test(raw)) {
    const seconds = Number(raw);
    if (!Number.isInteger(seconds) || seconds <= 0) {
      return null;
    }
    return seconds * 1000;
  }

  const match = raw.match(/^(\d+)(s|m|h|d)$/);
  if (!match) {
    return null;
  }
  const amount = Number(match[1]);
  if (!Number.isInteger(amount) || amount <= 0) {
    return null;
  }
  const unitMs = { s: 1000, m: 60 * 1000, h: 60 * 60 * 1000, d: 24 * 60 * 60 * 1000 };
  return amount * unitMs[match[2]];
}

function parseRefreshDays(value) {
  if (value == null || String(value).trim() === '') {
    return null;
  }
  const days = Number(value);
  if (!Number.isInteger(days)) {
    return null;
  }
  return days;
}

function getJwtSecret() {
  const secret = readTrimmed('JWT_SECRET');
  if (!secret) {
    throw new AppError(503, 'JWT_SECRET is not configured');
  }
  return secret;
}

function getJwtIssuer() {
  const issuer = readTrimmed('JWT_ISSUER');
  if (!issuer) {
    throw new AppError(503, 'JWT is not configured');
  }
  return issuer;
}

function getJwtAudience() {
  const audience = readTrimmed('JWT_AUDIENCE');
  if (!audience) {
    throw new AppError(503, 'JWT is not configured');
  }
  return audience;
}

function getJwtExpiresIn() {
  return readTrimmed('JWT_EXPIRES_IN') || DEFAULT_JWT_EXPIRES_IN;
}

function collectAuthConfigErrors() {
  const errors = [];

  const secret = readTrimmed('JWT_SECRET');
  if (!secret) {
    errors.push('JWT_SECRET is missing');
  } else if (secret.length < JWT_SECRET_MIN_LENGTH) {
    errors.push('JWT_SECRET is too short');
  }

  if (!readTrimmed('JWT_ISSUER')) {
    errors.push('JWT_ISSUER is missing');
  }
  if (!readTrimmed('JWT_AUDIENCE')) {
    errors.push('JWT_AUDIENCE is missing');
  }

  const expiresMs = parseExpiresIn(process.env.JWT_EXPIRES_IN || DEFAULT_JWT_EXPIRES_IN);
  if (!expiresMs || expiresMs > MAX_ACCESS_TOKEN_MS) {
    errors.push('JWT_EXPIRES_IN is invalid');
  }

  const days = parseRefreshDays(
    process.env.REFRESH_TOKEN_EXPIRES_DAYS || String(DEFAULT_REFRESH_TOKEN_EXPIRES_DAYS)
  );
  if (days == null || days < MIN_REFRESH_DAYS || days > MAX_REFRESH_DAYS) {
    errors.push('REFRESH_TOKEN_EXPIRES_DAYS is invalid');
  }

  return errors;
}

function assertAuthConfig() {
  const errors = collectAuthConfigErrors();
  if (errors.length === 0) {
    return;
  }

  console.error('Invalid auth configuration:', errors.join('; '));
  const err = new Error('Invalid auth configuration');
  err.name = 'AuthConfigError';
  throw err;
}

module.exports = {
  JWT_SECRET_MIN_LENGTH,
  DEFAULT_JWT_EXPIRES_IN,
  DEFAULT_REFRESH_TOKEN_EXPIRES_DAYS,
  getJwtSecret,
  getJwtIssuer,
  getJwtAudience,
  getJwtExpiresIn,
  collectAuthConfigErrors,
  assertAuthConfig,
};
