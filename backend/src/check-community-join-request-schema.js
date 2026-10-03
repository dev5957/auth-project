const fs = require('fs');
const path = require('path');

const SQL_PATH = path.join(__dirname, '..', 'sql', '014_create_community_join_requests.sql');
const SQL_012 = path.join(__dirname, '..', 'sql', '012_create_communities.sql');
const SQL_013 = path.join(__dirname, '..', 'sql', '013_create_community_invitations.sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function inspectJoinRequestSql() {
  const sql = fs.readFileSync(SQL_PATH, 'utf8');
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

  assert(/MANUELLEMENT/i.test(sql), '014 must be documented as manual');
  assert(/CREATE TABLE IF NOT EXISTS community_join_requests/i.test(sql), '014 must CREATE community_join_requests');
  assert(/GENERATED ALWAYS AS IDENTITY/i.test(sql), '014 ids must be IDENTITY');
  assert(!/\bON DELETE CASCADE\b/i.test(code), '014 must not CASCADE deletes');
  assert(!/\bDROP\s+TABLE\b/i.test(code), '014 must not DROP TABLE');
  assert(!/\bpublications\b/i.test(code), '014 must not alter publications');
  assert(!/\bpublication_media\b/i.test(code), '014 must not alter publication_media');
  assert(!/\bcommunity_invitations\b/i.test(code), '014 must not alter community_invitations');
  assert(!/\bcommunity_invitation_declines\b/i.test(code), '014 must not alter decline counters');
  assert(!/decline_count/i.test(code), '014 must not add a decline counter');

  assert(/REFERENCES communities \(id\) ON DELETE RESTRICT/i.test(sql), '014 community FK RESTRICT');
  assert(/REFERENCES users \(id\) ON DELETE RESTRICT/i.test(sql), '014 user FK RESTRICT');
  assert(/'pending',\s*'accepted',\s*'declined',\s*'cancelled'/i.test(sql), '014 statuses');
  assert(/community_join_requests_one_pending_per_pair_key/i.test(sql), '014 unique pending index');
  assert(/WHERE status = 'pending'/i.test(sql), '014 partial unique pending');
  assert(/community_join_requests_community_status_created_idx/i.test(sql), '014 community status index');
  assert(/community_join_requests_user_created_idx/i.test(sql), '014 requester index');
  assert(/\buser_id\b/i.test(sql), '014 requester column user_id');

  console.log('SQL file OK (sql/014_create_community_join_requests.sql inspected, not applied).');
}

function inspectPriorMigrationsUnchanged() {
  const sql012 = fs.readFileSync(SQL_012, 'utf8');
  const sql013 = fs.readFileSync(SQL_013, 'utf8');
  assert(!/community_join_requests/i.test(sql012), '012 must not mention join requests');
  assert(!/community_join_requests/i.test(sql013), '013 must not mention join requests');
  assert(/Pas de table de demandes/i.test(sql013), '013 still defers join requests');
  console.log('SQL 012/013 unchanged regarding join requests.');
}

inspectJoinRequestSql();
inspectPriorMigrationsUnchanged();
console.log('Community join-request schema check succeeded (fichier uniquement, sans Neon).');
