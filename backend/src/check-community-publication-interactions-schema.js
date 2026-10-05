const fs = require('fs');
const path = require('path');

const SQL_PATH = path.join(__dirname, '..', 'sql', '017_create_community_publication_interactions.sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function inspectSqlFile() {
  const sql = fs.readFileSync(SQL_PATH, 'utf8');
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

  assert(/MANUELLEMENT/i.test(sql), '017 must be documented as manual');
  assert(/like_count/i.test(sql), '017 like_count');
  assert(/comment_count/i.test(sql), '017 comment_count');
  assert(/CREATE TABLE IF NOT EXISTS community_publication_likes/i.test(sql), '017 likes table');
  assert(/CREATE TABLE IF NOT EXISTS community_publication_comments/i.test(sql), '017 comments table');
  assert(/CREATE TABLE IF NOT EXISTS community_comment_ephemeral_traces/i.test(sql), '017 traces table');
  assert(/UNIQUE \(community_publication_id, user_id\)/i.test(sql), '017 unique like');
  assert(/'visible'/i.test(sql) && /'author_deleted'/i.test(sql) && /'moderated'/i.test(sql), '017 comment statuses');
  assert(/char_length\(body\) <= 200/i.test(sql), '017 comment max 200');
  assert(/char_length\(btrim\(body\)\) >= 2/i.test(sql), '017 comment min 2');
  assert(/ON DELETE CASCADE/i.test(sql), '017 cascade from publication');
  assert(!/community_members/i.test(code), '017 must not FK community_members');
  assert(!/\bpublication_media\b/i.test(code.replace(/community_publication/g, '')), '017 must not alter publication_media');
  const tracesBlock = sql.split(/CREATE TABLE IF NOT EXISTS community_comment_ephemeral_traces/i)[1] || '';
  assert(
    !/REFERENCES community_publications/i.test(tracesBlock),
    '017 traces must not FK publications'
  );
  assert(!/ON DELETE CASCADE/i.test(tracesBlock), '017 traces must not cascade from publications');
  console.log('SQL file OK (sql/017_create_community_publication_interactions.sql inspected, not applied).');
}

inspectSqlFile();
console.log('Community publication interactions schema check succeeded (fichier uniquement, sans Neon).');
