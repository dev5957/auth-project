const http = require('http');
const express = require('express');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const {
  createCommunity,
  getCommunityById,
  listCommunityMembers,
  updateMemberRole,
  removeMember,
  leaveCommunity,
  NOT_FOUND,
  MEMBER_NOT_FOUND,
  ROLE_CANNOT_BE_SET,
  OWNER_CANNOT_BE_CHANGED,
  OWNER_CANNOT_BE_REMOVED,
  CANNOT_REMOVE_YOURSELF,
  MEMBER_CANNOT_BE_REMOVED,
  OWNER_CANNOT_LEAVE,
} = require('./services/communityService');
const pool = require('./db');
const errorHandler = require('./middleware/errorHandler');
const communityRoutes = require('./routes/communities');

const TEST_SECRET = 'community-members-test-secret';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const HTTP_PORT = 30484;

const OWNER_ID = 42;
const MEMBER_ID = 7;
const ADMIN_ID = 9;
const SECOND_ADMIN_ID = 13;
const STRANGER_ID = 11;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function expectAsyncAppError(promise, statusCode, message) {
  try {
    await promise;
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err && err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    assert(err.message === message, `unexpected message: ${err.message}`);
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function ownerCount(members, communityId) {
  return members.filter(
    (item) => Number(item.community_id) === Number(communityId) && item.role === 'owner'
  ).length;
}

function createLockTable() {
  const tails = new Map();
  return {
    async acquire(key) {
      const prev = tails.get(key) || Promise.resolve();
      let release;
      const next = new Promise((resolve) => {
        release = resolve;
      });
      tails.set(key, prev.then(() => next));
      await prev;
      return release;
    },
  };
}

function createMembersMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner42' },
    { id: MEMBER_ID, login: 'member7' },
    { id: ADMIN_ID, login: 'admin9' },
    { id: SECOND_ADMIN_ID, login: 'admin13' },
    { id: STRANGER_ID, login: 'stranger11' },
  ];
  const state = {
    communities: [],
    members: [],
  };
  let nextCommunityId = 1;
  let nextMemberId = 1;
  let failOwnerPromote = false;
  const locks = createLockTable();

  function clone() {
    return {
      communities: state.communities.map((row) => ({ ...row })),
      members: state.members.map((row) => ({ ...row })),
      nextCommunityId,
      nextMemberId,
    };
  }

  function memberCount(communityId) {
    return state.members.filter((item) => Number(item.community_id) === Number(communityId)).length;
  }

  async function query(sql, params = [], session) {
    const key = sqlKey(sql);
    if (key === 'BEGIN') {
      if (session) {
        await session.acquire('txn:global');
        session.snapshot = clone();
      }
      return { rows: [], rowCount: 0 };
    }
    if (key === 'COMMIT') {
      if (session) {
        session.snapshot = null;
        session.releaseLocks();
      }
      return { rows: [], rowCount: 0 };
    }
    if (key === 'ROLLBACK') {
      if (session && session.snapshot) {
        state.communities = session.snapshot.communities;
        state.members = session.snapshot.members;
        nextCommunityId = session.snapshot.nextCommunityId;
        nextMemberId = session.snapshot.nextMemberId;
        session.snapshot = null;
      }
      if (session) {
        session.releaseLocks();
      }
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('COMMUNITY_PUBLICATIONS') || key.includes('COMMUNITY_PUBLICATION_MEDIA')) {
      return { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITIES')) {
      const now = new Date();
      const row = {
        id: nextCommunityId,
        name: params[0],
        description: params[1],
        visibility: params[2],
        created_by: params[3],
        created_at: now,
        updated_at: now,
      };
      nextCommunityId += 1;
      state.communities.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_MEMBERS')) {
      const now = new Date();
      const row = {
        id: nextMemberId,
        community_id: Number(params[0]),
        user_id: Number(params[1]),
        role: params[2],
        role_assigned_at: null,
        created_at: now,
        updated_at: now,
      };
      nextMemberId += 1;
      state.members.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.includes('FROM COMMUNITIES') && key.includes('FOR UPDATE') && !key.includes('JOIN')) {
      const id = Number(params[0]);
      if (session) {
        await session.acquire(`community:${id}`);
      }
      const community = state.communities.find((item) => Number(item.id) === id);
      if (!community) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [{ id: community.id, created_by: community.created_by }], rowCount: 1 };
    }

    if (key.startsWith('DELETE FROM COMMUNITY_MEMBERS')) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      const index = state.members.findIndex(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      if (index < 0) {
        return { rows: [], rowCount: 0 };
      }
      state.members.splice(index, 1);
      return { rows: [], rowCount: 1 };
    }

    if (key.includes('AS OWNER_COUNT')) {
      return {
        rows: [{ owner_count: ownerCount(state.members, params[0]) }],
        rowCount: 1,
      };
    }

    if (key.includes("ROLE = 'ADMIN'") && key.includes('ORDER BY ROLE_ASSIGNED_AT')) {
      const communityId = Number(params[0]);
      const rows = state.members
        .filter((item) => Number(item.community_id) === communityId && item.role === 'admin')
        .sort((a, b) => {
          const ta = a.role_assigned_at ? new Date(a.role_assigned_at).getTime() : Number.MAX_SAFE_INTEGER;
          const tb = b.role_assigned_at ? new Date(b.role_assigned_at).getTime() : Number.MAX_SAFE_INTEGER;
          if (ta !== tb) {
            return ta - tb;
          }
          return Number(a.user_id) - Number(b.user_id);
        })
        .slice(0, 1);
      if (session && rows[0]) {
        await session.acquire(`member:${communityId}:${rows[0].user_id}`);
      }
      return {
        rows: rows.map((item) => ({
          user_id: item.user_id,
          role: item.role,
          role_assigned_at: item.role_assigned_at,
        })),
        rowCount: rows.length,
      };
    }

    if (key.startsWith('UPDATE COMMUNITY_MEMBERS') && key.includes("ROLE = 'OWNER'")) {
      if (failOwnerPromote) {
        throw new Error('forced successor promote failure');
      }
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      const otherOwner = state.members.find(
        (item) =>
          Number(item.community_id) === communityId &&
          item.role === 'owner' &&
          Number(item.user_id) !== userId
      );
      if (otherOwner) {
        const err = new Error(
          'duplicate key value violates unique constraint "community_members_one_owner_per_community_key"'
        );
        err.code = '23505';
        err.constraint = 'community_members_one_owner_per_community_key';
        throw err;
      }
      const row = state.members.find(
        (item) =>
          Number(item.community_id) === communityId &&
          Number(item.user_id) === userId &&
          item.role === 'admin'
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.role = 'owner';
      row.role_assigned_at = null;
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('UPDATE COMMUNITY_MEMBERS')) {
      const role = params[0];
      const communityId = Number(params[1]);
      const userId = Number(params[2]);
      const row = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.role = role;
      row.updated_at = new Date();
      if (key.includes('ROLE_ASSIGNED_AT = NOW()')) {
        row.role_assigned_at = new Date();
      } else if (key.includes('ROLE_ASSIGNED_AT = NULL')) {
        row.role_assigned_at = null;
      }
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.includes('WHERE C.ID = $2')) {
      const userId = Number(params[0]);
      const id = Number(params[1]);
      const community = state.communities.find((item) => Number(item.id) === id);
      const membership = state.members.find(
        (item) => Number(item.community_id) === id && Number(item.user_id) === userId
      );
      if (!community || !membership) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rows: [{ ...community, my_role: membership.role, member_count: memberCount(id) }],
        rowCount: 1,
      };
    }

    if (key.includes('INNER JOIN USERS U') && key.includes('AND M.USER_ID = $2')) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      const row = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      const user = users.find((item) => Number(item.id) === userId);
      if (!row || !user) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rows: [
          {
            user_id: row.user_id,
            login: user.login,
            role: row.role,
            role_assigned_at: row.role_assigned_at || null,
          },
        ],
        rowCount: 1,
      };
    }

    if (key.includes('INNER JOIN USERS U') && key.includes('WHERE M.COMMUNITY_ID = $1')) {
      const communityId = Number(params[0]);
      const order = { owner: 0, admin: 1, member: 2 };
      const rows = state.members
        .filter((item) => Number(item.community_id) === communityId)
        .map((item) => {
          const user = users.find((entry) => Number(entry.id) === Number(item.user_id));
          return {
            user_id: item.user_id,
            login: user ? user.login : 'unknown',
            role: item.role,
            role_assigned_at: item.role_assigned_at || null,
          };
        })
        .sort((a, b) => (order[a.role] ?? 9) - (order[b.role] ?? 9) || Number(a.user_id) - Number(b.user_id));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM COMMUNITY_MEMBERS') && key.includes('USER_ID = $2')) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      if (session && key.includes('FOR UPDATE')) {
        await session.acquire(`member:${communityId}:${userId}`);
      }
      const row = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rows: [{ user_id: row.user_id, role: row.role, role_assigned_at: row.role_assigned_at || null }],
        rowCount: 1,
      };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  function createSession() {
    const held = [];
    const session = {
      snapshot: null,
      async acquire(key) {
        const release = await locks.acquire(key);
        held.push(release);
      },
      releaseLocks() {
        while (held.length) {
          const release = held.pop();
          release();
        }
      },
      query(sql, params) {
        return query(sql, params, session);
      },
      release() {
        session.releaseLocks();
      },
    };
    return session;
  }

  return {
    state,
    setFailOwnerPromote(value) {
      failOwnerPromote = value;
    },
    addMember(communityId, userId, role, roleAssignedAt = null) {
      state.members.push({
        id: nextMemberId,
        community_id: Number(communityId),
        user_id: Number(userId),
        role,
        role_assigned_at: roleAssignedAt,
        created_at: new Date(),
        updated_at: new Date(),
      });
      nextMemberId += 1;
    },
    query,
    connect: async () => createSession(),
  };
}

