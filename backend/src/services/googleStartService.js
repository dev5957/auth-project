const pool = require('../db');
const AppError = require('../errors/AppError');
const { normalizeEmail } = require('../validators/authFields');
const {
  generateAccessToken,
  generateRefreshToken,
  getRefreshTokenExpiryDate,
} = require('./tokenService');
const { storeLoginRefreshToken } = require('./refreshSessionService');
const { verifyGoogleIdToken } = require('./googleAuthService');
const { createPendingOauthContext, PENDING_PHONE_PLACEHOLDER } = require('./oauthService');

const EMAIL_PROVIDER_CONFLICT = 'Account already exists with another authentication method';

async function issueSession(user, executor) {
  const access_token = generateAccessToken(user);
  const { token: refresh_token, token_hash } = generateRefreshToken();
  const expires_at = getRefreshTokenExpiryDate();
  await storeLoginRefreshToken(user.id, token_hash, expires_at, executor);
  return { access_token, refresh_token };
}

async function startGoogleAuth(body, options = {}) {
  const payload = body && typeof body === 'object' ? body : {};
  const verify = options.verifyGoogleIdToken || verifyGoogleIdToken;
  const db = options.db || pool;

  const identity = await verify(payload.id_token, options.googleClient ? { client: options.googleClient } : {});
  const email = normalizeEmail(identity.email);
  const provider_user_id = identity.provider_user_id;

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const existingGoogle = await db.query(
    `SELECT id, login, email, auth_provider, provider_user_id
     FROM users
     WHERE auth_provider = 'google'
       AND provider_user_id = $1
     LIMIT 1`,
    [provider_user_id]
  );

  if (existingGoogle.rowCount > 0) {
    if (!process.env.JWT_SECRET) {
      throw new AppError(503, 'JWT_SECRET is not configured');
    }

    const user = existingGoogle.rows[0];
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
      provider: 'google',
      provider_user_id,
      email,
      first_name: identity.first_name,
      last_name: identity.last_name,
    },
    { db }
  );

  return {
    message: 'Phone verification required',
    oauth_verification_token: pending.oauth_verification_token,
    email: pending.email,
  };
}

module.exports = {
  PENDING_PHONE_PLACEHOLDER,
  EMAIL_PROVIDER_CONFLICT,
  startGoogleAuth,
};
