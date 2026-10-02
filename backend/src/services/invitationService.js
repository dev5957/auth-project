const pool = require('../db');
const AppError = require('../errors/AppError');
const { parseCommunityId } = require('../validators/communityFields');
const {
  parseInviteBody,
  parseInvitationId,
  DECLINE_LIMIT,
} = require('../validators/invitationFields');

const NOT_FOUND = 'Community not found';
const USER_NOT_FOUND = 'User not found';
const INVITATION_NOT_FOUND = 'Invitation not found';
const ALREADY_MEMBER = 'user is already a member';
const CANNOT_INVITE_SELF = 'cannot invite yourself';
const CANNOT_SEND = 'invitation cannot be sent';
const LIMIT_REACHED = 'invitation limit reached';
const NOT_PENDING = 'invitation is not pending';

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function formatId(value) {
  if (typeof value === 'bigint') {
    const asNumber = Number(value);
    return Number.isSafeInteger(asNumber) ? asNumber : value.toString();
  }
  if (typeof value === 'string' && /^\d+$/.test(value)) {
    const asNumber = Number(value);
    return Number.isSafeInteger(asNumber) ? asNumber : value;
  }
  return value;
}

function toIso(value) {
  if (value == null) {
    return null;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toISOString();
}

function toCreatedInvitation(row) {
  return {
    id: formatId(row.id),
    community_id: formatId(row.community_id),
    invitee_user_id: formatId(row.invitee_user_id),
    status: row.status,
    created_at: toIso(row.created_at),
  };
}

function toInboxInvitation(row) {
  return {
    id: formatId(row.id),
    community_id: formatId(row.community_id),
    community_name: row.community_name,
    invited_by_login: row.invited_by_login,
    status: row.status,
    created_at: toIso(row.created_at),
  };
}

function toSentInvitation(row) {
  const login = row.invitee_login;
  return {
    id: formatId(row.id),
    invitee_login: typeof login === 'string' && login.trim() ? login : null,
    status: row.status,
    created_at: toIso(row.created_at),
    declined_at: row.status === 'declined' ? toIso(row.declined_at) : null,
  };
}

function isUniqueViolation(err) {
  return err && (err.code === '23505' || err.constraint === 'community_invitations_one_pending_per_pair_key');
}

async function withTransaction(db, fn) {
  const client = await db.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    committed = true;
    return result;
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // ignore rollback errors
      }
    }
    throw err;
  } finally {
    client.release();
  }
}

async function lockCommunity(client, communityId) {
  const result = await client.query(
    `SELECT id
     FROM communities
     WHERE id = $1
     FOR UPDATE`,
    [communityId]
  );
  return result.rows[0] || null;
}

async function lockMembership(client, communityId, userId) {
  const result = await client.query(
    `SELECT user_id, role
     FROM community_members
     WHERE community_id = $1
       AND user_id = $2
     FOR UPDATE`,
    [communityId, userId]
  );
  return result.rows[0] || null;
}

async function requireOwnerActor(client, communityId, actorUserId) {
  const community = await lockCommunity(client, communityId);
  const membership = await lockMembership(client, communityId, actorUserId);
  if (!community || !membership) {
    throw new AppError(404, NOT_FOUND);
  }
  if (membership.role !== 'owner') {
    throw new AppError(400, CANNOT_SEND);
  }
  return membership;
}

async function lockDeclineCounter(client, communityId, inviteeUserId) {
  await client.query(
    `INSERT INTO community_invitation_declines (
       community_id,
       invitee_user_id,
       decline_count
     )
     VALUES ($1, $2, 0)
     ON CONFLICT (community_id, invitee_user_id)
     DO NOTHING`,
    [communityId, inviteeUserId]
  );
  const result = await client.query(
    `SELECT decline_count
     FROM community_invitation_declines
     WHERE community_id = $1
       AND invitee_user_id = $2
     FOR UPDATE`,
    [communityId, inviteeUserId]
  );
  return result.rows[0];
}

async function closePendingJoinRequestsIfPresent(_client, _communityId, _userId) {
  // Lot 2.4: clôturer les demandes d’adhésion pending du même couple
  // sans les compter comme un refus d’invitation.
}

