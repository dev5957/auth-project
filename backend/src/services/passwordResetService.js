const crypto = require('crypto');
const bcrypt = require('bcrypt');
const pool = require('../db');
const AppError = require('../errors/AppError');
const { validatePasswordForRegistration } = require('../validators/passwordValidator');
const { normalizePhoneNumber } = require('../validators/authFields');
const smsService = require('./smsService');

const BCRYPT_ROUNDS = 10;
const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const COOLDOWN_MS = 60 * 1000;
const DUMMY_PASSWORD_HASH = bcrypt.hashSync('dummy-timing-password', BCRYPT_ROUNDS);
const GENERIC_FORGOT_MESSAGE =
  'If an account exists for this phone number, a reset code has been sent.';
const GENERIC_RESET_ERROR = 'Invalid or expired reset code';
const RESET_SUCCESS_MESSAGE = 'Password has been reset. You can sign in.';

function requiredString(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, `${field} is required`);
  }
  return value.trim();
}

function generateResetCode() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

function isRecoverableLocalAccount(user) {
  return (
    user &&
    user.auth_provider === 'local' &&
    user.phone_verified === true &&
    typeof user.password_hash === 'string' &&
    user.password_hash.length > 0
  );
}

async function dummyCompare(code) {
  const value = typeof code === 'string' && code.length > 0 ? code : '000000';
  await bcrypt.compare(value, DUMMY_PASSWORD_HASH);
}

async function requestPasswordReset(body, deps = {}) {
  const db = deps.db || pool;
  const nowMs = deps.nowMs || Date.now();
  const sendSms = deps.sendSms || smsService.sendSms;
  const createCode = deps.generateCode || generateResetCode;

  const payload = body && typeof body === 'object' ? body : {};
  const phone_number = normalizePhoneNumber(payload.phone_number);

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const found = await db.query(
    `SELECT id, auth_provider, password_hash, phone_verified
     FROM users
     WHERE phone_number = $1
     LIMIT 1`,
    [phone_number]
  );
  const user = found.rows[0];

  if (!isRecoverableLocalAccount(user)) {
    await dummyCompare('000000');
    return { message: GENERIC_FORGOT_MESSAGE };
  }

  const latest = await db.query(
    `SELECT created_at
     FROM password_reset_requests
     WHERE phone_number = $1
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [phone_number]
  );
  const lastCreated = latest.rows[0] && latest.rows[0].created_at;
  if (lastCreated && nowMs - new Date(lastCreated).getTime() < COOLDOWN_MS) {
    return { message: GENERIC_FORGOT_MESSAGE };
  }

  const code = createCode();
  const code_hash = await bcrypt.hash(code, BCRYPT_ROUNDS);
  const expires_at = new Date(nowMs + CODE_TTL_MS);

  await db.query(
    `INSERT INTO password_reset_requests (
       user_id,
       phone_number,
       code_hash,
       expires_at,
       attempts
     ) VALUES ($1, $2, $3, $4, 0)`,
    [user.id, phone_number, code_hash, expires_at]
  );

  if (process.env.DEV_LOG_RESET_CODE === 'true') {
    console.log(`[DEV] Password reset code: ${code}`);
  }

  await sendSms(phone_number, `Your verification code is ${code}`);
  return { message: GENERIC_FORGOT_MESSAGE };
}

function validateResetPayload(body) {
  const payload = body && typeof body === 'object' ? body : {};
  const phone_number = normalizePhoneNumber(payload.phone_number);
  const code = requiredString(payload.code, 'code');
  const password = validatePasswordForRegistration(payload.password);
  if (typeof payload.password_confirmation !== 'string' || payload.password_confirmation === '') {
    throw new AppError(400, 'password_confirmation is required');
  }
  if (payload.password !== payload.password_confirmation) {
    throw new AppError(400, 'password and password_confirmation do not match');
  }
  return { phone_number, code, password };
}

async function confirmPasswordReset(body, deps = {}) {
  const db = deps.db || pool;
  const nowMs = deps.nowMs || Date.now();
  const { phone_number, code, password } = validateResetPayload(body);

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const client = await db.connect();
  let committed = false;

  try {
    await client.query('BEGIN');

    const found = await client.query(
      `SELECT id, user_id, phone_number, code_hash, expires_at, attempts, used_at
       FROM password_reset_requests
       WHERE phone_number = $1 AND used_at IS NULL
       ORDER BY created_at DESC, id DESC
       LIMIT 1
       FOR UPDATE`,
      [phone_number]
    );

    if (found.rowCount === 0) {
      await dummyCompare(code);
      throw new AppError(400, GENERIC_RESET_ERROR);
    }

    const row = found.rows[0];

    if (row.used_at || new Date(row.expires_at).getTime() <= nowMs || row.attempts >= MAX_ATTEMPTS) {
      throw new AppError(400, GENERIC_RESET_ERROR);
    }

    const matches = await bcrypt.compare(code, row.code_hash);
    if (!matches) {
      const nextAttempts = row.attempts + 1;
      await client.query(
        'UPDATE password_reset_requests SET attempts = $1 WHERE id = $2',
        [nextAttempts, row.id]
      );
      await client.query('COMMIT');
      committed = true;
      throw new AppError(400, GENERIC_RESET_ERROR);
    }

    const consumed = await client.query(
      `UPDATE password_reset_requests
       SET used_at = NOW()
       WHERE id = $1 AND used_at IS NULL`,
      [row.id]
    );
    if (consumed.rowCount !== 1) {
      throw new AppError(400, GENERIC_RESET_ERROR);
    }

    const password_hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
    const updated = await client.query(
      `UPDATE users
       SET password_hash = $1, updated_at = NOW()
       WHERE id = $2 AND auth_provider = 'local'`,
      [password_hash, row.user_id]
    );
    if (updated.rowCount !== 1) {
      throw new AppError(400, GENERIC_RESET_ERROR);
    }

    await client.query(
      `UPDATE refresh_tokens
       SET revoked_at = NOW()
       WHERE user_id = $1 AND revoked_at IS NULL`,
      [row.user_id]
    );

    await client.query('COMMIT');
    committed = true;
    return { message: RESET_SUCCESS_MESSAGE };
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // Preserve the original error.
      }
    }
    throw err;
  } finally {
    client.release();
  }
}

module.exports = {
  GENERIC_FORGOT_MESSAGE,
  GENERIC_RESET_ERROR,
  RESET_SUCCESS_MESSAGE,
  CODE_TTL_MS,
  MAX_ATTEMPTS,
  COOLDOWN_MS,
  generateResetCode,
  requestPasswordReset,
  confirmPasswordReset,
};
