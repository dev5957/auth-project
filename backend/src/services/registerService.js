const crypto = require('crypto');
const bcrypt = require('bcrypt');
const pool = require('../db');
const AppError = require('../errors/AppError');

const BCRYPT_ROUNDS = 10;
const CODE_TTL_MS = 10 * 60 * 1000;

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

  const email = requiredString(payload.email, 'email');
  const birth_date = requiredString(payload.birth_date, 'birth_date');
  const login = requiredString(payload.login, 'login');
  const phone_number = requiredString(payload.phone_number, 'phone_number');

  if (typeof payload.password !== 'string' || payload.password === '') {
    throw new AppError(400, 'password is required');
  }
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
    password: payload.password,
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

  // DEV only: log the SMS code until a real SMS provider is wired in.
  // This must be replaced by an SMS provider later. Never persist the plaintext code.
  if (process.env.NODE_ENV !== 'production') {
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

module.exports = {
  startLocalRegistration,
};
