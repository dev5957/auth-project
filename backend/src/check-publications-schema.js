require('dotenv').config();

const fs = require('fs');
const path = require('path');
const pool = require('./db');

const SQL_PATH = path.join(__dirname, '..', 'sql', '008_create_publications.sql');

const EXPECTED_COLUMNS = [
  'id',
  'user_id',
  'theme_id',
  'title',
  'body',
  'status',
  'scheduled_at',
  'published_at',
  'archived_at',
  'expired_at',
  'purge_after',
  'deleted_at',
  'is_time_limited',
  'expires_at',
  'is_public',
  'audience',
  'comments_enabled',
  'media_total_bytes',
  'created_at',
  'updated_at',
];

const EXPECTED_STATUS = ['draft', 'scheduled', 'active', 'archived', 'expired', 'deleted'];
const EXPECTED_AUDIENCE = ['private', 'followers', 'public'];

const FEED_INDEXES = [
  {
    name: 'publications_user_id_active_feed_idx',
    status: 'active',
    columns: ['user_id', 'published_at', 'id'],
  },
  {
    name: 'publications_user_id_archived_feed_idx',
    status: 'archived',
    columns: ['user_id', 'archived_at', 'id'],
  },
  {
    name: 'publications_user_id_expired_feed_idx',
    status: 'expired',
    columns: ['user_id', 'expired_at', 'id'],
  },
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function readSql() {
  return fs.readFileSync(SQL_PATH, 'utf8');
}

function inspectSqlFile() {
  const sql = readSql();
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

  assert(/CREATE TABLE IF NOT EXISTS publications/i.test(sql), '008 must CREATE TABLE publications');
  assert(/GENERATED ALWAYS AS IDENTITY/i.test(sql), '008 id must be IDENTITY');
  assert(/REFERENCES users \(id\) ON DELETE RESTRICT/i.test(sql), '008 user_id FK must ON DELETE RESTRICT');
  assert(/CONSTRAINT publications_user_id_fkey/i.test(sql), '008 publications_user_id_fkey missing');
  assert(/PRIMARY KEY/i.test(sql), '008 must declare PRIMARY KEY');
  assert(!/CREATE TABLE IF NOT EXISTS users\b/i.test(code), '008 must not recreate users');
  assert(!/\bpublication_media\b/i.test(code), '008 must not create publication_media');
  assert(/MANUELLEMENT/i.test(sql), '008 must be documented as manual');
  assert(!/\bDROP\s+TABLE\b/i.test(code), '008 must not DROP TABLE');

  for (const col of EXPECTED_COLUMNS) {
    const pattern = new RegExp(`\\b${col}\\b`, 'i');
    assert(pattern.test(sql), `008 column ${col} missing in file`);
  }

  for (const status of EXPECTED_STATUS) {
    assert(sql.includes(`'${status}'`), `008 status value ${status} missing in file`);
  }
  for (const audience of EXPECTED_AUDIENCE) {
    assert(sql.includes(`'${audience}'`), `008 audience value ${audience} missing in file`);
  }

  assert(/char_length\(btrim\(body\)\)\s*>=\s*20/i.test(sql), '008 body min 20 (btrim) missing in file');
  assert(/char_length\(body\)\s*<=\s*5000/i.test(sql), '008 body max 5000 missing in file');
  assert(/char_length\(title\)\s*<=\s*200/i.test(sql), '008 title max 200 missing in file');
  assert(/media_total_bytes\s*>=\s*0/i.test(sql), '008 media_total_bytes >= 0 missing in file');
  assert(!/209\s*715\s*200|200\s*Mio|Too many media/i.test(sql), '008 must not CHECK 200 Mio / 20 media');

  for (const idx of FEED_INDEXES) {
    assert(sql.includes(idx.name), `008 index ${idx.name} missing in file`);
    assert(
      new RegExp(`WHERE status = '${idx.status}'`).test(sql),
      `008 index ${idx.name} must be partial status=${idx.status}`
    );
  }

  console.log('SQL file OK (sql/008_create_publications.sql inspected, not applied).');
}

async function tableExists() {
  const result = await pool.query(
    `SELECT 1
     FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_type = 'BASE TABLE'
       AND table_name = 'publications'`
  );
  return result.rows.length === 1;
}

async function runLiveChecks() {
  const ping = await pool.query('SELECT 1 AS ok');
  assert(Number(ping.rows[0].ok) === 1, 'SELECT 1 failed');
  console.log('PostgreSQL reachable (SELECT 1).');

  const exists = await tableExists();
  if (!exists) {
    console.log('Table publications: not found.');
    console.log('Apply sql/008_create_publications.sql manually in Neon.');
    console.log('This script does not apply the migration.');
    throw new Error('publications table is missing');
  }
  console.log('Table publications: present.');

  const columnsResult = await pool.query(
    `SELECT column_name, data_type, udt_name
     FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'publications'
     ORDER BY ordinal_position`
  );
  const columns = columnsResult.rows;
  const names = columns.map((row) => row.column_name);
  const byName = Object.fromEntries(columns.map((row) => [row.column_name, row]));

  console.log('  columns found:', names.join(', '));

  const missing = EXPECTED_COLUMNS.filter((col) => !names.includes(col));
  assert(missing.length === 0, `columns missing: ${missing.join(', ')}`);
  console.log('  expected columns: all present');

  function assertType(column, allowed) {
    const row = byName[column];
    assert(row, `${column} missing`);
    const actual = `${row.data_type}/${row.udt_name}`.toLowerCase();
    const ok = allowed.some((item) => actual.includes(item.toLowerCase()));
    assert(ok, `${column} type expected one of ${allowed.join('|')}, got ${row.data_type} (${row.udt_name})`);
  }

  assertType('id', ['bigint']);
  assertType('user_id', ['bigint']);
  assertType('body', ['text']);
  assertType('status', ['text']);
  console.log('  types: id/user_id bigint, body/status text');

  const pk = await pool.query(
    `SELECT c.conname
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
     JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname = 'publications'
       AND c.contype = 'p'`
  );
  const pkNames = pk.rows.map((row) => row.conname);
  assert(pkNames.includes('publications_pkey'), `PRIMARY KEY publications_pkey missing (found: ${pkNames.join(', ') || 'none'})`);
  console.log('  PK publications_pkey: present');

  const fk = await pool.query(
    `SELECT
       c.conname,
       c.confdeltype,
       pg_get_constraintdef(c.oid) AS def,
       ref.relname AS ref_table
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
     JOIN pg_class ref ON ref.oid = c.confrelid
     JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname = 'publications'
       AND c.contype = 'f'
       AND c.conname = 'publications_user_id_fkey'`
  );
  assert(fk.rows.length === 1, 'FK publications_user_id_fkey missing');
  const fkRow = fk.rows[0];
  assert(fkRow.ref_table === 'users', `FK must reference users, got ${fkRow.ref_table}`);
  assert(fkRow.confdeltype === 'r', `FK ON DELETE must be RESTRICT (pg confdeltype=r), got ${fkRow.confdeltype}`);
  assert(/ON DELETE RESTRICT/i.test(fkRow.def), `FK def must include ON DELETE RESTRICT: ${fkRow.def}`);
  console.log('  FK publications_user_id_fkey → users.id ON DELETE RESTRICT: present');

  const checks = await pool.query(
    `SELECT c.conname, pg_get_constraintdef(c.oid) AS def
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
     JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname = 'publications'
       AND c.contype = 'c'`
  );
  const checkByName = Object.fromEntries(checks.rows.map((row) => [row.conname, row.def]));

  const statusDef = checkByName.publications_status_check;
  assert(statusDef, 'CHECK publications_status_check missing');
  for (const status of EXPECTED_STATUS) {
    assert(statusDef.includes(`'${status}'`), `status CHECK missing ${status}: ${statusDef}`);
  }
  console.log('  CHECK status: draft|scheduled|active|archived|expired|deleted');

  const bodyDef = checkByName.publications_body_length_check;
  assert(bodyDef, 'CHECK publications_body_length_check missing');
  assert(/btrim/i.test(bodyDef) && /20/.test(bodyDef), `body CHECK must btrim >= 20: ${bodyDef}`);
  assert(/5000/.test(bodyDef), `body CHECK must max 5000: ${bodyDef}`);
  console.log('  CHECK body: btrim >= 20 and length <= 5000');

  const titleDef = checkByName.publications_title_length_check;
  assert(titleDef, 'CHECK publications_title_length_check missing');
  assert(/200/.test(titleDef), `title CHECK must max 200: ${titleDef}`);
  console.log('  CHECK title: max 200');

  const audienceDef = checkByName.publications_audience_check;
  assert(audienceDef, 'CHECK publications_audience_check missing');
  for (const audience of EXPECTED_AUDIENCE) {
    assert(audienceDef.includes(`'${audience}'`), `audience CHECK missing ${audience}: ${audienceDef}`);
  }
  console.log('  CHECK audience: private|followers|public');

  const bytesDef = checkByName.publications_media_total_bytes_non_negative_check;
  assert(bytesDef, 'CHECK publications_media_total_bytes_non_negative_check missing');
  assert(/media_total_bytes/.test(bytesDef) && />=\s*0|>=\(0\)/.test(bytesDef.replace(/\s/g, '')), `media_total_bytes CHECK >= 0: ${bytesDef}`);
  console.log('  CHECK media_total_bytes >= 0');

  const indexes = await pool.query(
    `SELECT indexname, indexdef
     FROM pg_indexes
     WHERE schemaname = 'public' AND tablename = 'publications'`
  );
  const indexByName = Object.fromEntries(indexes.rows.map((row) => [row.indexname, row.indexdef]));

  for (const idx of FEED_INDEXES) {
    const def = indexByName[idx.name];
    assert(def, `index ${idx.name} missing`);
    for (const col of idx.columns) {
      assert(new RegExp(`\\b${col}\\b`).test(def), `index ${idx.name} must include ${col}: ${def}`);
    }
    assert(
      new RegExp(`status\\s*=\\s*'${idx.status}'`).test(def),
      `index ${idx.name} must be WHERE status='${idx.status}': ${def}`
    );
    console.log(`  index ${idx.name}: present (partial status=${idx.status})`);
  }

  console.log('Live schema check succeeded (SELECT only).');
}

async function main() {
  inspectSqlFile();

  if (!process.env.DATABASE_URL) {
    console.log('');
    console.log('DATABASE_URL is not set; live PostgreSQL SELECT checks skipped.');
    console.log('Aucune donnée n’a été modifiée. La migration 008 n’a pas été appliquée.');
    return;
  }

  await runLiveChecks();
  console.log('');
  console.log('Aucune donnée n’a été modifiée (SELECT uniquement).');
  console.log('La migration 008 n’a pas été appliquée par ce script.');
}

main()
  .catch((err) => {
    console.error('Publications schema check failed:', err.code || err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
