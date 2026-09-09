const pool = require('../db');
const AppError = require('../errors/AppError');
const {
  generateAccessToken,
  generateRefreshToken,
  getRefreshTokenExpiryDate,
  hashRefreshToken,
} = require('./tokenService');

const INVALID_REFRESH_TOKEN = 'Invalid refresh token';

function validateRefreshPayload(body) {
  const payload = body && typeof body === 'object' ? body : {};

  if (typeof payload.refresh_token !== 'string' || payload.refresh_token.trim() === '') {
    throw new AppError(400, 'refresh_token is required');
  }

  return payload.refresh_token.trim();
}

async function refreshAuthTokens(body, db = pool) {
  const refreshToken = validateRefreshPayload(body);

  if (!process.env.JWT_SECRET) {
    throw new AppError(503, 'JWT_SECRET is not configured');
  }

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const tokenHash = hashRefreshToken(refreshToken);
  const client = await db.connect();
  let committed = false;

  try {
    await client.query('BEGIN');

    const found = await client.query(
      `SELECT id, user_id, expires_at, revoked_at
       FROM refresh_tokens
       WHERE token_hash = $1
       FOR UPDATE`,
      [tokenHash]
    );

    const row = found.rows[0];
    if (!row) {
      throw new AppError(401, INVALID_REFRESH_TOKEN);
    }

    if (row.revoked_at) {
      await client.query(
        `UPDATE refresh_tokens
         SET revoked_at = NOW()
         WHERE user_id = $1 AND revoked_at IS NULL`,
        [row.user_id]
      );
      await client.query('COMMIT');
      committed = true;
      console.error('Security event: refresh_token_reuse', { userId: row.user_id });
      throw new AppError(401, INVALID_REFRESH_TOKEN);
    }

    if (new Date(row.expires_at).getTime() <= Date.now()) {
      throw new AppError(401, INVALID_REFRESH_TOKEN);
    }

    const userResult = await client.query(
      `SELECT id, login, email, auth_provider
       FROM users
       WHERE id = $1
       LIMIT 1`,
      [row.user_id]
    );

    const user = userResult.rows[0];
    if (!user) {
      throw new AppError(401, INVALID_REFRESH_TOKEN);
    }

    const access_token = generateAccessToken(user);
    const { token: new_refresh_token, token_hash } = generateRefreshToken();
    const expires_at = getRefreshTokenExpiryDate();

    await client.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, token_hash, expires_at]
    );

    await client.query(
      `UPDATE refresh_tokens
       SET revoked_at = NOW()
       WHERE id = $1`,
      [row.id]
    );

    await client.query('COMMIT');
    committed = true;

    return {
      access_token,
      refresh_token: new_refresh_token,
      user: {
        id: user.id,
        login: user.login,
        email: user.email,
        auth_provider: user.auth_provider,
      },
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

module.exports = {
  refreshAuthTokens,
};
