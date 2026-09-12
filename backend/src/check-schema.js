require('dotenv').config();

const pool = require('./db');

const EXPECTED = {
  users: [
    'id',
    'email',
    'birth_date',
    'phone_number',
    'phone_verified',
    'login',
    'password_hash',
    'auth_provider',
  ],
  phone_verifications: [
    'id',
    'verification_token',
    'phone_number',
    'code_hash',
    'expires_at',
    'attempts',
    'verified_at',
    'registration_data',
  ],
  refresh_tokens: [
    'id',
    'user_id',
    'token_hash',
    'expires_at',
    'revoked_at',
  ],
};

const TABLE_NAMES = Object.keys(EXPECTED);

async function checkSchema() {
  if (!process.env.DATABASE_URL) {
    console.error(
      'DATABASE_URL is not set; schema check cannot run in this environment.'
    );
    process.exitCode = 1;
    return;
  }

  const tablesResult = await pool.query(
    `SELECT table_name
     FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_type = 'BASE TABLE'
       AND table_name = ANY($1::text[])
     ORDER BY table_name`,
    [TABLE_NAMES]
  );

  const foundTables = tablesResult.rows.map((row) => row.table_name);
  const missingTables = TABLE_NAMES.filter((name) => !foundTables.includes(name));

  console.log('Tables found:', foundTables.length ? foundTables.join(', ') : '(none)');
  if (missingTables.length) {
    console.log('Tables missing:', missingTables.join(', '));
  }

  const columnsResult = await pool.query(
    `SELECT table_name, column_name
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = ANY($1::text[])
     ORDER BY table_name, ordinal_position`,
    [TABLE_NAMES]
  );

  const columnsByTable = {};
  for (const name of TABLE_NAMES) {
    columnsByTable[name] = [];
  }
  for (const row of columnsResult.rows) {
    columnsByTable[row.table_name].push(row.column_name);
  }

  let hasDifference = missingTables.length > 0;

  for (const tableName of TABLE_NAMES) {
    const actual = columnsByTable[tableName];
    const expected = EXPECTED[tableName];
    const missingColumns = expected.filter((col) => !actual.includes(col));
    const extraColumns = actual.filter((col) => !expected.includes(col));

    console.log('');
    console.log(`[${tableName}]`);
    if (!foundTables.includes(tableName)) {
      console.log('  status: table not found');
      continue;
    }

    console.log('  columns found:', actual.join(', ') || '(none)');
    if (missingColumns.length) {
      console.log('  columns missing:', missingColumns.join(', '));
      hasDifference = true;
    }
    if (extraColumns.length) {
      console.log('  extra columns:', extraColumns.join(', '));
    }
    if (!missingColumns.length) {
      console.log('  expected columns: all present');
    }
  }

  if (hasDifference) {
    console.error('');
    console.error('Schema check found missing tables or columns.');
    process.exitCode = 1;
    return;
  }

  console.log('');
  console.log('Schema check succeeded.');
}

checkSchema()
  .catch((err) => {
    console.error('Schema check failed:', err.code || 'ERROR');
    process.exitCode = 1;
  })
  .finally(() => pool.end());
