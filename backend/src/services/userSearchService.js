const pool = require('../db');
const AppError = require('../errors/AppError');
const { parseUserSearchQuery } = require('../validators/userSearchFields');

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function formatId(value) {
  if (typeof value === 'bigint') {
    const asNumber = Number(value);
    return Number.isSafeInteger(asNumber) ? asNumber : value.toString();
  }
  if (typeof value === 'string' && /^\d+$/.test(value)) {
    const asNumber = Number(value);
    return Number.isSafeInteger(asNumber) ? asNumber : value;
  }
  return value;
}

function toSearchHit(row) {
  return {
    user_id: formatId(row.id),
    login: row.login,
  };
}

async function searchUsers(query, deps = {}) {
  const input = parseUserSearchQuery(query);
  requireDatabase();
  const db = deps.db || pool;

  if (input.kind === 'login') {
    const result = await db.query(
      `SELECT id, login
       FROM users
       WHERE login = $1
       LIMIT 1`,
      [input.login]
    );
    const row = result.rows[0];
    return { items: row ? [toSearchHit(row)] : [] };
  }

  const result = await db.query(
    `SELECT id, login
     FROM users
     WHERE phone_number = $1
       AND phone_verified = TRUE
     LIMIT 1`,
    [input.phone]
  );
  const row = result.rows[0];
  return { items: row ? [toSearchHit(row)] : [] };
}

module.exports = {
  searchUsers,
  toSearchHit,
};
