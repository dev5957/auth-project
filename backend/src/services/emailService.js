const AppError = require('../errors/AppError');

function readTrimmed(name) {
  const value = process.env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function getEmailProvider() {
  const raw = readTrimmed('EMAIL_PROVIDER');
  if (raw == null) {
    return 'none';
  }
  return raw.toLowerCase();
}

function maskEmail(email) {
  const value = String(email || '');
  const at = value.indexOf('@');
  if (at <= 1) {
    return '***';
  }
  return `${value.slice(0, 1)}***${value.slice(at)}`;
}

async function sendResetEmail(email, _code) {
  if (typeof email !== 'string' || email.trim() === '') {
    throw new AppError(503, 'Email could not be sent');
  }

  const provider = getEmailProvider();
  if (provider === 'mock') {
    return { skipped: false, mocked: true };
  }
  if (provider === 'none') {
    return { skipped: true };
  }

  throw new AppError(503, 'Email could not be sent');
}

module.exports = {
  sendResetEmail,
  getEmailProvider,
  maskEmail,
};
