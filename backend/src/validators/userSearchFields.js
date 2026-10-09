const AppError = require('../errors/AppError');
const { normalizeLogin, normalizePhoneNumber } = require('./authFields');

function hasOwn(query, field) {
  return query != null && typeof query === 'object' && Object.prototype.hasOwnProperty.call(query, field);
}

function parseUserSearchQuery(query) {
  const raw = query && typeof query === 'object' && !Array.isArray(query) ? query : {};
  const hasLogin = hasOwn(raw, 'login');
  const hasPhone = hasOwn(raw, 'phone');

  if (hasLogin && hasPhone) {
    throw new AppError(400, 'login and phone cannot both be set');
  }
  if (!hasLogin && !hasPhone) {
    throw new AppError(400, 'login or phone is required');
  }

  if (hasLogin) {
    if (typeof raw.login !== 'string') {
      throw new AppError(400, 'login is invalid');
    }
    return { kind: 'login', login: normalizeLogin(raw.login) };
  }

  if (typeof raw.phone !== 'string') {
    throw new AppError(400, 'phone_number is invalid');
  }
  return { kind: 'phone', phone: normalizePhoneNumber(raw.phone) };
}

module.exports = {
  parseUserSearchQuery,
};
