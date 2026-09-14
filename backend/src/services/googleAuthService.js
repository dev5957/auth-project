const { OAuth2Client } = require('google-auth-library');
const AppError = require('../errors/AppError');

const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];
const CLOCK_SKEW_SECONDS = 300;

function readTrimmed(name) {
  const value = process.env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function getGoogleClientId() {
  return readTrimmed('GOOGLE_CLIENT_ID');
}

function isGoogleAuthConfigured() {
  return getGoogleClientId() != null;
}

function createGoogleOAuthClient(clientId = getGoogleClientId()) {
  if (!clientId) {
    throw new AppError(503, 'Google authentication is not configured');
  }
  return new OAuth2Client(clientId);
}

function optionalName(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function assertVerifiedGooglePayload(payload, audience) {
  if (!payload || typeof payload !== 'object') {
    throw new AppError(401, 'Unauthorized');
  }

  if (typeof payload.iss !== 'string' || !GOOGLE_ISSUERS.includes(payload.iss)) {
    throw new AppError(401, 'Unauthorized');
  }

  if (payload.aud !== audience) {
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

  if (typeof payload.email !== 'string' || payload.email.trim() === '') {
    throw new AppError(401, 'Unauthorized');
  }

  return {
    provider_user_id: payload.sub.trim(),
    email: payload.email.trim(),
    first_name: optionalName(payload.given_name),
    last_name: optionalName(payload.family_name),
  };
}

async function verifyGoogleIdToken(idToken, options = {}) {
  if (typeof idToken !== 'string' || idToken.trim() === '') {
    throw new AppError(400, 'id_token is required');
  }

  const clientId = getGoogleClientId();
  if (!clientId) {
    throw new AppError(503, 'Google authentication is not configured');
  }

  const client = options.client || createGoogleOAuthClient(clientId);

  try {
    const ticket = await client.verifyIdToken({
      idToken: idToken.trim(),
      audience: clientId,
    });
    return assertVerifiedGooglePayload(ticket.getPayload(), clientId);
  } catch (err) {
    if (err.statusCode) {
      throw err;
    }
    throw new AppError(401, 'Unauthorized');
  }
}

module.exports = {
  GOOGLE_ISSUERS,
  getGoogleClientId,
  isGoogleAuthConfigured,
  createGoogleOAuthClient,
  verifyGoogleIdToken,
};
