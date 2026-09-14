const bcrypt = require('bcrypt');
const pool = require('../db');
const AppError = require('../errors/AppError');
const {
  generateAccessToken,
  generateRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const { storeLoginRefreshToken } = require('./refreshSessionService');
const { preparePasswordForLogin } = require('../validators/passwordValidator');
const { prepareLoginForLookup } = require('../validators/authFields');

const INVALID_CREDENTIALS = 'Invalid credentials';
const BCRYPT_ROUNDS = 10;
const DUMMY_PASSWORD_HASH = bcrypt.hashSync('dummy-timing-password', BCRYPT_ROUNDS);

function validateLoginPayload(body) {
  const payload = body && typeof body === 'object' ? body : {};

  return {
    login: prepareLoginForLookup(payload.login),
    password: preparePasswordForLogin(payload.password),
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
    await bcrypt.compare(password, DUMMY_PASSWORD_HASH);
    throw new AppError(401, INVALID_CREDENTIALS);
  }

  if (!user.phone_verified) {
    throw new AppError(403, 'Phone number is not verified');
  }

  if (!user.password_hash) {
    await bcrypt.compare(password, DUMMY_PASSWORD_HASH);
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
