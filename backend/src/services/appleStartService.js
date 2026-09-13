const pool = require('../db');
const AppError = require('../errors/AppError');
const { normalizeEmail } = require('../validators/authFields');
const {
  generateAccessToken,
  generateRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const { storeLoginRefreshToken } = require('./refreshSessionService');
const { verifyAppleIdentityToken } = require('./appleAuthService');
const { createPendingOauthContext, EMAIL_PROVIDER_CONFLICT } = require('./oauthService');

function optionalName(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

async function issueSession(user, executor) {
  const access_token = generateAccessToken(user);
  const { token: refresh_token, token_hash } = generateRefreshToken();
  const expires_at = getRefreshTokenExpiryDate();
  await storeLoginRefreshToken(user.id, token_hash, expires_at, executor);
  return { access_token, refresh_token };
}

async function startAppleAuth(body, options = {}) {
  const payload = body && typeof body === 'object' ? body : {};
  const verify = options.verifyAppleIdentityToken || verifyAppleIdentityToken;
  const db = options.db || pool;

  const identity = await verify(payload.identity_token, options.appleVerifyOptions || {});
  const provider_user_id = identity.provider_user_id;
  const first_name = identity.first_name || optionalName(payload.first_name);
  const last_name = identity.last_name || optionalName(payload.last_name);

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const existingApple = await db.query(
    `SELECT id, login, email, auth_provider, provider_user_id
     FROM users
     WHERE auth_provider = 'apple'
       AND provider_user_id = $1
     LIMIT 1`,
    [provider_user_id]
  );

  if (existingApple.rowCount > 0) {
    if (!process.env.JWT_SECRET) {
      throw new AppError(503, 'JWT_SECRET is not configured');
    }

    const user = existingApple.rows[0];
    const client = await db.connect();
    let committed = false;
    try {
      await client.query('BEGIN');
      const tokens = await issueSession(user, client);
      await client.query('COMMIT');
      committed = true;
      return {
        message: 'Login successful',
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
      throw err;
    } finally {
      client.release();
    }
  }

  if (typeof identity.email !== 'string' || identity.email.trim() === '') {
    throw new AppError(400, 'email is required');
  }

  const email = normalizeEmail(identity.email);

  const emailTaken = await db.query(
    `SELECT auth_provider
     FROM users
     WHERE email = $1
     LIMIT 1`,
    [email]
  );
  if (emailTaken.rowCount > 0) {
    throw new AppError(409, EMAIL_PROVIDER_CONFLICT);
  }

  const pending = await createPendingOauthContext(
    {
      provider: 'apple',
      provider_user_id,
      email,
      first_name,
      last_name,
    },
    { db }
  );

  return {
    message: 'Phone verification required',
    oauth_verification_token: pending.oauth_verification_token,
    email: pending.email,
    provider: 'apple',
  };
}

module.exports = {
  EMAIL_PROVIDER_CONFLICT,
  startAppleAuth,
};
