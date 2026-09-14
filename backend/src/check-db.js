require('dotenv').config();

const pool = require('./db');

async function checkConnection() {
  if (!process.env.DATABASE_URL) {
    console.error(
      'DATABASE_URL is not set; real PostgreSQL connection test cannot run in this environment.'
    );
    process.exitCode = 1;
    return;
  }

  try {
    const result = await pool.query('SELECT 1');
    const value = result.rows[0] && Object.values(result.rows[0])[0];

    if (Number(value) === 1) {
      console.log('PostgreSQL connection succeeded (SELECT 1).');
    } else {
      console.error('PostgreSQL connection test returned an unexpected result.');
      process.exitCode = 1;
    }
  } catch (err) {
    console.error('PostgreSQL connection failed:', err.code || 'ERROR');
    process.exitCode = 1;
  }
}

checkConnection().finally(() => pool.end());
