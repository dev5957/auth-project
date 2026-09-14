require('dotenv').config();

const { purgeStaleRefreshTokens, STALE_REFRESH_TOKEN_DAYS } = require('./services/refreshSessionService');
const pool = require('./db');

async function main() {
  if (!process.argv.includes('--confirm')) {
    console.error(
      'Refusing to purge. Re-run with --confirm after review. ' +
        `Deletes refresh tokens revoked or expired for more than ${STALE_REFRESH_TOKEN_DAYS} days. ` +
        'Active tokens are never deleted.'
    );
    process.exitCode = 1;
    return;
  }

  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL is not set; purge cannot run.');
    process.exitCode = 1;
    return;
  }

  const deleted = await purgeStaleRefreshTokens({ confirm: true });
  console.log(`Purged ${deleted} stale refresh token row(s).`);
}

main()
  .catch((err) => {
    console.error('Purge failed:', err.code || err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