async function createInvitation(actorUserId, rawCommunityId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const { userId: inviteeUserId } = parseInviteBody(body);
  requireDatabase();
  const db = deps.db || pool;

  if (Number(inviteeUserId) === Number(actorUserId)) {
    throw new AppError(400, CANNOT_INVITE_SELF);
  }

  try {
    return await withTransaction(db, async (client) => {
      await requireOwnerActor(client, communityId, actorUserId);

      const user = await client.query(
        `SELECT id
         FROM users
         WHERE id = $1
         LIMIT 1`,
        [inviteeUserId]
      );
      if (!user.rows[0]) {
        throw new AppError(404, USER_NOT_FOUND);
      }

      const existingMember = await lockMembership(client, communityId, inviteeUserId);
      if (existingMember) {
        throw new AppError(400, ALREADY_MEMBER);
      }

      const declines = await lockDeclineCounter(client, communityId, inviteeUserId);
      if (!declines || Number(declines.decline_count) >= DECLINE_LIMIT) {
        throw new AppError(400, LIMIT_REACHED);
      }

      await client.query(
        `UPDATE community_invitations
         SET status = 'replaced',
             updated_at = NOW()
         WHERE community_id = $1
           AND invitee_user_id = $2
           AND status = 'pending'`,
        [communityId, inviteeUserId]
      );

      const inserted = await client.query(
        `INSERT INTO community_invitations (
           community_id,
           invitee_user_id,
           invited_by_user_id,
           status
         )
         VALUES ($1, $2, $3, 'pending')
         RETURNING id, community_id, invitee_user_id, status, created_at`,
        [communityId, inviteeUserId, actorUserId]
      );
      return toCreatedInvitation(inserted.rows[0]);
    });
  } catch (err) {
    if (isUniqueViolation(err)) {
      throw new AppError(400, CANNOT_SEND);
    }
    throw err;
  }
}

async function listReceivedInvitations(actorUserId, deps = {}) {
  requireDatabase();
  const db = deps.db || pool;
  const result = await db.query(
    `SELECT i.id,
            i.community_id,
            c.name AS community_name,
            u.login AS invited_by_login,
            i.status,
            i.created_at
     FROM community_invitations i
     INNER JOIN communities c ON c.id = i.community_id
     INNER JOIN users u ON u.id = i.invited_by_user_id
     WHERE i.invitee_user_id = $1
       AND i.status = 'pending'
     ORDER BY i.created_at DESC, i.id DESC`,
    [actorUserId]
  );
  return {
    items: result.rows.map(toInboxInvitation),
  };
}

async function listSentInvitations(actorUserId, rawCommunityId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  requireDatabase();
  const db = deps.db || pool;
  const access = await db.query(
    `SELECT m.role
     FROM communities c
     INNER JOIN community_members m
       ON m.community_id = c.id
      AND m.user_id = $1
     WHERE c.id = $2
     LIMIT 1`,
    [actorUserId, communityId]
  );
  if (!access.rows[0] || access.rows[0].role !== 'owner') {
    throw new AppError(404, NOT_FOUND);
  }

  const result = await db.query(
    `SELECT i.id,
            u.login AS invitee_login,
            i.status,
            i.created_at,
            CASE
              WHEN i.status = 'declined' THEN i.updated_at
              ELSE NULL
            END AS declined_at
     FROM community_invitations i
     INNER JOIN users u ON u.id = i.invitee_user_id
     WHERE i.community_id = $1
       AND i.status IN ('pending', 'accepted', 'declined')
     ORDER BY i.created_at DESC, i.id DESC`,
    [communityId]
  );
  return {
    items: result.rows.map(toSentInvitation),
  };
}

async function lockInvitation(client, invitationId) {
  const result = await client.query(
    `SELECT id,
            community_id,
            invitee_user_id,
            invited_by_user_id,
            status
     FROM community_invitations
     WHERE id = $1
     FOR UPDATE`,
    [invitationId]
  );
  return result.rows[0] || null;
}

async function loadInvitation(client, invitationId) {
  const result = await client.query(
    `SELECT id,
            community_id,
            invitee_user_id,
            invited_by_user_id,
            status
     FROM community_invitations
     WHERE id = $1`,
    [invitationId]
  );
  return result.rows[0] || null;
}

async function lockInvitationForCommunity(client, invitationId, communityId) {
  await lockCommunity(client, communityId);
  return lockInvitation(client, invitationId);
}

