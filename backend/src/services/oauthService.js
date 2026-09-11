const crypto = require('crypto');
const bcrypt = require('bcrypt');
const pool = require('../db');
const AppError = require('../errors/AppError');
const { normalizeEmail, normalizePhoneNumber } = require('../validators/authFields');
const smsService = require('./smsService');

const BCRYPT_ROUNDS = 10;
const OAUTH_TTL_MS = 10 * 60 * 1000;
const CODE_TTL_MS = 10 * 60 * 1000;
const PENDING_PHONE_PLACEHOLDER = 'oauth-pending';
const OAUTH_PROVIDERS = new Set(['google', 'apple']);

function requiredString(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, `${field} is required`);
  }
  return value.trim();
}

function generateOauthVerificationToken() {
  return crypto.randomBytes(32).toString('hex');
}

function generateSmsCode() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

function optionalName(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function parseOauthContext(data, { requirePhone = false } = {}) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new AppError(400, 'Verification is no longer valid');
  }

  if (data.password_hash) {
    throw new AppError(400, 'Verification is no longer valid');
  }

  if (!OAUTH_PROVIDERS.has(data.provider)) {
    throw new AppError(400, 'Verification is no longer valid');
  }

  if (typeof data.provider_user_id !== 'string' || data.provider_user_id.trim() === '') {
    throw new AppError(400, 'Verification is no longer valid');
  }

  const email = normalizeEmail(data.email);
  const first_name = optionalName(data.first_name);
  const last_name = optionalName(data.last_name);
  let phone_number = null;
  if (requirePhone || (typeof data.phone_number === 'string' && data.phone_number.trim() !== '')) {
    phone_number = normalizePhoneNumber(data.phone_number);
  }

  return {
    provider: data.provider,
    provider_user_id: data.provider_user_id.trim(),
    email,
    first_name,
    last_name,
    phone_number,
  };
}

function prepareOauthUserDraft(context) {
  return {
    email: context.email,
    phone_number: context.phone_number,
    phone_verified: true,
    password_hash: null,
    auth_provider: context.provider,
    provider_user_id: context.provider_user_id,
    first_name: context.first_name,
    last_name: context.last_name,
  };
}

function assertDatabaseConfigured(options) {
  if (!options.db && !process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

async function createPendingOauthContext(input, options = {}) {
  assertDatabaseConfigured(options);
  const db = options.db || pool;

  const context = parseOauthContext(
    {
      provider: input.provider,
      provider_user_id: input.provider_user_id,
      email: input.email,
      first_name: input.first_name,
      last_name: input.last_name,
    },
    { requirePhone: false }
  );

  const oauth_verification_token = generateOauthVerificationToken();
  const placeholderHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), BCRYPT_ROUNDS);
  const expires_at = new Date(Date.now() + OAUTH_TTL_MS);

  await db.query(
    `INSERT INTO phone_verifications (
       verification_token,
       phone_number,
       code_hash,
       expires_at,
       attempts,
       registration_data
     ) VALUES ($1, $2, $3, $4, 0, $5)`,
    [
      oauth_verification_token,
      PENDING_PHONE_PLACEHOLDER,
      placeholderHash,
      expires_at,
      {
        provider: context.provider,
        provider_user_id: context.provider_user_id,
        email: context.email,
        first_name: context.first_name,
        last_name: context.last_name,
      },
    ]
  );

  return {
    oauth_verification_token,
    email: context.email,
  };
}

async function startOAuthPhoneVerification(body, options = {}) {
  const payload = body && typeof body === 'object' ? body : {};
  const oauth_verification_token = requiredString(
    payload.oauth_verification_token,
    'oauth_verification_token'
  );
  const phone_number = normalizePhoneNumber(payload.phone_number);

  assertDatabaseConfigured(options);
  const db = options.db || pool;
  const sendSms = options.sendSms || smsService.sendSms;
  const generateCode = options.generateSmsCode || generateSmsCode;

  const smsCode = generateCode();
  const code_hash = await bcrypt.hash(smsCode, BCRYPT_ROUNDS);
  const expires_at = new Date(Date.now() + CODE_TTL_MS);

  const client = await db.connect();
  let committed = false;
  let storedContext = null;

  try {
    await client.query('BEGIN');

    const found = await client.query(
      `SELECT id, expires_at, verified_at, registration_data
       FROM phone_verifications
       WHERE verification_token = $1
       FOR UPDATE`,
      [oauth_verification_token]
    );

    if (found.rowCount === 0) {
      throw new AppError(404, 'Verification token not found');
    }

    const row = found.rows[0];
    if (row.verified_at) {
      throw new AppError(400, 'Verification is no longer valid');
    }
    if (new Date(row.expires_at).getTime() <= Date.now()) {
      throw new AppError(400, 'Verification is no longer valid');
    }

    const context = parseOauthContext(row.registration_data, { requirePhone: false });

    const taken = await client.query(
      `SELECT EXISTS (SELECT 1 FROM users WHERE phone_number = $1) AS phone_taken`,
      [phone_number]
    );
    if (taken.rows[0] && taken.rows[0].phone_taken) {
      throw new AppError(409, 'Phone number is already in use');
    }

    storedContext = {
      provider: context.provider,
      provider_user_id: context.provider_user_id,
      email: context.email,
      first_name: context.first_name,
      last_name: context.last_name,
      phone_number,
    };

    const updated = await client.query(
      `UPDATE phone_verifications
       SET phone_number = $1,
           code_hash = $2,
           expires_at = $3,
           attempts = 0,
           registration_data = $4
       WHERE id = $5
         AND verified_at IS NULL`,
      [phone_number, code_hash, expires_at, storedContext, row.id]
    );
    if (updated.rowCount !== 1) {
      throw new AppError(400, 'Verification is no longer valid');
    }

    await client.query('COMMIT');
    committed = true;
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

  // Log the plaintext SMS code only when DEV_LOG_SMS_CODE=true is set explicitly.
  // Default is off. Never persist the plaintext code. Never log hashes or tokens.
  if (process.env.DEV_LOG_SMS_CODE === 'true') {
    console.log('[DEV] SMS verification code:', smsCode);
  }

  await sendSms(phone_number, `Your verification code is ${smsCode}`);

  return {
    message: 'Verification code generated',
    oauth_verification_token,
  };
}

module.exports = {
  PENDING_PHONE_PLACEHOLDER,
  OAUTH_TTL_MS,
  CODE_TTL_MS,
  generateOauthVerificationToken,
  generateSmsCode,
  parseOauthContext,
  prepareOauthUserDraft,
  createPendingOauthContext,
  startOAuthPhoneVerification,
};
