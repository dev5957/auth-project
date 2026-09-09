const AppError = require('../errors/AppError');

const PASSWORD_MIN_LENGTH = 8;
const PASSWORD_MAX_LENGTH = 72;

function isBlankPassword(password) {
  return typeof password !== 'string' || password.length === 0 || password.trim() === '';
}

function validatePasswordForRegistration(password) {
  if (isBlankPassword(password)) {
    throw new AppError(400, 'password is required');
  }

  if (password.length < PASSWORD_MIN_LENGTH || password.length > PASSWORD_MAX_LENGTH) {
    throw new AppError(400, 'Password must be between 8 and 72 characters');
  }

  return password;
}

function preparePasswordForLogin(password) {
  if (isBlankPassword(password)) {
    throw new AppError(400, 'password is required');
  }

  if (password.length > PASSWORD_MAX_LENGTH) {
    throw new AppError(401, 'Invalid credentials');
  }

  return password;
}

module.exports = {
  PASSWORD_MIN_LENGTH,
  PASSWORD_MAX_LENGTH,
  validatePasswordForRegistration,
  preparePasswordForLogin,
};
