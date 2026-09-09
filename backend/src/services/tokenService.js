const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const AppError = require('../errors/AppError');

function hashRefreshToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function generateAccessToken(user) {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new AppError(503, 'JWT_SECRET is not configured');
  }

  const expiresIn = process.env.JWT_EXPIRES_IN || '15m';

  return jwt.sign(
    {
      userId: user.id,
      login: user.login,
      auth_provider: user.auth_provider,
    },
    secret,
    { expiresIn }
  );
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
  generateRefreshToken,
  getRefreshTokenExpiryDate,
  hashRefreshToken,
};
