require('dotenv').config();

const fs = require('fs');
const path = require('path');
const pool = require('./db');

const SQL_DIR = path.join(__dirname, '..', 'sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function readSql(name) {
  return fs.readFileSync(path.join(SQL_DIR, name), 'utf8');
}

function stripSqlComments(sql) {
  return sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
}

function inspectSqlFiles() {
  const users = readSql('001_create_users.sql');
  const verifications = readSql('002_create_phone_verifications.sql');
  const registration = readSql('003_add_registration_data_to_phone_verifications.sql');
  const refresh = readSql('004_create_refresh_tokens.sql');
  const harden = readSql('005_harden_users.sql');
  const hardenCode = stripSqlComments(harden);

  assert(users.includes('CONSTRAINT users_email_key UNIQUE (email)'), 'C: users.email UNIQUE missing in 001');
  assert(users.includes('CONSTRAINT users_login_key UNIQUE (login)'), 'D: users.login UNIQUE missing in 001');
  assert(users.includes('phone_number TEXT NOT NULL'), 'E: users.phone_number NOT NULL missing in 001');
  assert(
    !users.includes('UNIQUE (phone_number)'),
    'E: phone UNIQUE must not be in 001 (added in 005 only)'
  );

  assert(
    verifications.includes('CONSTRAINT phone_verifications_verification_token_key UNIQUE (verification_token)'),
    'I: verification_token UNIQUE missing in 002'
  );
  assert(verifications.includes('code_hash TEXT NOT NULL'), 'I: code_hash NOT NULL missing');
  assert(verifications.includes('expires_at TIMESTAMPTZ NOT NULL'), 'I: expires_at NOT NULL missing');
  assert(verifications.includes('attempts INTEGER NOT NULL'), 'I: attempts NOT NULL missing');
  assert(verifications.includes('verified_at TIMESTAMPTZ'), 'I: verified_at missing');
  assert(
    verifications.includes('phone_verifications_phone_number_created_at_idx'),
    'I: phone_number/created_at index missing in 002'
  );
  assert(
    !verifications.includes('UNIQUE (phone_number)'),
    'I: phone_verifications.phone_number must not be UNIQUE'
  );

  assert(registration.includes('registration_data JSONB'), 'I: registration_data missing in 003');

  assert(
    refresh.includes('CONSTRAINT refresh_tokens_token_hash_key UNIQUE (token_hash)'),
    'G: token_hash UNIQUE missing in 004'
  );
  assert(refresh.includes('ON DELETE CASCADE'), 'G: ON DELETE CASCADE missing in 004');
  assert(refresh.includes('CONSTRAINT refresh_tokens_user_id_fkey'), 'G: user_id FK missing in 004');
  assert(refresh.includes('expires_at TIMESTAMPTZ NOT NULL'), 'G: expires_at missing in 004');
  assert(refresh.includes('revoked_at TIMESTAMPTZ'), 'G: revoked_at missing in 004');
  assert(refresh.includes('refresh_tokens_user_id_idx'), 'H: user_id index missing in 004');

  assert(harden.includes('users_phone_number_unique'), '005 must add users_phone_number_unique');
  assert(harden.includes('UNIQUE (phone_number)'), '005 must UNIQUE phone_number');
  assert(harden.includes('refresh_tokens_user_id_active_idx'), '005 must add active refresh index');
  assert(harden.includes('WHERE revoked_at IS NULL'), '005 active index must be partial');
  assert(!/DROP\s+TABLE/i.test(hardenCode), '005 must not DROP TABLE');
  assert(!/DROP\s+COLUMN/i.test(hardenCode), '005 must not DROP COLUMN');
  assert(!/\bDELETE\b/i.test(hardenCode), '005 must not DELETE');
  assert(!/\bTRUNCATE\b/i.test(hardenCode), '005 must not TRUNCATE');
  assert(!/\bUPDATE\b/i.test(hardenCode), '005 must not UPDATE rows');

  console.log('SQL files OK (001–005 inspected, 005 non-destructive).');
}

