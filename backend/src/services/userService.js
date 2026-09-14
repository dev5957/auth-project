const pool = require('../db');
const AppError = require('../errors/AppError');

function formatBirthDate(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    const year = value.getUTCFullYear();
    const month = String(value.getUTCMonth() + 1).padStart(2, '0');
    const day = String(value.getUTCDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  if (typeof value === 'string' && value.length >= 10) {
    return value.slice(0, 10);
  }
  return value;
}

function formatUserId(value) {
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

function toPublicProfile(row) {
  return {
    id: formatUserId(row.id),
    login: row.login,
    email: row.email,
    phone_number: row.phone_number,
    birth_date: formatBirthDate(row.birth_date),
    auth_provider: row.auth_provider,
  };
}

async function findUserProfileById(userId) {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }

  if (userId == null || userId === '') {
    throw new AppError(404, 'User not found');
  }

  const result = await pool.query(
    `SELECT id, login, email, phone_number, birth_date, auth_provider
     FROM users
     WHERE id = $1
     LIMIT 1`,
    [userId]
  );

  const row = result.rows[0];
  if (!row) {
    throw new AppError(404, 'User not found');
  }

  return toPublicProfile(row);
}

module.exports = {
  findUserProfileById,
};
