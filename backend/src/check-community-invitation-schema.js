const fs = require('fs');
const path = require('path');

const SQL_PATH = path.join(__dirname, '..', 'sql', '013_create_community_invitations.sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function inspectSqlFile() {
  const sql = fs.readFileSync(SQL_PATH, 'utf8');
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

  assert(/MANUELLEMENT/i.test(sql), '013 must be documented as manual');
  assert(/CREATE TABLE IF NOT EXISTS community_invitations/i.test(sql), '013 must CREATE community_invitations');
  assert(
    /CREATE TABLE IF NOT EXISTS community_invitation_declines/i.test(sql),
    '013 must CREATE community_invitation_declines'
  );
  assert(/GENERATED ALWAYS AS IDENTITY/i.test(sql), '013 ids must be IDENTITY');
  assert(!/\bON DELETE CASCADE\b/i.test(code), '013 must not CASCADE deletes');
  assert(!/\bDROP\s+TABLE\b/i.test(code), '013 must not DROP TABLE');
  assert(!/\bpublications\b/i.test(code), '013 must not alter publications');
  assert(!/\bpublication_media\b/i.test(code), '013 must not alter publication_media');
  assert(!/community_join/i.test(code), '013 must not create join-request tables');
  assert(!/join_request/i.test(code), '013 must not mention join_request schema');

  assert(/REFERENCES communities \(id\) ON DELETE RESTRICT/i.test(sql), '013 community FKs RESTRICT');
  assert(/REFERENCES users \(id\) ON DELETE RESTRICT/i.test(sql), '013 user FKs RESTRICT');

  assert(/'pending',\s*'accepted',\s*'declined',\s*'replaced',\s*'cancelled'/i.test(sql), '013 statuses');
  assert(/cancelled/i.test(sql), '013 cancelled status');
  assert(/community_invitations_one_pending_per_pair_key/i.test(sql), '013 unique pending index');
  assert(/WHERE status = 'pending'/i.test(sql), '013 partial unique pending');
  assert(/community_invitations_invitee_status_created_idx/i.test(sql), '013 inbox index');
  assert(/community_invitations_community_status_idx/i.test(sql), '013 community status index');
  assert(/invitee_user_id <> invited_by_user_id/i.test(sql), '013 no self-invite check');

  assert(/community_invitation_declines_pkey/i.test(sql), '013 decline PK pair');
  assert(/decline_count >= 0 AND decline_count <= 5/i.test(sql), '013 decline_count bounds');
  assert(/PRIMARY KEY \(community_id, invitee_user_id\)/i.test(sql), '013 decline pair identity');

  console.log('SQL file OK (sql/013_create_community_invitations.sql inspected, not applied).');
}

inspectSqlFile();
console.log('Community invitation schema check succeeded (fichier uniquement, sans Neon).');