async function acceptInvitation(actorUserId, rawInvitationId, deps = {}) {
  const invitationId = parseInvitationId(rawInvitationId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const preview = await loadInvitation(client, invitationId);
    if (!preview || Number(preview.invitee_user_id) !== Number(actorUserId)) {
      throw new AppError(404, INVITATION_NOT_FOUND);
    }

    const invitation = await lockInvitationForCommunity(
      client,
      invitationId,
      preview.community_id
    );
    if (!invitation || Number(invitation.invitee_user_id) !== Number(actorUserId)) {
      throw new AppError(404, INVITATION_NOT_FOUND);
    }
    if (invitation.status !== 'pending') {
      throw new AppError(400, NOT_PENDING);
    }

    const existingMember = await lockMembership(
      client,
      invitation.community_id,
      actorUserId
    );
    if (existingMember) {
      throw new AppError(400, ALREADY_MEMBER);
    }

    await client.query(
      `INSERT INTO community_members (
         community_id,
         user_id,
         role
       )
       VALUES ($1, $2, 'member')`,
      [invitation.community_id, actorUserId]
    );

    await client.query(
      `UPDATE community_invitations
       SET status = 'accepted',
           updated_at = NOW()
       WHERE id = $1
         AND status = 'pending'`,
      [invitationId]
    );

    await client.query(
      `UPDATE community_invitation_declines
       SET decline_count = 0,
           updated_at = NOW()
       WHERE community_id = $1
         AND invitee_user_id = $2`,
      [invitation.community_id, actorUserId]
    );

    await closePendingJoinRequestsIfPresent(client, invitation.community_id, actorUserId);

    return {
      invitation: {
        id: formatId(invitation.id),
        community_id: formatId(invitation.community_id),
        status: 'accepted',
      },
      membership: {
        user_id: formatId(actorUserId),
        role: 'member',
      },
    };
  });
}

async function declineInvitation(actorUserId, rawInvitationId, deps = {}) {
  const invitationId = parseInvitationId(rawInvitationId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const preview = await loadInvitation(client, invitationId);
    if (!preview || Number(preview.invitee_user_id) !== Number(actorUserId)) {
      throw new AppError(404, INVITATION_NOT_FOUND);
    }

    const invitation = await lockInvitationForCommunity(
      client,
      invitationId,
      preview.community_id
    );
    if (!invitation || Number(invitation.invitee_user_id) !== Number(actorUserId)) {
      throw new AppError(404, INVITATION_NOT_FOUND);
    }
    if (invitation.status !== 'pending') {
      throw new AppError(400, NOT_PENDING);
    }

    const updated = await client.query(
      `UPDATE community_invitations
       SET status = 'declined',
           updated_at = NOW()
       WHERE id = $1
         AND status = 'pending'
       RETURNING id`,
      [invitationId]
    );
    if (!updated.rows[0]) {
      throw new AppError(400, NOT_PENDING);
    }

    const declines = await lockDeclineCounter(
      client,
      invitation.community_id,
      actorUserId
    );
    if (Number(declines.decline_count) >= DECLINE_LIMIT) {
      throw new AppError(400, LIMIT_REACHED);
    }

    await client.query(
      `UPDATE community_invitation_declines
       SET decline_count = decline_count + 1,
           updated_at = NOW()
       WHERE community_id = $1
         AND invitee_user_id = $2
         AND decline_count < $3`,
      [invitation.community_id, actorUserId, DECLINE_LIMIT]
    );

    return {
      id: formatId(invitation.id),
      status: 'declined',
    };
  });
}

async function cancelInvitation(actorUserId, rawInvitationId, deps = {}) {
  const invitationId = parseInvitationId(rawInvitationId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const preview = await loadInvitation(client, invitationId);
    if (!preview) {
      throw new AppError(404, INVITATION_NOT_FOUND);
    }

    await requireOwnerActor(client, preview.community_id, actorUserId);

    const invitation = await lockInvitation(client, invitationId);
    if (!invitation) {
      throw new AppError(404, INVITATION_NOT_FOUND);
    }
    if (invitation.status !== 'pending') {
      throw new AppError(400, NOT_PENDING);
    }

    const updated = await client.query(
      `UPDATE community_invitations
       SET status = 'cancelled',
           updated_at = NOW()
       WHERE id = $1
         AND status = 'pending'
       RETURNING id`,
      [invitationId]
    );
    if (!updated.rows[0]) {
      throw new AppError(400, NOT_PENDING);
    }

    return {
      id: formatId(invitation.id),
      status: 'cancelled',
    };
  });
}

module.exports = {
  NOT_FOUND,
  USER_NOT_FOUND,
  INVITATION_NOT_FOUND,
  ALREADY_MEMBER,
  CANNOT_INVITE_SELF,
  CANNOT_SEND,
  LIMIT_REACHED,
  NOT_PENDING,
  DECLINE_LIMIT,
  createInvitation,
  listReceivedInvitations,
  listSentInvitations,
  acceptInvitation,
  declineInvitation,
  cancelInvitation,
  closePendingJoinRequestsIfPresent,
};
