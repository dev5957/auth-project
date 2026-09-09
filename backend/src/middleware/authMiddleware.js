const jwt = require('jsonwebtoken');
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

    const secret = process.env.JWT_SECRET;
    if (!secret) {
      throw new AppError(503, 'JWT_SECRET is not configured');
    }

    let payload;
    try {
      payload = jwt.verify(token, secret, { algorithms: ['HS256'] });
    } catch (_) {
      throw unauthorized();
    }

    if (
      payload == null ||
      typeof payload !== 'object' ||
      payload.userId == null ||
      typeof payload.login !== 'string' ||
      typeof payload.auth_provider !== 'string'
    ) {
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
