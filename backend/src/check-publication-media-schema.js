require('dotenv').config();

const fs = require('fs');
const path = require('path');
const pool = require('./db');

const SQL_PATH = path.join(__dirname, '..', 'sql', '009_create_publication_media.sql');

const EXPECTED_COLUMNS = [
  'id',
  'publication_id',
  'kind',
  'source_type',
  'storage_key',
  'content_type',
  'byte_size',
  'original_filename',
  'sort_order',
  'status',
  'created_at',
];

const EXPECTED_KIND = ['image', 'video', 'audio', 'document'];
const EXPECTED_SOURCE_TYPE = ['camera', 'gallery', 'microphone', 'upload'];
const EXPECTED_STATUS = ['pending_upload', 'ready', 'failed'];

const EXPECTED_INDEXES = [
  {
    name: 'publication_media_publication_id_sort_order_idx',
    columns: ['publication_id', 'sort_order'],
    partialReady: false,
  },
  {
    name: 'publication_media_publication_id_ready_sort_order_key',
    columns: ['publication_id', 'sort_order'],
    partialReady: true,
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

  assert(
    /CREATE TABLE IF NOT EXISTS publication_media/i.test(sql),
    '009 must CREATE TABLE publication_media'
  );
  assert(/GENERATED ALWAYS AS IDENTITY/i.test(sql), '009 id must be IDENTITY');
  assert(/PRIMARY KEY/i.test(sql), '009 must declare PRIMARY KEY');
  assert(
    /REFERENCES publications \(id\) ON DELETE CASCADE/i.test(sql),
    '009 publication_id FK must ON DELETE CASCADE'
  );
  assert(
    /CONSTRAINT publication_media_publication_id_fkey/i.test(sql),
    '009 publication_media_publication_id_fkey missing'
  );
  assert(
    /CONSTRAINT publication_media_storage_key_key UNIQUE \(storage_key\)/i.test(sql),
    '009 storage_key UNIQUE missing'
  );
  assert(/MANUELLEMENT/i.test(sql), '009 must be documented as manual');
  assert(!/\bDROP\s+TABLE\b/i.test(code), '009 must not DROP TABLE');
  assert(!/CREATE TABLE IF NOT EXISTS publications\b/i.test(code), '009 must not recreate publications');
  assert(!/CREATE TABLE IF NOT EXISTS users\b/i.test(code), '009 must not recreate users');
  assert(!/\bBYTEA\b/i.test(code), '009 must not store BLOB/bytea');
  assert(!/r2\.|https:\/\//i.test(code), '009 must not persist storage URLs');
  assert(!/209\s*715\s*200|200\s*Mio|Too many media/i.test(sql), '009 must not CHECK 200 Mio / 20 media');
  assert(!/application\/pdf|image\/jpeg/i.test(code), '009 must not CHECK MIME types');

  for (const col of EXPECTED_COLUMNS) {
    assert(new RegExp(`\\b${col}\\b`, 'i').test(sql), `009 column ${col} missing in file`);
  }

  for (const kind of EXPECTED_KIND) {
    assert(sql.includes(`'${kind}'`), `009 kind value ${kind} missing in file`);
  }
  for (const source of EXPECTED_SOURCE_TYPE) {
    assert(sql.includes(`'${source}'`), `009 source_type value ${source} missing in file`);
  }
  for (const status of EXPECTED_STATUS) {
    assert(sql.includes(`'${status}'`), `009 status value ${status} missing in file`);
  }

  assert(/byte_size\s*>=\s*1/i.test(sql), '009 byte_size >= 1 missing in file');

  for (const idx of EXPECTED_INDEXES) {
    assert(sql.includes(idx.name), `009 index ${idx.name} missing in file`);
  }
  assert(/WHERE status = 'ready'/i.test(sql), '009 ready sort_order index must be partial');

  console.log('SQL file OK (sql/009_create_publication_media.sql inspected, not applied).');
}

async function tableExists() {
  const result = await pool.query(
    `SELECT 1
     FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_type = 'BASE TABLE'
       AND table_name = 'publication_media'`
  );
  return result.rows.length === 1;
}

async function runLiveChecks() {
  const ping = await pool.query('SELECT 1 AS ok');
  assert(Number(ping.rows[0].ok) === 1, 'SELECT 1 failed');
  console.log('PostgreSQL reachable (SELECT 1).');

  const exists = await tableExists();
  if (!exists) {
    console.log('Table publication_media: not found.');
    console.log('Apply sql/009_create_publication_media.sql manually in Neon.');
    console.log('This script does not apply the migration.');
    throw new Error('publication_media table is missing');
  }
  console.log('Table publication_media: present.');

  const columnsResult = await pool.query(
    `SELECT column_name, data_type, udt_name
     FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'publication_media'
     ORDER BY ordinal_position`
  );
  const names = columnsResult.rows.map((row) => row.column_name);
  console.log('  columns found:', names.join(', '));

  const missing = EXPECTED_COLUMNS.filter((col) => !names.includes(col));
  assert(missing.length === 0, `columns missing: ${missing.join(', ')}`);
  console.log('  expected columns: all present');

  const pk = await pool.query(
    `SELECT c.conname
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
     JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname = 'publication_media'
       AND c.contype = 'p'`
  );
  const pkNames = pk.rows.map((row) => row.conname);
  assert(
    pkNames.includes('publication_media_pkey'),
    `PRIMARY KEY publication_media_pkey missing (found: ${pkNames.join(', ') || 'none'})`
  );
  console.log('  PK publication_media_pkey: present');

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
       AND t.relname = 'publication_media'
       AND c.contype = 'f'
       AND c.conname = 'publication_media_publication_id_fkey'`
  );
  assert(fk.rows.length === 1, 'FK publication_media_publication_id_fkey missing');
  const fkRow = fk.rows[0];
  assert(fkRow.ref_table === 'publications', `FK must reference publications, got ${fkRow.ref_table}`);
  assert(fkRow.confdeltype === 'c', `FK ON DELETE must be CASCADE (pg confdeltype=c), got ${fkRow.confdeltype}`);
  assert(/ON DELETE CASCADE/i.test(fkRow.def), `FK def must include ON DELETE CASCADE: ${fkRow.def}`);
  console.log('  FK publication_media_publication_id_fkey → publications.id ON DELETE CASCADE: present');

  const uniques = await pool.query(
    `SELECT c.conname, pg_get_constraintdef(c.oid) AS def
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
     JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname = 'publication_media'
       AND c.contype = 'u'`
  );
  const uniqueByName = Object.fromEntries(uniques.rows.map((row) => [row.conname, row.def]));
  const storageUnique = uniqueByName.publication_media_storage_key_key;
  assert(storageUnique, 'UNIQUE publication_media_storage_key_key missing');
  assert(/storage_key/i.test(storageUnique), `UNIQUE must cover storage_key: ${storageUnique}`);
  console.log('  UNIQUE storage_key: present');

  const checks = await pool.query(
    `SELECT c.conname, pg_get_constraintdef(c.oid) AS def
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
     JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname = 'publication_media'
       AND c.contype = 'c'`
  );
  const checkByName = Object.fromEntries(checks.rows.map((row) => [row.conname, row.def]));

  const kindDef = checkByName.publication_media_kind_check;
  assert(kindDef, 'CHECK publication_media_kind_check missing');
  for (const kind of EXPECTED_KIND) {
    assert(kindDef.includes(`'${kind}'`), `kind CHECK missing ${kind}: ${kindDef}`);
  }
  console.log('  CHECK kind: image|video|audio|document');

  const sourceDef = checkByName.publication_media_source_type_check;
  assert(sourceDef, 'CHECK publication_media_source_type_check missing');
  for (const source of EXPECTED_SOURCE_TYPE) {
    assert(sourceDef.includes(`'${source}'`), `source_type CHECK missing ${source}: ${sourceDef}`);
  }
  console.log('  CHECK source_type: camera|gallery|microphone|upload');

  const statusDef = checkByName.publication_media_status_check;
  assert(statusDef, 'CHECK publication_media_status_check missing');
  for (const status of EXPECTED_STATUS) {
    assert(statusDef.includes(`'${status}'`), `status CHECK missing ${status}: ${statusDef}`);
  }
  console.log('  CHECK status: pending_upload|ready|failed');

  const sizeDef = checkByName.publication_media_byte_size_check;
  assert(sizeDef, 'CHECK publication_media_byte_size_check missing');
  assert(/byte_size/.test(sizeDef) && />=\s*1|>=\(1\)/.test(sizeDef.replace(/\s/g, '')), `byte_size CHECK >= 1: ${sizeDef}`);
  console.log('  CHECK byte_size >= 1');

  const indexes = await pool.query(
    `SELECT indexname, indexdef
     FROM pg_indexes
     WHERE schemaname = 'public' AND tablename = 'publication_media'`
  );
  const indexByName = Object.fromEntries(indexes.rows.map((row) => [row.indexname, row.indexdef]));

  for (const idx of EXPECTED_INDEXES) {
    const def = indexByName[idx.name];
    assert(def, `index ${idx.name} missing`);
    for (const col of idx.columns) {
      assert(new RegExp(`\\b${col}\\b`).test(def), `index ${idx.name} must include ${col}: ${def}`);
    }
    if (idx.partialReady) {
      assert(/status\s*=\s*'ready'/.test(def), `index ${idx.name} must be WHERE status='ready': ${def}`);
      assert(/UNIQUE/i.test(def), `index ${idx.name} must be UNIQUE: ${def}`);
    }
    console.log(`  index ${idx.name}: present`);
  }

  console.log('Live schema check succeeded (SELECT only).');
}

async function main() {
  inspectSqlFile();

  if (!process.env.DATABASE_URL) {
    console.log('');
    console.log('DATABASE_URL is not set; live PostgreSQL SELECT checks skipped.');
    console.log('Aucune donnée n’a été modifiée. La migration 009 n’a pas été appliquée.');
    return;
  }

  await runLiveChecks();
  console.log('');
  console.log('Aucune donnée n’a été modifiée (SELECT uniquement).');
  console.log('La migration 009 n’a pas été appliquée par ce script.');
}

main()
  .catch((err) => {
    console.error('Publication media schema check failed:', err.code || err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
