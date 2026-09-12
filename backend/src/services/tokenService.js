const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const {
  getJwtSecret,
  getJwtIssuer,
  getJwtAudience,
  getJwtExpiresIn,
} = require('../config/authConfig');

function hashRefreshToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function generateAccessToken(user) {
  const secret = getJwtSecret();
  const issuer = getJwtIssuer();
  const audience = getJwtAudience();
  const expiresIn = getJwtExpiresIn();

  return jwt.sign(
    {
      userId: user.id,
      login: user.login,
      auth_provider: user.auth_provider,
    },
    secret,
    {
      expiresIn,
      algorithm: 'HS256',
      issuer,
      audience,
      jwtid: crypto.randomUUID(),
    }
  );
}

function verifyAccessToken(token) {
  const payload = jwt.verify(token, getJwtSecret(), {
    algorithms: ['HS256'],
    issuer: getJwtIssuer(),
    audience: getJwtAudience(),
  });

  if (
    payload == null ||
    typeof payload !== 'object' ||
    typeof payload.exp !== 'number' ||
    payload.userId == null ||
    typeof payload.login !== 'string' ||
    typeof payload.auth_provider !== 'string'
  ) {
    const err = new Error('Invalid access token');
    err.name = 'JsonWebTokenError';
    throw err;
  }

  return payload;
}

function generateRefreshToken() {
  const token = crypto.randomBytes(32).toString('hex');
  return {
    token,
    token_hash: hashRefreshToken(token),
  };
}

function getRefreshTokenExpiryDate() {
  const days = Number(process.env.REFRESH_TOKEN_EXPIRES_DAYS || 90);
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
}

module.exports = {
  generateAccessToken,
  verifyAccessToken,
  generateRefreshToken,
  getRefreshTokenExpiryDate,
  hashRefreshToken,
};
