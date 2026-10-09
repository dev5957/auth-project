const pool = require('../db');
const AppError = require('../errors/AppError');
const { parseCommunityId } = require('../validators/communityFields');
const {
  parseJoinRequestCreateBody,
  parseJoinRequestId,
} = require('../validators/joinRequestFields');

const NOT_FOUND = 'Community not found';
const JOIN_REQUEST_NOT_FOUND = 'Join request not found';
const ALREADY_MEMBER = 'user is already a member';
const ALREADY_PENDING = 'join request already pending';
const NOT_PENDING = 'join request is not pending';

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

function toCreatedJoinRequest(row) {
  return {
    id: formatId(row.id),
    community_id: formatId(row.community_id),
    status: row.status,
    created_at: toIso(row.created_at),
  };
}

function toOwnerJoinRequest(row) {
  const login = row.requester_login;
  return {
    id: formatId(row.id),
    requester_login: typeof login === 'string' && login.trim() ? login : null,
    status: row.status,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

function toMineJoinRequest(row) {
  return {
    id: formatId(row.id),
    community_id: formatId(row.community_id),
    community_name: row.community_name,
    status: row.status,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

function isPendingJoinUniqueViolation(err) {
  return (
    err &&
    (err.code === '23505' || err.constraint === 'community_join_requests_one_pending_per_pair_key')
  );
}

function isMembershipUniqueViolation(err) {
  return (
    err &&
    (err.code === '23505' || err.constraint === 'community_members_community_id_user_id_key')
  );
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

async function requireOwnerForJoinRequests(client, communityId, actorUserId) {
  const community = await lockCommunity(client, communityId);
  const membership = await lockMembership(client, communityId, actorUserId);
  if (!community || !membership || membership.role !== 'owner') {
    throw new AppError(404, NOT_FOUND);
  }
  return membership;
}

async function closePendingInvitationsWithoutDecline(client, communityId, userId) {
  await client.query(
    `UPDATE community_invitations
     SET status = 'cancelled',
         updated_at = NOW()
     WHERE community_id = $1
       AND invitee_user_id = $2
       AND status = 'pending'`,
    [communityId, userId]
  );
}

async function createJoinRequest(actorUserId, rawCommunityId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  parseJoinRequestCreateBody(body);
  requireDatabase();
  const db = deps.db || pool;

  try {
    return await withTransaction(db, async (client) => {
      const community = await lockCommunity(client, communityId);
      if (!community) {
        throw new AppError(404, NOT_FOUND);
      }

      const membership = await lockMembership(client, communityId, actorUserId);
      if (membership) {
        throw new AppError(400, ALREADY_MEMBER);
      }

      const inserted = await client.query(
        `INSERT INTO community_join_requests (
           community_id,
           user_id,
           status
         )
         VALUES ($1, $2, 'pending')
         RETURNING id, community_id, status, created_at`,
        [communityId, actorUserId]
      );
      return toCreatedJoinRequest(inserted.rows[0]);
    });
  } catch (err) {
    if (isPendingJoinUniqueViolation(err)) {
      throw new AppError(400, ALREADY_PENDING);
    }
    throw err;
  }
}

async function listCommunityJoinRequests(actorUserId, rawCommunityId, deps = {}) {
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
    `SELECT r.id,
            u.login AS requester_login,
            r.status,
            r.created_at,
            r.updated_at
     FROM community_join_requests r
     INNER JOIN users u ON u.id = r.user_id
     WHERE r.community_id = $1
       AND r.status IN ('pending', 'accepted', 'declined')
     ORDER BY r.created_at DESC, r.id DESC`,
    [communityId]
  );
  return {
    items: result.rows.map(toOwnerJoinRequest),
  };
}

async function listMyJoinRequests(actorUserId, deps = {}) {
  requireDatabase();
  const db = deps.db || pool;
  const result = await db.query(
    `SELECT r.id,
            r.community_id,
            c.name AS community_name,
            r.status,
            r.created_at,
            r.updated_at
     FROM community_join_requests r
     INNER JOIN communities c ON c.id = r.community_id
     WHERE r.user_id = $1
     ORDER BY r.created_at DESC, r.id DESC`,
    [actorUserId]
  );
  return {
    items: result.rows.map(toMineJoinRequest),
  };
}

async function lockJoinRequest(client, requestId) {
  const result = await client.query(
    `SELECT id,
            community_id,
            user_id,
            status
     FROM community_join_requests
     WHERE id = $1
     FOR UPDATE`,
    [requestId]
  );
  return result.rows[0] || null;
}

async function acceptJoinRequest(actorUserId, rawCommunityId, rawRequestId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const requestId = parseJoinRequestId(rawRequestId);
  requireDatabase();
  const db = deps.db || pool;

  try {
    return await withTransaction(db, async (client) => {
      await requireOwnerForJoinRequests(client, communityId, actorUserId);

      const request = await lockJoinRequest(client, requestId);
      if (!request || Number(request.community_id) !== Number(communityId)) {
        throw new AppError(404, JOIN_REQUEST_NOT_FOUND);
      }
      if (request.status !== 'pending') {
        throw new AppError(400, NOT_PENDING);
      }

      const existingMember = await lockMembership(client, communityId, request.user_id);
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
        [communityId, request.user_id]
      );

      const updated = await client.query(
        `UPDATE community_join_requests
         SET status = 'accepted',
             updated_at = NOW()
         WHERE id = $1
           AND status = 'pending'
         RETURNING id`,
        [requestId]
      );
      if (!updated.rows[0]) {
        throw new AppError(400, NOT_PENDING);
      }

      await closePendingInvitationsWithoutDecline(client, communityId, request.user_id);

      return {
        join_request: {
          id: formatId(request.id),
          community_id: formatId(communityId),
          status: 'accepted',
        },
        membership: {
          user_id: formatId(request.user_id),
          role: 'member',
        },
      };
    });
  } catch (err) {
    if (isMembershipUniqueViolation(err)) {
      throw new AppError(400, ALREADY_MEMBER);
    }
    throw err;
  }
}

async function declineJoinRequest(actorUserId, rawCommunityId, rawRequestId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const requestId = parseJoinRequestId(rawRequestId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await requireOwnerForJoinRequests(client, communityId, actorUserId);

    const request = await lockJoinRequest(client, requestId);
    if (!request || Number(request.community_id) !== Number(communityId)) {
      throw new AppError(404, JOIN_REQUEST_NOT_FOUND);
    }
    if (request.status !== 'pending') {
      throw new AppError(400, NOT_PENDING);
    }

    const updated = await client.query(
      `UPDATE community_join_requests
       SET status = 'declined',
           updated_at = NOW()
       WHERE id = $1
         AND status = 'pending'
       RETURNING id`,
      [requestId]
    );
    if (!updated.rows[0]) {
      throw new AppError(400, NOT_PENDING);
    }

    return {
      id: formatId(request.id),
      status: 'declined',
    };
  });
}

module.exports = {
  NOT_FOUND,
  JOIN_REQUEST_NOT_FOUND,
  ALREADY_MEMBER,
  ALREADY_PENDING,
  NOT_PENDING,
  createJoinRequest,
  listCommunityJoinRequests,
  listMyJoinRequests,
  acceptJoinRequest,
  declineJoinRequest,
};
