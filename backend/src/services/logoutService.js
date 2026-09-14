const pool = require('../db');
const AppError = require('../errors/AppError');
const { hashRefreshToken } = require('./tokenService');

const UNAUTHORIZED = 'Unauthorized';
const REFRESH_REQUIRED = 'Refresh token required';

function readRefreshToken(body) {
  const payload = body && typeof body === 'object' ? body : {};

  if (typeof payload.refresh_token !== 'string' || payload.refresh_token.trim() === '') {
    throw new AppError(400, REFRESH_REQUIRED);
  }

  return payload.refresh_token.trim();
}

async function logoutCurrentSession(body, userId, db = pool) {
  const refreshToken = readRefreshToken(body);

  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  const tokenHash = hashRefreshToken(refreshToken);
  const client = await db.connect();
  let committed = false;

  try {
    await client.query('BEGIN');

    const found = await client.query(
      `SELECT id, user_id, revoked_at
       FROM refresh_tokens
       WHERE token_hash = $1
       FOR UPDATE`,
      [tokenHash]
    );

    const row = found.rows[0];
    if (!row || row.revoked_at || String(row.user_id) !== String(userId)) {
      throw new AppError(401, UNAUTHORIZED);
    }

    const updated = await client.query(
      `UPDATE refresh_tokens
       SET revoked_at = NOW()
       WHERE id = $1
         AND revoked_at IS NULL`,
      [row.id]
    );

    if (updated.rowCount !== 1) {
      throw new AppError(401, UNAUTHORIZED);
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
}

module.exports = {
  logoutCurrentSession,
};
