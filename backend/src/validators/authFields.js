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

// Login is stored and compared in lowercase so "TEST_USER" matches "test_user".
// PostgreSQL UNIQUE(login) remains case-sensitive: mixed-case historical rows
// are not rewritten in this step and would not match a lowercase lookup.
function normalizeLogin(value) {
  const login = requiredTrimmed(value, 'login').toLowerCase();
  if (login.length > LOGIN_MAX_LENGTH) {
    throw new AppError(400, 'login is invalid');
  }
  return login;
}

function prepareLoginForLookup(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, 'login is required');
  }
  const login = value.trim().toLowerCase();
  if (login.length > LOGIN_MAX_LENGTH) {
    throw new AppError(401, 'Invalid credentials');
  }
  return login;
}

// Light phone normalization only: trim, then drop spaces, hyphens and parentheses.
// No country conversion, no default country, no strict E.164 (later step).
function normalizePhoneNumber(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, 'phone_number is required');
  }
  const phone_number = value.trim().replace(/[\s\-()]/g, '');
  if (phone_number === '') {
    throw new AppError(400, 'phone_number is required');
  }
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
