const bcrypt = require('bcrypt');
const pool = require('../db');
const AppError = require('../errors/AppError');
const {
  generateAccessToken,
  generateRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const { storeLoginRefreshToken } = require('./refreshSessionService');

const INVALID_CREDENTIALS = 'Invalid credentials';

function validateLoginPayload(body) {
  const payload = body && typeof body === 'object' ? body : {};

  if (typeof payload.login !== 'string' || payload.login.trim() === '') {
    throw new AppError(400, 'login is required');
  }
  if (typeof payload.password !== 'string' || payload.password === '') {
    throw new AppError(400, 'password is required');
  }

  return {
    login: payload.login.trim(),
    password: payload.password,
  };
}

async function loginLocalUser(body) {
  const { login, password } = validateLoginPayload(body);

  if (!process.env.JWT_SECRET) {
    throw new AppError(503, 'JWT_SECRET is not configured');
  }

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const result = await pool.query(
    `SELECT id, login, email, auth_provider, password_hash, phone_verified
     FROM users
     WHERE login = $1
     LIMIT 1`,
    [login]
  );

  const user = result.rows[0];
  if (!user) {
    throw new AppError(401, INVALID_CREDENTIALS);
  }

  if (!user.phone_verified) {
    throw new AppError(403, 'Phone number is not verified');
  }

  if (!user.password_hash) {
    throw new AppError(401, INVALID_CREDENTIALS);
  }

  const matches = await bcrypt.compare(password, user.password_hash);
  if (!matches) {
    throw new AppError(401, INVALID_CREDENTIALS);
  }

  const access_token = generateAccessToken(user);
  const { token: refresh_token, token_hash } = generateRefreshToken();
  const expires_at = getRefreshTokenExpiryDate();

  const client = await pool.connect();
  let committed = false;

  try {
    await client.query('BEGIN');
    await storeLoginRefreshToken(user.id, token_hash, expires_at, client);
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

  return {
    access_token,
    refresh_token,
    user: {
      id: user.id,
      login: user.login,
      email: user.email,
      auth_provider: user.auth_provider,
    },
  };
}

module.exports = {
  loginLocalUser,
};
