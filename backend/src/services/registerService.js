const crypto = require('crypto');
const bcrypt = require('bcrypt');
const pool = require('../db');
const AppError = require('../errors/AppError');
const { validatePasswordForRegistration } = require('../validators/passwordValidator');
const {
  normalizeEmail,
  normalizeLogin,
  normalizePhoneNumber,
} = require('../validators/authFields');

const BCRYPT_ROUNDS = 10;
const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;

function requiredString(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, `${field} is required`);
  }
  return value.trim();
}

function optionalName(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new AppError(400, 'first_name and last_name must be strings when provided');
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function validateStartPayload(body) {
  const payload = body && typeof body === 'object' ? body : {};

  const email = normalizeEmail(payload.email);
  const birth_date = requiredString(payload.birth_date, 'birth_date');
  const login = normalizeLogin(payload.login);
  const phone_number = normalizePhoneNumber(payload.phone_number);
  const password = validatePasswordForRegistration(payload.password);
  if (typeof payload.password_confirmation !== 'string' || payload.password_confirmation === '') {
    throw new AppError(400, 'password_confirmation is required');
  }
  if (payload.password !== payload.password_confirmation) {
    throw new AppError(400, 'password and password_confirmation do not match');
  }

  return {
    email,
    birth_date,
    login,
    password,
    phone_number,
    first_name: optionalName(payload.first_name),
    last_name: optionalName(payload.last_name),
  };
}

async function assertUniqueInUsers({ email, login, phone_number }) {
  const result = await pool.query(
    `SELECT
       EXISTS (SELECT 1 FROM users WHERE email = $1) AS email_taken,
       EXISTS (SELECT 1 FROM users WHERE login = $2) AS login_taken,
       EXISTS (SELECT 1 FROM users WHERE phone_number = $3) AS phone_taken`,
    [email, login, phone_number]
  );

  const row = result.rows[0];
  if (row.email_taken) {
    throw new AppError(409, 'Email is already in use');
  }
  if (row.login_taken) {
    throw new AppError(409, 'Login is already in use');
  }
  if (row.phone_taken) {
    throw new AppError(409, 'Phone number is already in use');
  }
}

function generateSmsCode() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

function generateVerificationToken() {
  return crypto.randomBytes(32).toString('hex');
}

async function startLocalRegistration(body) {
  const data = validateStartPayload(body);

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  await assertUniqueInUsers(data);

  const password_hash = await bcrypt.hash(data.password, BCRYPT_ROUNDS);
  const smsCode = generateSmsCode();
  const code_hash = await bcrypt.hash(smsCode, BCRYPT_ROUNDS);
  const verification_token = generateVerificationToken();
  const expires_at = new Date(Date.now() + CODE_TTL_MS);

  // Log the plaintext SMS code only when DEV_LOG_SMS_CODE=true is set explicitly.
  // Default is off. This must be replaced by an SMS provider later.
  // Never persist the plaintext code. Never log password, hashes, or tokens.
  if (process.env.DEV_LOG_SMS_CODE === 'true') {
    console.log('[DEV] SMS verification code (replace with SMS provider):', smsCode);
  }

  await pool.query(
    `INSERT INTO phone_verifications (
       verification_token,
       phone_number,
       code_hash,
       expires_at,
       attempts,
       registration_data
     ) VALUES ($1, $2, $3, $4, 0, $5)`,
    [
      verification_token,
      data.phone_number,
      code_hash,
      expires_at,
      {
        email: data.email,
        birth_date: data.birth_date,
        phone_number: data.phone_number,
        login: data.login,
        password_hash,
        first_name: data.first_name,
        last_name: data.last_name,
      },
    ]
  );

  return { verification_token };
}

function validateVerifyPayload(body) {
  const payload = body && typeof body === 'object' ? body : {};
  const verification_token = requiredString(payload.verification_token, 'verification_token');

  if (typeof payload.code !== 'string' || payload.code.trim() === '') {
    throw new AppError(400, 'code is required');
  }

  return {
    verification_token,
    code: payload.code.trim(),
  };
}

async function verifyPhoneAndCreateUser(body) {
  const { verification_token, code } = validateVerifyPayload(body);

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const client = await pool.connect();
  let committed = false;

  try {
    await client.query('BEGIN');

    const found = await client.query(
      `SELECT id, code_hash, expires_at, attempts, verified_at, registration_data
       FROM phone_verifications
       WHERE verification_token = $1
       FOR UPDATE`,
      [verification_token]
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

    const data = row.registration_data;
    if (!data || typeof data !== 'object') {
      throw new AppError(400, 'Registration data is missing');
    }

    if (!data.birth_date || !data.password_hash) {
      throw new AppError(400, 'Registration data is incomplete');
    }

    const email = normalizeEmail(data.email);
    const login = normalizeLogin(data.login);
    const phone_number = normalizePhoneNumber(data.phone_number);
    const birth_date = data.birth_date;
    const password_hash = data.password_hash;
    const first_name = data.first_name ?? null;
    const last_name = data.last_name ?? null;

    const taken = await client.query(
      `SELECT
         EXISTS (SELECT 1 FROM users WHERE email = $1) AS email_taken,
         EXISTS (SELECT 1 FROM users WHERE login = $2) AS login_taken,
         EXISTS (SELECT 1 FROM users WHERE phone_number = $3) AS phone_taken`,
      [email, login, phone_number]
    );
    const flags = taken.rows[0];
    if (flags.email_taken) {
      throw new AppError(409, 'Email is already in use');
    }
    if (flags.login_taken) {
      throw new AppError(409, 'Login is already in use');
    }
    if (flags.phone_taken) {
      throw new AppError(409, 'Phone number is already in use');
    }

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
       ) VALUES ($1, $2, $3, TRUE, $4, $5, 'local', NULL, $6, $7)
       RETURNING id, email, login, phone_verified, auth_provider`,
      [email, birth_date, phone_number, login, password_hash, first_name, last_name]
    );

    await client.query('DELETE FROM phone_verifications WHERE id = $1', [row.id]);
    await client.query('COMMIT');
    committed = true;

    return inserted.rows[0];
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // Ignore rollback errors so the original error is preserved.
      }
    }

    if (err.code === '23505') {
      throw new AppError(409, 'Email, login or phone number is already in use');
    }

    throw err;
  } finally {
    client.release();
  }
}

module.exports = {
  startLocalRegistration,
  verifyPhoneAndCreateUser,
};