function printCount(label, count) {
  console.log(`  ${label}: ${count}`);
}

async function runLiveChecks() {
  const ping = await pool.query('SELECT 1 AS ok');
  assert(Number(ping.rows[0].ok) === 1, 'A: SELECT 1 failed');
  console.log('A OK connexion PostgreSQL (SELECT 1)');

  const columns = await pool.query(
    `SELECT column_name
     FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'users'`
  );
  const userCols = columns.rows.map((row) => row.column_name);
  for (const col of ['id', 'email', 'login', 'phone_number']) {
    assert(userCols.includes(col), `B: users.${col} missing`);
  }
  console.log('B OK structure users');

  const constraints = await pool.query(
    `SELECT c.conname, c.contype, t.relname AS table_name
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
     JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public'
       AND t.relname IN ('users', 'phone_verifications', 'refresh_tokens')
     ORDER BY t.relname, c.conname`
  );

  const names = constraints.rows.map((row) => row.conname);
  assert(names.includes('users_email_key'), 'C: users_email_key missing in database');
  console.log('C OK email UNIQUE présent');
  assert(names.includes('users_login_key'), 'D: users_login_key missing in database');
  console.log('D OK login UNIQUE présent');

  const phoneUnique = names.includes('users_phone_number_unique');
  console.log(
    `E phone_number UNIQUE en base: ${phoneUnique ? 'oui (005 déjà appliqué)' : 'non (005 à appliquer manuellement)'}`
  );

  const emailDupes = await pool.query(
    `SELECT COUNT(*)::int AS groups
     FROM (
       SELECT email FROM users GROUP BY email HAVING COUNT(*) > 1
     ) d`
  );
  const loginDupes = await pool.query(
    `SELECT COUNT(*)::int AS groups
     FROM (
       SELECT login FROM users GROUP BY login HAVING COUNT(*) > 1
     ) d`
  );
  const phoneDupes = await pool.query(
    `SELECT COUNT(*)::int AS groups
     FROM (
       SELECT phone_number FROM users GROUP BY phone_number HAVING COUNT(*) > 1
     ) d`
  );
  const phoneNulls = await pool.query(
    'SELECT COUNT(*)::int AS n FROM users WHERE phone_number IS NULL'
  );
  const phoneEmpty = await pool.query(
    `SELECT COUNT(*)::int AS n FROM users WHERE phone_number = ''`
  );
  const phoneDupeIds = await pool.query(
    `SELECT MIN(id) AS one_id, COUNT(*)::int AS n
     FROM users
     GROUP BY phone_number
     HAVING COUNT(*) > 1
     ORDER BY n DESC, one_id ASC
     LIMIT 20`
  );

  printCount('A doublons email (groupes)', emailDupes.rows[0].groups);
  printCount('B doublons login (groupes)', loginDupes.rows[0].groups);
  printCount('C doublons phone_number (groupes)', phoneDupes.rows[0].groups);
  printCount('D phone_number NULL', phoneNulls.rows[0].n);
  printCount('E phone_number vide', phoneEmpty.rows[0].n);
  if (phoneDupeIds.rows.length) {
    console.log(
      '  ids concernés (un id par groupe, sans numéro):',
      phoneDupeIds.rows.map((row) => `${row.one_id}(n=${row.n})`).join(', ')
    );
  }

  if (phoneDupes.rows[0].groups === 0) {
    console.log('F OK aucun doublon phone_number');
  } else {
    console.log('F BLOQUANT: doublons phone_number — ne pas appliquer UNIQUE tant qu’ils existent');
  }

  const refreshConstraints = constraints.rows.filter((row) => row.table_name === 'refresh_tokens');
  const refreshNames = refreshConstraints.map((row) => row.conname);
  assert(refreshNames.includes('refresh_tokens_token_hash_key'), 'G: token_hash UNIQUE missing');
  assert(refreshNames.includes('refresh_tokens_user_id_fkey'), 'G: user_id FK missing');
  console.log('G OK contraintes refresh_tokens (UNIQUE token_hash, FK user_id)');

  const indexes = await pool.query(
    `SELECT tablename, indexname, indexdef
     FROM pg_indexes
     WHERE schemaname = 'public'
       AND tablename IN ('users', 'phone_verifications', 'refresh_tokens')
     ORDER BY tablename, indexname`
  );

  const refreshIdx = indexes.rows.filter((row) => row.tablename === 'refresh_tokens');
  const hasUserIdIdx = refreshIdx.some((row) => row.indexname === 'refresh_tokens_user_id_idx');
  const hasActiveIdx = refreshIdx.some(
    (row) =>
      row.indexname === 'refresh_tokens_user_id_active_idx' ||
      /ON refresh_tokens USING btree \(user_id\).*WHERE \(revoked_at IS NULL\)/i.test(row.indexdef)
  );
  assert(hasUserIdIdx, 'H: refresh_tokens_user_id_idx missing');
  console.log(
    `H index refresh_tokens: user_id=${hasUserIdIdx ? 'oui' : 'non'}, user_id actif (005)=${hasActiveIdx ? 'oui' : 'non (à appliquer)'}`
  );

  const activeByUser = await pool.query(
    `SELECT user_id, COUNT(*)::int AS active_count
     FROM refresh_tokens
     WHERE revoked_at IS NULL
     GROUP BY user_id
     ORDER BY active_count DESC, user_id ASC
     LIMIT 20`
  );
  console.log(`  F refresh_tokens actifs: ${activeByUser.rows.length} user_id (max 20 listés, sans token_hash)`);
  for (const row of activeByUser.rows) {
    console.log(`    user_id=${row.user_id} active_count=${row.active_count}`);
  }

  const pvNames = constraints.rows
    .filter((row) => row.table_name === 'phone_verifications')
    .map((row) => row.conname);
  assert(
    pvNames.includes('phone_verifications_verification_token_key'),
    'I: verification_token UNIQUE missing in database'
  );
  const pvIdx = indexes.rows.filter((row) => row.tablename === 'phone_verifications');
  assert(
    pvIdx.some((row) => row.indexname === 'phone_verifications_phone_number_created_at_idx'),
    'I: phone_number/created_at index missing in database'
  );
  console.log('I OK contraintes/index phone_verifications (token UNIQUE, pas de UNIQUE téléphone)');

  const defs = new Map();
  let duplicateIndex = false;
  for (const row of indexes.rows) {
    const normalized = row.indexdef.replace(row.indexname, '<name>');
    const key = `${row.tablename}::${normalized}`;
    if (defs.has(key)) {
      duplicateIndex = true;
      console.log(`  J doublon d’index: ${defs.get(key)} et ${row.indexname}`);
    } else {
      defs.set(key, row.indexname);
    }
  }
  assert(!duplicateIndex, 'J: duplicate indexes detected');
  console.log('J OK aucun doublon d’index');

  return {
    phoneDupes: phoneDupes.rows[0].groups,
    phoneUnique,
  };
}

async function main() {
  inspectSqlFiles();

  if (!process.env.DATABASE_URL) {
    console.log('');
    console.log('DATABASE_URL is not set; live PostgreSQL SELECT checks skipped.');
    console.log('Aucune donnée n’a été modifiée. Neon n’a pas été contacté.');
    console.log('Migration prête à être appliquée manuellement dans Neon.');
    return;
  }

  const live = await runLiveChecks();
  console.log('');
  if (live.phoneDupes > 0) {
    console.log('UNIQUE téléphone BLOQUÉ tant que les doublons ne sont pas corrigés à la main.');
  } else if (!live.phoneUnique) {
    console.log('UNIQUE téléphone possible. SQL à exécuter dans Neon : sql/005_harden_users.sql');
  } else {
    console.log('UNIQUE téléphone déjà présent en base.');
  }
  console.log('Aucune donnée n’a été modifiée (SELECT uniquement).');
  console.log('Migration prête à être appliquée manuellement dans Neon.');
}

main()
  .catch((err) => {
    console.error('SQL hardening check failed:', err.code || err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
