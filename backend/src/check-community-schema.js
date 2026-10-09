const fs = require('fs');
const path = require('path');

const SQL_PATH = path.join(__dirname, '..', 'sql', '012_create_communities.sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function inspectSqlFile() {
  const sql = fs.readFileSync(SQL_PATH, 'utf8');
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

  assert(/MANUELLEMENT/i.test(sql), '012 must be documented as manual');
  assert(/CREATE TABLE IF NOT EXISTS communities/i.test(sql), '012 must CREATE communities');
  assert(/CREATE TABLE IF NOT EXISTS community_members/i.test(sql), '012 must CREATE community_members');
  assert(/GENERATED ALWAYS AS IDENTITY/i.test(sql), '012 ids must be IDENTITY');
  assert(/REFERENCES users \(id\) ON DELETE RESTRICT/i.test(sql), '012 user FKs must ON DELETE RESTRICT');
  assert(/REFERENCES communities \(id\) ON DELETE RESTRICT/i.test(sql), '012 community FK must ON DELETE RESTRICT');
  assert(!/\bON DELETE CASCADE\b/i.test(code), '012 must not CASCADE deletes');
  assert(!/\bDROP\s+TABLE\b/i.test(code), '012 must not DROP TABLE');
  assert(!/\bpublications\b/i.test(code), '012 must not alter publications');
  assert(!/\bpublication_media\b/i.test(code), '012 must not alter publication_media');
  assert(/UNIQUE \(community_id, user_id\)/i.test(sql), '012 membership uniqueness');
  assert(/community_members_one_owner_per_community_key/i.test(sql), '012 one owner index');
  assert(/community_members_user_id_idx/i.test(sql), '012 user membership index');
  assert(/community_members_community_id_role_idx/i.test(sql), '012 community role index');
  assert(/visibility = 'private'/i.test(sql), '012 visibility private only');
  assert(/char_length\(btrim\(name\)\)\s*>=\s*10/i.test(sql), '012 name min 10');
  assert(/char_length\(btrim\(name\)\)\s*<=\s*100/i.test(sql), '012 name max 100');
  assert(/char_length\(btrim\(description\)\)\s*<=\s*500/i.test(sql), '012 description max 500');
  assert(!/UNIQUE \(name\)/i.test(sql), '012 must allow homonyms');
  assert(/avatar_storage_key/i.test(sql), '012 avatar_storage_key column');
  assert(/banner_storage_key/i.test(sql), '012 banner_storage_key column');
  console.log('SQL file OK (sql/012_create_communities.sql inspected, not applied).');
}

inspectSqlFile();
console.log('Community schema check succeeded (fichier uniquement, sans Neon).');
