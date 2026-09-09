const AppError = require('../errors/AppError');

const LOGIN_MAX_LENGTH = 64;
const EMAIL_MAX_LENGTH = 254;
const PHONE_MAX_LENGTH = 32;

function requiredTrimmed(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, `${field} is required`);
  }
  return value.trim();
}

function normalizeEmail(value) {
  const email = requiredTrimmed(value, 'email').toLowerCase();
  if (email.length > EMAIL_MAX_LENGTH) {
    throw new AppError(400, 'email is invalid');
  }
  return email;
}

function normalizeLogin(value) {
  const login = requiredTrimmed(value, 'login');
  if (login.length > LOGIN_MAX_LENGTH) {
    throw new AppError(400, 'login is invalid');
  }
  return login;
}

function prepareLoginForLookup(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, 'login is required');
  }
  const login = value.trim();
  if (login.length > LOGIN_MAX_LENGTH) {
    throw new AppError(401, 'Invalid credentials');
  }
  return login;
}

function normalizePhoneNumber(value) {
  const phone_number = requiredTrimmed(value, 'phone_number');
  if (phone_number.length > PHONE_MAX_LENGTH) {
    throw new AppError(400, 'phone_number is invalid');
  }
  return phone_number;
}

module.exports = {
  LOGIN_MAX_LENGTH,
  EMAIL_MAX_LENGTH,
  PHONE_MAX_LENGTH,
  normalizeEmail,
  normalizeLogin,
  prepareLoginForLookup,
  normalizePhoneNumber,
};
