const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const AppError = require('../errors/AppError');

const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const CLOCK_SKEW_SECONDS = 300;
const JWKS_CACHE_MS = 60 * 60 * 1000;

let jwksCache = {
  keys: null,
  expiresAt: 0,
};

function readTrimmed(name) {
  const value = process.env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function getAppleClientIds() {
  const raw = readTrimmed('APPLE_CLIENT_ID');
  if (!raw) {
    return [];
  }
  return raw
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value !== '');
}

function getAppleClientId() {
  const ids = getAppleClientIds();
  return ids.length > 0 ? ids[0] : null;
}

function isAppleAuthConfigured() {
  return getAppleClientIds().length > 0;
}

function optionalName(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function optionalEmail(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function decodeProtectedHeader(identityToken) {
  const segments = identityToken.split('.');
  if (segments.length !== 3) {
    throw new Error('Invalid Apple identity token format');
  }
  const padded = segments[0] + '='.repeat((4 - (segments[0].length % 4)) % 4);
  const header = JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
  if (!header || typeof header !== 'object') {
    throw new Error('Invalid Apple identity token header');
  }
  return header;
}

function parseCacheTtlMs(cacheControl) {
  if (typeof cacheControl !== 'string') {
    return JWKS_CACHE_MS;
  }
  const match = /max-age=(\d+)/i.exec(cacheControl);
  if (!match) {
    return JWKS_CACHE_MS;
  }
  const seconds = Number(match[1]);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return JWKS_CACHE_MS;
  }
  return Math.min(seconds * 1000, JWKS_CACHE_MS);
}

async function fetchAppleJwks() {
  const now = Date.now();
  if (jwksCache.keys && now < jwksCache.expiresAt) {
    return jwksCache.keys;
  }

  const response = await fetch(APPLE_JWKS_URL);
  if (!response.ok) {
    throw new Error('Failed to retrieve Apple signing keys');
  }
  const data = await response.json();
  if (!data || !Array.isArray(data.keys) || data.keys.length === 0) {
    throw new Error('Failed to retrieve Apple signing keys');
  }

  const ttl = parseCacheTtlMs(response.headers.get && response.headers.get('cache-control'));
  jwksCache = {
    keys: data.keys,
    expiresAt: Date.now() + ttl,
  };
  return jwksCache.keys;
}

async function defaultGetSigningKey(kid) {
  if (typeof kid !== 'string' || kid.trim() === '') {
    throw new Error('Missing Apple signing key id');
  }

  let keys = await fetchAppleJwks();
  let jwk = keys.find((key) => key && key.kid === kid);
  if (!jwk) {
    jwksCache = { keys: null, expiresAt: 0 };
    keys = await fetchAppleJwks();
    jwk = keys.find((key) => key && key.kid === kid);
  }
  if (!jwk) {
    throw new Error('Unknown Apple signing key');
  }

  return crypto.createPublicKey({ key: jwk, format: 'jwk' });
}

function assertVerifiedApplePayload(payload, audiences) {
  if (!payload || typeof payload !== 'object') {
    throw new AppError(401, 'Unauthorized');
  }

  if (payload.iss !== APPLE_ISSUER) {
    throw new AppError(401, 'Unauthorized');
  }

  if (!audiences.includes(payload.aud)) {
    throw new AppError(401, 'Unauthorized');
  }

  const exp = Number(payload.exp);
  if (!Number.isFinite(exp)) {
    throw new AppError(401, 'Unauthorized');
  }
  const nowSeconds = Date.now() / 1000;
  if (nowSeconds > exp + CLOCK_SKEW_SECONDS) {
    throw new AppError(401, 'Unauthorized');
  }

  if (typeof payload.sub !== 'string' || payload.sub.trim() === '') {
    throw new AppError(401, 'Unauthorized');
  }

  return {
    provider_user_id: payload.sub.trim(),
    email: optionalEmail(payload.email),
    first_name: optionalName(payload.given_name),
    last_name: optionalName(payload.family_name),
  };
}

async function verifyAppleIdentityToken(identityToken, options = {}) {
  if (typeof identityToken !== 'string' || identityToken.trim() === '') {
    throw new AppError(400, 'identity_token is required');
  }

  const audiences = getAppleClientIds();
  if (audiences.length === 0) {
    throw new AppError(503, 'Apple authentication is not configured');
  }

  const token = identityToken.trim();
  const getSigningKey = options.getSigningKey || defaultGetSigningKey;

  try {
    const header = decodeProtectedHeader(token);
    const signingKey = await getSigningKey(header.kid);
    const payload = jwt.verify(token, signingKey, {
      algorithms: ['RS256'],
      issuer: APPLE_ISSUER,
      audience: audiences.length === 1 ? audiences[0] : audiences,
      clockTolerance: CLOCK_SKEW_SECONDS,
    });
    return assertVerifiedApplePayload(payload, audiences);
  } catch (err) {
    if (err.statusCode) {
      throw err;
    }
    throw new AppError(401, 'Unauthorized');
  }
}

module.exports = {
  APPLE_ISSUER,
  APPLE_JWKS_URL,
  CLOCK_SKEW_SECONDS,
  getAppleClientId,
  getAppleClientIds,
  isAppleAuthConfigured,
  verifyAppleIdentityToken,
};
