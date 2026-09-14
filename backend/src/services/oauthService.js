const crypto = require('crypto');
const bcrypt = require('bcrypt');
const pool = require('../db');
const AppError = require('../errors/AppError');
const { normalizeEmail, normalizeLogin, normalizePhoneNumber } = require('../validators/authFields');
const smsService = require('./smsService');
const {
  generateAccessToken,
  generateRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const { storeLoginRefreshToken } = require('./refreshSessionService');

const BCRYPT_ROUNDS = 10;
const OAUTH_TTL_MS = 10 * 60 * 1000;
const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const PENDING_PHONE_PLACEHOLDER = 'oauth-pending';
const OAUTH_PROVIDERS = new Set(['google', 'apple']);
const EMAIL_PROVIDER_CONFLICT =
  'Account already exists with another authentication method';

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

function validateBirthDate(value) {
  const birth_date = requiredString(value, 'birth_date');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birth_date)) {
    throw new AppError(400, 'birth_date is invalid');
  }
  const year = Number(birth_date.slice(0, 4));
  const month = Number(birth_date.slice(5, 7));
  const day = Number(birth_date.slice(8, 10));
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() + 1 !== month ||
    parsed.getUTCDate() !== day
  ) {
    throw new AppError(400, 'birth_date is invalid');
  }
  return birth_date;
}

function validateOAuthVerifyPayload(body) {
  const payload = body && typeof body === 'object' ? body : {};
  const oauth_verification_token = requiredString(
    payload.oauth_verification_token,
    'oauth_verification_token'
  );
  if (typeof payload.code !== 'string' || payload.code.trim() === '') {
    throw new AppError(400, 'code is required');
  }
  return {
    oauth_verification_token,
    code: payload.code.trim(),
    birth_date: validateBirthDate(payload.birth_date),
    login: normalizeLogin(payload.login),
  };
}

async function issueSession(user, executor) {
  const access_token = generateAccessToken(user);
  const { token: refresh_token, token_hash } = generateRefreshToken();
  const expires_at = getRefreshTokenExpiryDate();
  await storeLoginRefreshToken(user.id, token_hash, expires_at, executor);
  return { access_token, refresh_token };
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

async function verifyOAuthPhoneAndCreateUser(body, options = {}) {
  const { oauth_verification_token, code, birth_date, login } = validateOAuthVerifyPayload(body);

  assertDatabaseConfigured(options);
  if (!process.env.JWT_SECRET) {
    throw new AppError(503, 'JWT_SECRET is not configured');
  }

  const db = options.db || pool;
  const client = await db.connect();
  let committed = false;

  try {
    await client.query('BEGIN');

    const found = await client.query(
      `SELECT id, code_hash, expires_at, attempts, verified_at, registration_data
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
      throw new AppError(400, 'Verification code has expired');
    }
    if (row.attempts >= MAX_ATTEMPTS) {
      throw new AppError(429, 'Too many verification attempts');
    }

    const matches = await bcrypt.compare(code, row.code_hash);
    if (!matches) {
      const nextAttempts = row.attempts + 1;
      await client.query(
        'UPDATE phone_verifications SET attempts = $1 WHERE id = $2',
        [nextAttempts, row.id]
      );
      await client.query('COMMIT');
      committed = true;

      if (nextAttempts >= MAX_ATTEMPTS) {
        throw new AppError(429, 'Too many verification attempts');
      }
      throw new AppError(400, 'Invalid verification code');
    }

    const context = parseOauthContext(row.registration_data, { requirePhone: false });
    if (!context.phone_number) {
      throw new AppError(400, 'Verification is no longer valid');
    }

    const uniqueness = await client.query(
      `SELECT
         (SELECT auth_provider FROM users WHERE email = $1 LIMIT 1) AS email_provider,
         EXISTS (SELECT 1 FROM users WHERE login = $2) AS login_taken,
         EXISTS (SELECT 1 FROM users WHERE phone_number = $3) AS phone_taken,
         EXISTS (
           SELECT 1 FROM users
           WHERE auth_provider = $4
             AND provider_user_id = $5
         ) AS provider_taken`,
      [context.email, login, context.phone_number, context.provider, context.provider_user_id]
    );
    const flags = uniqueness.rows[0] || {};
    if (flags.login_taken) {
      throw new AppError(409, 'Login is already in use');
    }
    if (flags.email_provider) {
      if (flags.email_provider !== context.provider) {
        throw new AppError(409, EMAIL_PROVIDER_CONFLICT);
      }
      throw new AppError(409, 'Email is already in use');
    }
    if (flags.phone_taken) {
      throw new AppError(409, 'Phone number is already in use');
    }
    if (flags.provider_taken) {
      throw new AppError(409, EMAIL_PROVIDER_CONFLICT);
    }

    const draft = prepareOauthUserDraft(context);
    const inserted = await client.query(
      `INSERT INTO users (
         email,
         birth_date,
         phone_number,
         phone_verified,
         login,
         password_hash,
         auth_provider,
         provider_user_id,
         first_name,
         last_name
       ) VALUES ($1, $2, $3, TRUE, $4, NULL, $5, $6, $7, $8)
       RETURNING id, login, email, auth_provider, provider_user_id, phone_verified, password_hash`,
      [
        draft.email,
        birth_date,
        draft.phone_number,
        login,
        draft.auth_provider,
        draft.provider_user_id,
        draft.first_name,
        draft.last_name,
      ]
    );

    const user = inserted.rows[0];
    if (!user || user.password_hash != null) {
      throw new AppError(500, 'Internal server error');
    }

    const consumed = await client.query(
      `UPDATE phone_verifications
       SET verified_at = NOW()
       WHERE id = $1
         AND verified_at IS NULL`,
      [row.id]
    );
    if (consumed.rowCount !== 1) {
      throw new AppError(400, 'Verification is no longer valid');
    }

    const tokens = await issueSession(user, client);
    await client.query('COMMIT');
    committed = true;

    return {
      message: 'Account created',
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
    };
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // Preserve the original error.
      }
    }

    if (err.code === '23505') {
      const constraint = String(err.constraint || '');
      if (constraint.includes('login')) {
        throw new AppError(409, 'Login is already in use');
      }
      if (constraint.includes('phone')) {
        throw new AppError(409, 'Phone number is already in use');
      }
      if (constraint.includes('email') || constraint.includes('provider_user_id')) {
        throw new AppError(409, EMAIL_PROVIDER_CONFLICT);
      }
      throw new AppError(409, 'Email, login or phone number is already in use');
    }

    throw err;
  } finally {
    client.release();
  }
}

module.exports = {
  PENDING_PHONE_PLACEHOLDER,
  EMAIL_PROVIDER_CONFLICT,
  OAUTH_TTL_MS,
  CODE_TTL_MS,
  generateOauthVerificationToken,
  generateSmsCode,
  parseOauthContext,
  prepareOauthUserDraft,
  createPendingOauthContext,
  startOAuthPhoneVerification,
  verifyOAuthPhoneAndCreateUser,
};