function httpRequest({ port, method, urlPath, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const payload = body == null ? null : Buffer.from(JSON.stringify(body), 'utf8');
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers: {
          ...headers,
          ...(payload
            ? { 'Content-Type': 'application/json', 'Content-Length': String(payload.length) }
            : {}),
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try {
            json = JSON.parse(raw);
          } catch (_) {
            json = null;
          }
          resolve({ status: res.statusCode, json, raw });
        });
      }
    );
    req.on('error', reject);
    if (payload) {
      req.write(payload);
    }
    req.end();
  });
}

function authFor(userId, login) {
  const token = generateAccessToken({
    id: userId,
    login,
    auth_provider: 'local',
  });
  return { Authorization: `Bearer ${token}` };
}

async function main() {
  const previous = {
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    DATABASE_URL: process.env.DATABASE_URL,
  };
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://members-test/local';

  const db = createMembersMemory();
  const created = await createCommunity(OWNER_ID, { name: 'Cercle membres lot trois' }, { db });
  assert(ownerCount(db.state.members, created.id) === 1, 'create has one owner');

  db.addMember(created.id, MEMBER_ID, 'member');
  db.addMember(created.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
  db.addMember(created.id, SECOND_ADMIN_ID, 'admin', new Date('2026-02-01T00:00:00.000Z'));

  const promotedAgain = await updateMemberRole(OWNER_ID, created.id, MEMBER_ID, { role: 'admin' }, { db });
  assert(promotedAgain.role === 'admin', 'promote member');
  assert(promotedAgain.role_assigned_at, 'role_assigned_at set');
  const demoted = await updateMemberRole(OWNER_ID, created.id, MEMBER_ID, { role: 'member' }, { db });
  assert(demoted.role === 'member', 'demote admin');
  assert(demoted.role_assigned_at == null, 'cleared assigned at');
  await expectAsyncAppError(
    updateMemberRole(ADMIN_ID, created.id, MEMBER_ID, { role: 'admin' }, { db }),
    400,
    ROLE_CANNOT_BE_SET
  );
  await expectAsyncAppError(
    updateMemberRole(ADMIN_ID, created.id, ADMIN_ID, { role: 'member' }, { db }),
    400,
    ROLE_CANNOT_BE_SET
  );
  await expectAsyncAppError(
    updateMemberRole(MEMBER_ID, created.id, ADMIN_ID, { role: 'member' }, { db }),
    400,
    ROLE_CANNOT_BE_SET
  );
  await expectAsyncAppError(
    updateMemberRole(OWNER_ID, created.id, MEMBER_ID, { role: 'owner' }, { db }),
    400,
    'role is invalid'
  );
  await expectAsyncAppError(
    updateMemberRole(OWNER_ID, created.id, OWNER_ID, { role: 'admin' }, { db }),
    400,
    ROLE_CANNOT_BE_SET
  );
  await expectAsyncAppError(
    updateMemberRole(OWNER_ID, created.id, OWNER_ID, { role: 'member' }, { db }),
    400,
    ROLE_CANNOT_BE_SET
  );
  const other = await createCommunity(STRANGER_ID, { name: 'Autre cercle prive x' }, { db });
  await expectAsyncAppError(
    updateMemberRole(OWNER_ID, other.id, MEMBER_ID, { role: 'admin' }, { db }),
    404,
    NOT_FOUND
  );
  assert(ownerCount(db.state.members, created.id) === 1, 'owner unchanged after role ops');
  console.log('A OK roles promote/demote/protections');

  const removeTarget = MEMBER_ID;
  const removed = await removeMember(OWNER_ID, created.id, removeTarget, { db });
  assert(removed.removed === true, 'removed');
  assert(
    !db.state.members.some(
      (item) => Number(item.community_id) === Number(created.id) && Number(item.user_id) === removeTarget
    ),
    'membership deleted'
  );
  await expectAsyncAppError(getCommunityById(removeTarget, created.id, { db }), 404, NOT_FOUND);
  await expectAsyncAppError(removeMember(OWNER_ID, created.id, removeTarget, { db }), 404, MEMBER_NOT_FOUND);
  db.addMember(created.id, MEMBER_ID, 'member');
  await expectAsyncAppError(removeMember(OWNER_ID, created.id, OWNER_ID, { db }), 400, CANNOT_REMOVE_YOURSELF);
  await expectAsyncAppError(removeMember(ADMIN_ID, created.id, MEMBER_ID, { db }), 400, MEMBER_CANNOT_BE_REMOVED);
  await expectAsyncAppError(removeMember(MEMBER_ID, created.id, ADMIN_ID, { db }), 400, MEMBER_CANNOT_BE_REMOVED);
  await expectAsyncAppError(removeMember(OWNER_ID, created.id, STRANGER_ID, { db }), 404, MEMBER_NOT_FOUND);
  await expectAsyncAppError(removeMember(OWNER_ID, other.id, MEMBER_ID, { db }), 404, NOT_FOUND);
  await removeMember(OWNER_ID, created.id, ADMIN_ID, { db });
  assert(ownerCount(db.state.members, created.id) === 1, 'owner remains after admin remove');
  db.addMember(created.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
  console.log('B OK remove member/admin/permissions/access');

  const leftMember = await leaveCommunity(MEMBER_ID, created.id, { db });
  assert(leftMember.left === true && leftMember.transferred === false, 'member leave');
  await expectAsyncAppError(leaveCommunity(MEMBER_ID, created.id, { db }), 404, NOT_FOUND);
  db.addMember(created.id, MEMBER_ID, 'member');
  const leftAdmin = await leaveCommunity(ADMIN_ID, created.id, { db });
  assert(leftAdmin.left === true, 'admin leave');
  await expectAsyncAppError(leaveCommunity(MEMBER_ID, other.id, { db }), 404, NOT_FOUND);
  db.addMember(created.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
  await expectAsyncAppError(getCommunityById(STRANGER_ID, created.id, { db }), 404, NOT_FOUND);
  console.log('C OK leave member/admin/double/wrong community');

  const solo = await createCommunity(OWNER_ID, { name: 'Cercle owner seul xx' }, { db });
  await expectAsyncAppError(leaveCommunity(OWNER_ID, solo.id, { db }), 400, OWNER_CANNOT_LEAVE);
  assert(ownerCount(db.state.members, solo.id) === 1, 'solo owner remains');
  db.addMember(solo.id, MEMBER_ID, 'member');
  await expectAsyncAppError(leaveCommunity(OWNER_ID, solo.id, { db }), 400, OWNER_CANNOT_LEAVE);

  const transferred = await leaveCommunity(OWNER_ID, created.id, { db });
  assert(transferred.transferred === true, 'owner leave transfers');
  assert(Number(transferred.successor.user_id) === ADMIN_ID, 'oldest admin successor');
  assert(transferred.successor.role === 'owner', 'successor is owner');
  assert(ownerCount(db.state.members, created.id) === 1, 'exactly one owner after transfer');
  const oldOwnerGone = db.state.members.find(
    (item) => Number(item.community_id) === Number(created.id) && Number(item.user_id) === OWNER_ID
  );
  assert(!oldOwnerGone, 'previous owner membership deleted');
  const createdBy = db.state.communities.find((item) => Number(item.id) === Number(created.id));
  assert(Number(createdBy.created_by) === OWNER_ID, 'created_by unchanged');
  console.log('D OK transfer to oldest admin; solo/no-admin refused; created_by kept');

  const chrono = await createCommunity(OWNER_ID, { name: 'Cercle chrono admins x' }, { db });
  db.addMember(chrono.id, SECOND_ADMIN_ID, 'admin', new Date('2026-03-01T00:00:00.000Z'));
  db.addMember(chrono.id, ADMIN_ID, 'admin', new Date('2026-01-15T00:00:00.000Z'));
  const chronoLeave = await leaveCommunity(OWNER_ID, chrono.id, { db });
  assert(Number(chronoLeave.successor.user_id) === ADMIN_ID, 'earlier assigned_at wins');
  console.log('E OK chronological successor');

  const rollback = await createCommunity(OWNER_ID, { name: 'Cercle rollback owner' }, { db });
  db.addMember(rollback.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
  db.addMember(rollback.id, MEMBER_ID, 'member');
  const before = cloneMembers(db.state.members, rollback.id);
  db.setFailOwnerPromote(true);
  try {
    await leaveCommunity(OWNER_ID, rollback.id, { db });
    throw new Error('expected successor promote failure');
  } catch (err) {
    assert(err instanceof AppError === false, 'forced failure is not a business AppError');
    assert(err.message === 'forced successor promote failure', err.message);
  }
  db.setFailOwnerPromote(false);
  const after = cloneMembers(db.state.members, rollback.id);
  assert(JSON.stringify(before) === JSON.stringify(after), 'rollback restored memberships');
  assert(ownerCount(db.state.members, rollback.id) === 1, 'rollback one owner');
  console.log('F OK transfer rollback');

  const race = await createCommunity(OWNER_ID, { name: 'Cercle concurrence own' }, { db });
  db.addMember(race.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
  db.addMember(race.id, SECOND_ADMIN_ID, 'admin', new Date('2026-02-01T00:00:00.000Z'));
  const pair = await Promise.allSettled([
    leaveCommunity(OWNER_ID, race.id, { db }),
    leaveCommunity(OWNER_ID, race.id, { db }),
  ]);
  const fulfilled = pair.filter((item) => item.status === 'fulfilled');
  const rejected = pair.filter((item) => item.status === 'rejected');
  assert(fulfilled.length === 1, 'one transfer wins');
  assert(rejected.length === 1, 'second transfer fails');
  assert(ownerCount(db.state.members, race.id) === 1, 'concurrent transfers keep one owner');
  console.log('G OK concurrent transfers');

  const mix = await createCommunity(OWNER_ID, { name: 'Cercle mixte locks xxx' }, { db });
  db.addMember(mix.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
  db.addMember(mix.id, MEMBER_ID, 'member');
  const mixed = await Promise.allSettled([
    leaveCommunity(OWNER_ID, mix.id, { db }),
    removeMember(OWNER_ID, mix.id, MEMBER_ID, { db }),
  ]);
  assert(mixed.filter((item) => item.status === 'fulfilled').length >= 1, 'mix has a winner');
  assert(ownerCount(db.state.members, mix.id) === 1, 'mix keeps one owner');

  const mix2 = await createCommunity(OWNER_ID, { name: 'Cercle role et leave x' }, { db });
  db.addMember(mix2.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
  db.addMember(mix2.id, MEMBER_ID, 'member');
  const mixedRole = await Promise.allSettled([
    leaveCommunity(OWNER_ID, mix2.id, { db }),
    updateMemberRole(OWNER_ID, mix2.id, MEMBER_ID, { role: 'admin' }, { db }),
  ]);
  assert(mixedRole.some((item) => item.status === 'fulfilled'), 'role/transfer one succeeds');
  assert(ownerCount(db.state.members, mix2.id) === 1, 'role/transfer one owner');
  console.log('H OK transfer+remove and transfer+role concurrency');

  const origQuery = pool.query;
  const origConnect = pool.connect;
  pool.query = (sql, params) => db.query(sql, params);
  pool.connect = () => db.connect();
  const app = express();
  app.use(express.json({ limit: '32kb' }));
  app.use('/communities', communityRoutes);
  app.use(errorHandler);
  const server = await new Promise((resolve) => {
    const httpServer = app.listen(HTTP_PORT, '127.0.0.1', () => resolve(httpServer));
  });

  try {
    const httpCommunity = await createCommunity(OWNER_ID, { name: 'Cercle http membres x' }, { db });
    db.addMember(httpCommunity.id, MEMBER_ID, 'member');
    db.addMember(httpCommunity.id, ADMIN_ID, 'admin', new Date('2026-01-01T00:00:00.000Z'));
    const ownerAuth = authFor(OWNER_ID, 'owner42');
    const adminAuth = authFor(ADMIN_ID, 'admin9');
    const memberAuth = authFor(MEMBER_ID, 'member7');

    const promoteHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'PATCH',
      urlPath: `/communities/${httpCommunity.id}/members/${MEMBER_ID}`,
      headers: ownerAuth,
      body: { role: 'admin' },
    });
    assert(promoteHttp.status === 200, `promote http ${promoteHttp.status} ${promoteHttp.raw}`);
    assert(promoteHttp.json.member.role === 'admin', 'http admin');

    const adminPromote = await httpRequest({
      port: HTTP_PORT,
      method: 'PATCH',
      urlPath: `/communities/${httpCommunity.id}/members/${ADMIN_ID}`,
      headers: adminAuth,
      body: { role: 'member' },
    });
    assert(adminPromote.status === 400, `admin patch ${adminPromote.status}`);

    const demoteHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'PATCH',
      urlPath: `/communities/${httpCommunity.id}/members/${MEMBER_ID}`,
      headers: ownerAuth,
      body: { role: 'member' },
    });
    assert(demoteHttp.status === 200 && demoteHttp.json.member.role === 'member', demoteHttp.raw);

    const adminRemove = await httpRequest({
      port: HTTP_PORT,
      method: 'DELETE',
      urlPath: `/communities/${httpCommunity.id}/members/${MEMBER_ID}`,
      headers: adminAuth,
    });
    assert(adminRemove.status === 400, `admin remove ${adminRemove.status}`);

    const ownerRemove = await httpRequest({
      port: HTTP_PORT,
      method: 'DELETE',
      urlPath: `/communities/${httpCommunity.id}/members/${MEMBER_ID}`,
      headers: ownerAuth,
    });
    assert(ownerRemove.status === 200 && ownerRemove.json.removed === true, ownerRemove.raw);

    db.addMember(httpCommunity.id, MEMBER_ID, 'member');
    const memberLeave = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/leave`,
      headers: memberAuth,
    });
    assert(memberLeave.status === 200 && memberLeave.json.left === true, memberLeave.raw);

    const ownerLeave = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/leave`,
      headers: ownerAuth,
    });
    assert(ownerLeave.status === 200 && ownerLeave.json.transferred === true, ownerLeave.raw);
    assert(Number(ownerLeave.json.successor.user_id) === ADMIN_ID, 'http successor');

    const membersAfter = await listCommunityMembers(ADMIN_ID, httpCommunity.id, { db });
    assert(!membersAfter.items.some((item) => Number(item.user_id) === OWNER_ID), 'old owner gone');
    assert(membersAfter.items.filter((item) => item.role === 'owner').length === 1, 'http one owner');
    console.log('I OK HTTP role/remove/leave/transfer');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    pool.query = origQuery;
    pool.connect = origConnect;
    process.env.JWT_SECRET = previous.JWT_SECRET;
    process.env.JWT_ISSUER = previous.JWT_ISSUER;
    process.env.JWT_AUDIENCE = previous.JWT_AUDIENCE;
    if (!previous.DATABASE_URL) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previous.DATABASE_URL;
    }
  }

  console.log('Community members check succeeded (mock DB, sans Neon ni R2).');
}

function cloneMembers(members, communityId) {
  return members
    .filter((item) => Number(item.community_id) === Number(communityId))
    .map((item) => ({ user_id: item.user_id, role: item.role }))
    .sort((a, b) => Number(a.user_id) - Number(b.user_id));
}

main().catch((err) => {
  console.error('Community members check failed:', err.message);
  process.exitCode = 1;
});
