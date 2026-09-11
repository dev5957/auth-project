const { OAuth2Client } = require('google-auth-library');
const AppError = require('../errors/AppError');

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
    const payload = ticket.getPayload();
    if (!payload || typeof payload.sub !== 'string' || payload.sub.trim() === '') {
      throw new AppError(401, 'Unauthorized');
    }
    return payload;
  } catch (err) {
    if (err.statusCode) {
      throw err;
    }
    throw new AppError(401, 'Unauthorized');
  }
}

module.exports = {
  getGoogleClientId,
  isGoogleAuthConfigured,
  createGoogleOAuthClient,
  verifyGoogleIdToken,
};
