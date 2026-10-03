const fs = require('fs');
const path = require('path');

const SQL_PATH = path.join(__dirname, '..', 'sql', '015_add_role_assigned_at_to_community_members.sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function inspectSqlFile() {
  const sql = fs.readFileSync(SQL_PATH, 'utf8');
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

  assert(/MANUELLEMENT/i.test(sql), '015 must be documented as manual');
  assert(/ALTER TABLE community_members/i.test(sql), '015 must ALTER community_members');
  assert(/ADD COLUMN IF NOT EXISTS role_assigned_at TIMESTAMPTZ/i.test(sql), '015 must add role_assigned_at');
  assert(/WHERE role = 'admin'/i.test(sql), '015 must backfill current admins');
  assert(/community_members_admin_assigned_idx/i.test(sql), '015 admin assigned index');
  assert(!/\bDROP\s+TABLE\b/i.test(code), '015 must not DROP TABLE');
  assert(!/\bON DELETE CASCADE\b/i.test(code), '015 must not CASCADE');
  assert(!/\b012_create_communities\b/i.test(sql), '015 must not rewrite 012');
  assert(!/\b013_/i.test(sql), '015 must not rewrite 013');
  assert(!/\b014_/i.test(sql), '015 must not rewrite 014');
  console.log('SQL file OK (sql/015_add_role_assigned_at_to_community_members.sql inspected, not applied).');
}

inspectSqlFile();
console.log('Community members schema check succeeded (fichier uniquement, sans Neon).');
