const fs = require('fs');
const path = require('path');

const SQL_PATH = path.join(__dirname, '..', 'sql', '016_create_community_publications.sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function inspectSqlFile() {
  const sql = fs.readFileSync(SQL_PATH, 'utf8');
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

  assert(/MANUELLEMENT/i.test(sql), '016 must be documented as manual');
  assert(/CREATE TABLE IF NOT EXISTS community_publications/i.test(sql), '016 publications table');
  assert(/CREATE TABLE IF NOT EXISTS community_publication_media/i.test(sql), '016 media table');
  assert(/initial_media_count/i.test(sql), '016 initial_media_count');
  assert(/initial_media_open/i.test(sql), '016 initial_media_open');
  assert(/deleted_by_user_id/i.test(sql), '016 deleted_by_user_id');
  assert(/comments_enabled/i.test(sql), '016 comments_enabled');
  assert(/media_total_bytes/i.test(sql), '016 media_total_bytes');
  assert(/'draft'/i.test(sql) && /'scheduled'/i.test(sql) && /'active'/i.test(sql), '016 statuses');
  assert(/'expired'/i.test(sql) && /'deleted'/i.test(sql), '016 expired/deleted');
  assert(!/'archived'/i.test(code), '016 must not include archived');
  assert(!/\bis_public\b/i.test(code), '016 must not include is_public');
  assert(!/\baudience\b/i.test(code), '016 must not include audience');
  assert(!/\btheme_id\b/i.test(code), '016 must not include theme_id');
  assert(/REFERENCES communities \(id\) ON DELETE RESTRICT/i.test(sql), '016 community RESTRICT');
  assert(/REFERENCES users \(id\) ON DELETE RESTRICT/i.test(sql), '016 user RESTRICT');
  assert(!/community_members/i.test(code), '016 must not FK community_members');
  assert(!/\bpublications\b/i.test(code.replace(/community_publications/g, '')), '016 must not alter publications');
  assert(!/\bpublication_media\b/i.test(code.replace(/community_publication_media/g, '')), '016 must not alter publication_media');
  assert(/char_length\(title\) <= 200/i.test(sql), '016 title max 200');
  assert(/char_length\(body\) <= 1000/i.test(sql), '016 body max 1000');
  assert(/ON DELETE CASCADE/i.test(sql), '016 media CASCADE on publication delete');
  console.log('SQL file OK (sql/016_create_community_publications.sql inspected, not applied).');
}

inspectSqlFile();
console.log('Community publication schema check succeeded (fichier uniquement, sans Neon).');
