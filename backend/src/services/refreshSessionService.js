const pool = require('../db');

const MAX_ACTIVE_REFRESH_TOKENS = 5;
const STALE_REFRESH_TOKEN_DAYS = 30;

async function enforceActiveRefreshTokenLimit(executor, userId) {
  const result = await executor.query(
    `SELECT id
     FROM refresh_tokens
     WHERE user_id = $1
       AND revoked_at IS NULL
       AND expires_at > NOW()
     ORDER BY created_at ASC, id ASC`,
    [userId]
  );

  const overflow = result.rows.length - MAX_ACTIVE_REFRESH_TOKENS;
  if (overflow <= 0) {
    return 0;
  }

  const idsToRevoke = result.rows.slice(0, overflow).map((row) => row.id);
  await executor.query(
    `UPDATE refresh_tokens
     SET revoked_at = NOW()
     WHERE id = ANY($1::bigint[])
       AND revoked_at IS NULL`,
    [idsToRevoke]
  );

  return idsToRevoke.length;
}

async function storeLoginRefreshToken(userId, tokenHash, expiresAt, executor = pool) {
  await executor.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [userId, tokenHash, expiresAt]
  );
  return enforceActiveRefreshTokenLimit(executor, userId);
}

async function purgeStaleRefreshTokens({
  confirm = false,
  olderThanDays = STALE_REFRESH_TOKEN_DAYS,
  executor = pool,
} = {}) {
  if (!confirm) {
    throw new Error('Refusing to purge refresh tokens without { confirm: true }');
  }

  const days = Number(olderThanDays);
  if (!Number.isFinite(days) || days < 1) {
    throw new Error('olderThanDays must be a positive number');
  }

  const result = await executor.query(
    `DELETE FROM refresh_tokens
     WHERE (
       revoked_at IS NOT NULL
       AND revoked_at < NOW() - ($1 * INTERVAL '1 day')
     )
     OR expires_at < NOW() - ($1 * INTERVAL '1 day')
     RETURNING id`,
    [days]
  );

  return result.rowCount;
}

module.exports = {
  MAX_ACTIVE_REFRESH_TOKENS,
  STALE_REFRESH_TOKEN_DAYS,
  enforceActiveRefreshTokenLimit,
  storeLoginRefreshToken,
  purgeStaleRefreshTokens,
};
