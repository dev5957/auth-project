const pool = require('../db');
const AppError = require('../errors/AppError');
const {
  parseCommunityId,
  parseTargetUserId,
  parseCreateCommunityInput,
  parseSearchQuery,
  parseListQuery,
  parseRolePatch,
  escapeIlikePattern,
  VISIBILITY_PRIVATE,
} = require('../validators/communityFields');

const NOT_FOUND = 'Community not found';

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

function toPublicCommunity(row) {
  return {
    id: formatId(row.id),
    name: row.name,
    description: row.description == null ? null : row.description,
    visibility: VISIBILITY_PRIVATE,
    my_role: row.my_role,
    member_count: Number(row.member_count) || 0,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

function toSearchPreview(row) {
  return {
    id: formatId(row.id),
    name: row.name,
    description: row.description == null ? null : row.description,
    member_count: Number(row.member_count) || 0,
  };
}

function toPublicMember(row) {
  return {
    user_id: formatId(row.user_id),
    login: row.login,
    role: row.role,
    role_assigned_at: row.role_assigned_at == null ? null : toIso(row.role_assigned_at),
  };
}

const MEMBER_NOT_FOUND = 'Member not found';
const ROLE_CANNOT_BE_SET = 'role cannot be set';
const OWNER_CANNOT_BE_CHANGED = 'owner cannot be changed';
const OWNER_CANNOT_BE_REMOVED = 'owner cannot be removed';
const CANNOT_REMOVE_YOURSELF = 'cannot remove yourself';
const MEMBER_CANNOT_BE_REMOVED = 'member cannot be removed';
const OWNER_CANNOT_LEAVE = 'owner cannot leave without a successor';

async function lockCommunity(client, communityId) {
  const result = await client.query(
    `SELECT id, created_by
     FROM communities
     WHERE id = $1
     FOR UPDATE`,
    [communityId]
  );
  return result.rows[0] || null;
}

async function lockMembership(client, communityId, userId) {
  const result = await client.query(
    `SELECT user_id, role, role_assigned_at
     FROM community_members
     WHERE community_id = $1
       AND user_id = $2
     FOR UPDATE`,
    [communityId, userId]
  );
  return result.rows[0] || null;
}

async function loadPublicMember(client, communityId, userId) {
  const result = await client.query(
    `SELECT m.user_id, u.login, m.role, m.role_assigned_at
     FROM community_members m
     INNER JOIN users u ON u.id = m.user_id
     WHERE m.community_id = $1
       AND m.user_id = $2
     LIMIT 1`,
    [communityId, userId]
  );
  return result.rows[0] ? toPublicMember(result.rows[0]) : null;
}

async function deleteMembership(client, communityId, userId) {
  await client.query(
    `DELETE FROM community_members
     WHERE community_id = $1
       AND user_id = $2`,
    [communityId, userId]
  );
}

async function assertExactlyOneOwner(client, communityId) {
  const result = await client.query(
    `SELECT COUNT(*)::int AS owner_count
     FROM community_members
     WHERE community_id = $1
       AND role = 'owner'`,
    [communityId]
  );
  const ownerCount = Number(result.rows[0] && result.rows[0].owner_count);
  if (ownerCount !== 1) {
    throw new AppError(500, 'owner invariant violated');
  }
}

async function lockOldestAdmin(client, communityId) {
  const result = await client.query(
    `SELECT user_id, role, role_assigned_at
     FROM community_members
     WHERE community_id = $1
       AND role = 'admin'
     ORDER BY role_assigned_at ASC NULLS LAST, user_id ASC
     LIMIT 1
     FOR UPDATE`,
    [communityId]
  );
  return result.rows[0] || null;
}

async function transferOwnershipAndLeave(client, communityId, ownerUserId) {
  const successor = await lockOldestAdmin(client, communityId);
  if (!successor) {
    throw new AppError(400, OWNER_CANNOT_LEAVE);
  }

  // Unique index community_members_one_owner_per_community_key is checked
  // per statement (not deferrable). Promoting the successor while the current
  // owner row still exists would create two owners and abort the transaction.
  await deleteMembership(client, communityId, ownerUserId);
  await client.query(
    `UPDATE community_members
     SET role = 'owner',
         role_assigned_at = NULL,
         updated_at = NOW()
     WHERE community_id = $1
       AND user_id = $2
       AND role = 'admin'`,
    [communityId, successor.user_id]
  );
  await assertExactlyOneOwner(client, communityId);

  const publicSuccessor = await loadPublicMember(client, communityId, successor.user_id);
  return {
    left: true,
    transferred: true,
    successor: publicSuccessor,
  };
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

async function createCommunity(userId, body, deps = {}) {
  const input = parseCreateCommunityInput(body);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const inserted = await client.query(
      `INSERT INTO communities (
         name,
         description,
         visibility,
         created_by
       )
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [input.name, input.description, VISIBILITY_PRIVATE, userId]
    );
    const community = inserted.rows[0];
    await client.query(
      `INSERT INTO community_members (
         community_id,
         user_id,
         role
       )
       VALUES ($1, $2, $3)`,
      [community.id, userId, 'owner']
    );
    return toPublicCommunity({
      ...community,
      my_role: 'owner',
      member_count: 1,
    });
  });
}

async function listMyCommunities(userId, query, deps = {}) {
  const { limit } = parseListQuery(query);
  requireDatabase();
  const db = deps.db || pool;
  const result = await db.query(
    `SELECT c.id,
            c.name,
            c.description,
            c.visibility,
            c.created_at,
            c.updated_at,
            m.role AS my_role,
            (
              SELECT COUNT(*)::int
              FROM community_members cm
              WHERE cm.community_id = c.id
            ) AS member_count
     FROM communities c
     INNER JOIN community_members m
       ON m.community_id = c.id
      AND m.user_id = $1
     ORDER BY c.created_at DESC, c.id DESC
     LIMIT $2`,
    [userId, limit]
  );
  return {
    items: result.rows.map(toPublicCommunity),
  };
}

async function getCommunityById(userId, rawId, deps = {}) {
  const id = parseCommunityId(rawId);
  requireDatabase();
  const db = deps.db || pool;
  const result = await db.query(
    `SELECT c.id,
            c.name,
            c.description,
            c.visibility,
            c.created_at,
            c.updated_at,
            m.role AS my_role,
            (
              SELECT COUNT(*)::int
              FROM community_members cm
              WHERE cm.community_id = c.id
            ) AS member_count
     FROM communities c
     INNER JOIN community_members m
       ON m.community_id = c.id
      AND m.user_id = $1
     WHERE c.id = $2
     LIMIT 1`,
    [userId, id]
  );
  const row = result.rows[0];
  if (!row) {
    throw new AppError(404, NOT_FOUND);
  }
  return toPublicCommunity(row);
}

async function searchCommunities(userId, query, deps = {}) {
  const { q, limit } = parseSearchQuery(query);
  requireDatabase();
  const db = deps.db || pool;
  const pattern = `%${escapeIlikePattern(q)}%`;
  const result = await db.query(
    `SELECT c.id,
            c.name,
            c.description,
            (
              SELECT COUNT(*)::int
              FROM community_members cm
              WHERE cm.community_id = c.id
            ) AS member_count
     FROM communities c
     WHERE c.name ILIKE $1 ESCAPE '\\'
     ORDER BY c.name ASC, c.id ASC
     LIMIT $2`,
    [pattern, limit]
  );
  return {
    items: result.rows.map(toSearchPreview),
  };
}

async function listCommunityMembers(userId, rawId, deps = {}) {
  const id = parseCommunityId(rawId);
  requireDatabase();
  const db = deps.db || pool;
  const membership = await db.query(
    `SELECT role
     FROM community_members
     WHERE community_id = $1
       AND user_id = $2
     LIMIT 1`,
    [id, userId]
  );
  if (!membership.rows[0]) {
    throw new AppError(404, NOT_FOUND);
  }
  const result = await db.query(
    `SELECT m.user_id,
            u.login,
            m.role,
            m.role_assigned_at
     FROM community_members m
     INNER JOIN users u ON u.id = m.user_id
     WHERE m.community_id = $1
     ORDER BY
       CASE m.role
         WHEN 'owner' THEN 0
         WHEN 'admin' THEN 1
         ELSE 2
       END,
       m.user_id ASC`,
    [id]
  );
  return {
    items: result.rows.map(toPublicMember),
  };
}

async function updateMemberRole(actorUserId, rawCommunityId, rawTargetUserId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const targetUserId = parseTargetUserId(rawTargetUserId);
  const { role } = parseRolePatch(body);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const community = await lockCommunity(client, communityId);
    if (!community) {
      throw new AppError(404, NOT_FOUND);
    }

    const actor = await lockMembership(client, communityId, actorUserId);
    if (!actor) {
      throw new AppError(404, NOT_FOUND);
    }
    if (actor.role !== 'owner') {
      throw new AppError(400, ROLE_CANNOT_BE_SET);
    }
    if (Number(targetUserId) === Number(actorUserId)) {
      throw new AppError(400, ROLE_CANNOT_BE_SET);
    }

    const target = await lockMembership(client, communityId, targetUserId);
    if (!target) {
      throw new AppError(404, NOT_FOUND);
    }
    if (target.role === 'owner') {
      throw new AppError(400, OWNER_CANNOT_BE_CHANGED);
    }

    if (role === 'admin') {
      await client.query(
        `UPDATE community_members
         SET role = $1,
             role_assigned_at = NOW(),
             updated_at = NOW()
         WHERE community_id = $2
           AND user_id = $3`,
        [role, communityId, targetUserId]
      );
    } else {
      await client.query(
        `UPDATE community_members
         SET role = $1,
             role_assigned_at = NULL,
             updated_at = NOW()
         WHERE community_id = $2
           AND user_id = $3`,
        [role, communityId, targetUserId]
      );
    }

    await assertExactlyOneOwner(client, communityId);
    return loadPublicMember(client, communityId, targetUserId);
  });
}

async function removeMember(actorUserId, rawCommunityId, rawTargetUserId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const targetUserId = parseTargetUserId(rawTargetUserId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const community = await lockCommunity(client, communityId);
    if (!community) {
      throw new AppError(404, NOT_FOUND);
    }

    const actor = await lockMembership(client, communityId, actorUserId);
    if (!actor) {
      throw new AppError(404, NOT_FOUND);
    }
    if (actor.role !== 'owner') {
      throw new AppError(400, MEMBER_CANNOT_BE_REMOVED);
    }
    if (Number(targetUserId) === Number(actorUserId)) {
      throw new AppError(400, CANNOT_REMOVE_YOURSELF);
    }

    const target = await lockMembership(client, communityId, targetUserId);
    if (!target) {
      throw new AppError(404, MEMBER_NOT_FOUND);
    }
    if (target.role === 'owner') {
      throw new AppError(400, OWNER_CANNOT_BE_REMOVED);
    }

    await deleteMembership(client, communityId, targetUserId);
    await assertExactlyOneOwner(client, communityId);
    return { removed: true };
  });
}

async function leaveCommunity(actorUserId, rawCommunityId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  requireDatabase();
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const community = await lockCommunity(client, communityId);
    if (!community) {
      throw new AppError(404, NOT_FOUND);
    }

    const actor = await lockMembership(client, communityId, actorUserId);
    if (!actor) {
      throw new AppError(404, NOT_FOUND);
    }

    if (actor.role === 'owner') {
      return transferOwnershipAndLeave(client, communityId, actorUserId);
    }

    await deleteMembership(client, communityId, actorUserId);
    await assertExactlyOneOwner(client, communityId);
    return { left: true, transferred: false };
  });
}

module.exports = {
  NOT_FOUND,
  MEMBER_NOT_FOUND,
  ROLE_CANNOT_BE_SET,
  OWNER_CANNOT_BE_CHANGED,
  OWNER_CANNOT_BE_REMOVED,
  CANNOT_REMOVE_YOURSELF,
  MEMBER_CANNOT_BE_REMOVED,
  OWNER_CANNOT_LEAVE,
  createCommunity,
  listMyCommunities,
  getCommunityById,
  searchCommunities,
  listCommunityMembers,
  updateMemberRole,
  removeMember,
  leaveCommunity,
  toPublicCommunity,
  toSearchPreview,
};
