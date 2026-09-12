const { verifyAccessToken } = require('../services/tokenService');
const AppError = require('../errors/AppError');

function unauthorized() {
  return new AppError(401, 'Unauthorized');
}

function readBearerToken(header) {
  if (typeof header !== 'string' || header.trim() === '') {
    return null;
  }

  const match = header.trim().match(/^Bearer\s+(\S+)$/);
  if (!match) {
    return null;
  }

  return match[1];
}

function requireAuth(req, res, next) {
  try {
    const token = readBearerToken(req.headers.authorization);
    if (!token) {
      throw unauthorized();
    }

    let payload;
    try {
      payload = verifyAccessToken(token);
    } catch (err) {
      if (err.statusCode) {
        throw err;
      }
      throw unauthorized();
    }

    req.user = {
      userId: payload.userId,
      login: payload.login,
      auth_provider: payload.auth_provider,
    };

    next();
  } catch (err) {
    next(err);
  }
}

module.exports = {
  requireAuth,
};
