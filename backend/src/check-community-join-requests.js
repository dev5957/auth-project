const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const express = require('express');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const {
  parseJoinRequestCreateBody,
  parseJoinRequestId,
  JOIN_REQUEST_STATUSES,
} = require('./validators/joinRequestFields');
const {
  createJoinRequest,
  listCommunityJoinRequests,
  listMyJoinRequests,
  acceptJoinRequest,
  declineJoinRequest,
  NOT_FOUND,
  JOIN_REQUEST_NOT_FOUND,
  ALREADY_MEMBER,
  ALREADY_PENDING,
  NOT_PENDING,
} = require('./services/joinRequestService');
const {
  createInvitation,
  acceptInvitation,
} = require('./services/invitationService');
const pool = require('./db');
const errorHandler = require('./middleware/errorHandler');
const communityRoutes = require('./routes/communities');
const invitationRoutes = require('./routes/invitations');
const joinRequestRoutes = require('./routes/joinRequests');

const TEST_SECRET = 'join-request-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30482;
const HTTP_PORT = 30483;

const OWNER_ID = 42;
const REQUESTER_ID = 7;
const ADMIN_ID = 9;
const STRANGER_ID = 11;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function expectAppError(fn, statusCode, message) {
  try {
    fn();
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    assert(err.message === message, `unexpected message: ${err.message}`);
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

function cloneState(state, nextIds) {
  return {
    communities: state.communities.map((row) => ({ ...row })),
    members: state.members.map((row) => ({ ...row })),
    invitations: state.invitations.map((row) => ({ ...row })),
    joinRequests: state.joinRequests.map((row) => ({ ...row })),
    declines: state.declines.map((row) => ({ ...row })),
    nextIds: { ...nextIds },
  };
}

function createJoinRequestMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner42' },
    { id: REQUESTER_ID, login: 'invitee7' },
    { id: ADMIN_ID, login: 'admin9' },
    { id: STRANGER_ID, login: 'stranger11' },
  ];
  const state = {
    communities: [],
    members: [],
    invitations: [],
    joinRequests: [],
    declines: [],
  };
  const nextIds = {
    community: 1,
    member: 1,
    invitation: 1,
    joinRequest: 1,
  };
  const locks = createLockTable();

  function pendingJoin(communityId, userId) {
    return state.joinRequests.find(
      (item) =>
        Number(item.community_id) === Number(communityId) &&
        Number(item.user_id) === Number(userId) &&
        item.status === 'pending'
    );
  }

  function uniqueJoinPending() {
    const err = new Error('duplicate pending join request');
    err.code = '23505';
    err.constraint = 'community_join_requests_one_pending_per_pair_key';
    return err;
  }

  function uniqueMember() {
    const err = new Error('duplicate membership');
    err.code = '23505';
    err.constraint = 'community_members_community_id_user_id_key';
    return err;
  }

  async function query(sql, params = [], session) {
    const key = sqlKey(sql);

    if (key === 'BEGIN') {
      if (session) {
        await session.acquire('txn:global');
        session.snapshot = cloneState(state, nextIds);
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
        state.invitations = session.snapshot.invitations;
        state.joinRequests = session.snapshot.joinRequests;
        state.declines = session.snapshot.declines;
        nextIds.community = session.snapshot.nextIds.community;
        nextIds.member = session.snapshot.nextIds.member;
        nextIds.invitation = session.snapshot.nextIds.invitation;
        nextIds.joinRequest = session.snapshot.nextIds.joinRequest;
        session.snapshot = null;
      }
      if (session) {
        session.releaseLocks();
      }
      return { rows: [], rowCount: 0 };
    }

    if (key.startsWith('SELECT ID FROM COMMUNITIES') && key.includes('FOR UPDATE')) {
      const communityId = Number(params[0]);
      if (session) {
        await session.acquire(`community:${communityId}`);
      }
      const row = state.communities.find((item) => Number(item.id) === communityId);
      return row ? { rows: [{ id: row.id }], rowCount: 1 } : { rows: [], rowCount: 0 };
    }

    if (
      key.startsWith('SELECT USER_ID, ROLE FROM COMMUNITY_MEMBERS') &&
      key.includes('FOR UPDATE')
    ) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      if (session) {
        await session.acquire(`member:${communityId}:${userId}`);
      }
      const row = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      return row
        ? { rows: [{ user_id: row.user_id, role: row.role }], rowCount: 1 }
        : { rows: [], rowCount: 0 };
    }

    if (
      key.includes('FROM COMMUNITIES C') &&
      key.includes('INNER JOIN COMMUNITY_MEMBERS M') &&
      key.includes('SELECT M.ROLE')
    ) {
      const actorUserId = Number(params[0]);
      const communityId = Number(params[1]);
      const community = state.communities.find((item) => Number(item.id) === communityId);
      if (!community) {
        return { rows: [], rowCount: 0 };
      }
      const member = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === actorUserId
      );
      return member
        ? { rows: [{ role: member.role }], rowCount: 1 }
        : { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_JOIN_REQUESTS')) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      if (pendingJoin(communityId, userId)) {
        throw uniqueJoinPending();
      }
      const now = new Date();
      const row = {
        id: nextIds.joinRequest,
        community_id: communityId,
        user_id: userId,
        status: 'pending',
        created_at: now,
        updated_at: now,
      };
      nextIds.joinRequest += 1;
      state.joinRequests.push(row);
      return {
        rows: [
          {
            id: row.id,
            community_id: row.community_id,
            status: row.status,
            created_at: row.created_at,
          },
        ],
        rowCount: 1,
      };
    }

    if (
      key.includes('FROM COMMUNITY_JOIN_REQUESTS R') &&
      key.includes('INNER JOIN USERS U') &&
      key.includes("STATUS IN ('PENDING', 'ACCEPTED', 'DECLINED')")
    ) {
      const communityId = Number(params[0]);
      const rows = state.joinRequests
        .filter(
          (item) =>
            Number(item.community_id) === communityId &&
            (item.status === 'pending' || item.status === 'accepted' || item.status === 'declined')
        )
        .sort((a, b) => b.created_at - a.created_at || Number(b.id) - Number(a.id))
        .map((item) => {
          const requester = users.find((entry) => Number(entry.id) === Number(item.user_id));
          return {
            id: item.id,
            requester_login: requester ? requester.login : null,
            status: item.status,
            created_at: item.created_at,
            updated_at: item.updated_at,
          };
        });
      return { rows, rowCount: rows.length };
    }

    if (
      key.includes('FROM COMMUNITY_JOIN_REQUESTS R') &&
      key.includes('INNER JOIN COMMUNITIES C') &&
      key.includes('WHERE R.USER_ID = $1')
    ) {
      const userId = Number(params[0]);
      const rows = state.joinRequests
        .filter((item) => Number(item.user_id) === userId)
        .sort((a, b) => b.created_at - a.created_at || Number(b.id) - Number(a.id))
        .map((item) => {
          const community = state.communities.find(
            (entry) => Number(entry.id) === Number(item.community_id)
          );
          return {
            id: item.id,
            community_id: item.community_id,
            community_name: community ? community.name : 'unknown',
            status: item.status,
            created_at: item.created_at,
            updated_at: item.updated_at,
          };
        });
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('SELECT ID, COMMUNITY_ID, USER_ID, STATUS FROM COMMUNITY_JOIN_REQUESTS')) {
      const requestId = Number(params[0]);
      const row = state.joinRequests.find((item) => Number(item.id) === requestId);
      if (key.includes('FOR UPDATE') && session) {
        await session.acquire(`joinRequest:${requestId}`);
      }
      return row
        ? {
            rows: [
              {
                id: row.id,
                community_id: row.community_id,
                user_id: row.user_id,
                status: row.status,
              },
            ],
            rowCount: 1,
          }
        : { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_MEMBERS')) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      const role = params[2] == null ? 'member' : params[2];
      const duplicate = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      if (duplicate) {
        throw uniqueMember();
      }
      const now = new Date();
      const row = {
        id: nextIds.member,
        community_id: communityId,
        user_id: userId,
        role,
        created_at: now,
        updated_at: now,
      };
      nextIds.member += 1;
      state.members.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith("UPDATE COMMUNITY_JOIN_REQUESTS") && key.includes("STATUS = 'ACCEPTED'")) {
      const requestId = Number(params[0]);
      const row = state.joinRequests.find((item) => Number(item.id) === requestId);
      if (!row || row.status !== 'pending') {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'accepted';
      row.updated_at = new Date();
      return { rows: [{ id: row.id }], rowCount: 1 };
    }

    if (key.startsWith("UPDATE COMMUNITY_JOIN_REQUESTS") && key.includes("STATUS = 'DECLINED'")) {
      const requestId = Number(params[0]);
      const row = state.joinRequests.find((item) => Number(item.id) === requestId);
      if (!row || row.status !== 'pending') {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'declined';
      row.updated_at = new Date();
      return { rows: [{ id: row.id }], rowCount: 1 };
    }

    if (key.startsWith("UPDATE COMMUNITY_JOIN_REQUESTS") && key.includes("STATUS = 'CANCELLED'")) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      const now = new Date();
      let count = 0;
      for (const row of state.joinRequests) {
        if (
          Number(row.community_id) === communityId &&
          Number(row.user_id) === userId &&
          row.status === 'pending'
        ) {
          row.status = 'cancelled';
          row.updated_at = now;
          count += 1;
        }
      }
      return { rows: [], rowCount: count };
    }

    if (
      key.startsWith("UPDATE COMMUNITY_INVITATIONS") &&
      key.includes("STATUS = 'CANCELLED'") &&
      key.includes('INVITEE_USER_ID')
    ) {
      const communityId = Number(params[0]);
      const inviteeUserId = Number(params[1]);
      const now = new Date();
      let count = 0;
      for (const row of state.invitations) {
        if (
          Number(row.community_id) === communityId &&
          Number(row.invitee_user_id) === inviteeUserId &&
          row.status === 'pending'
        ) {
          row.status = 'cancelled';
          row.updated_at = now;
          count += 1;
        }
      }
      return { rows: [], rowCount: count };
    }

    if (key.includes('FROM USERS') && key.includes('WHERE ID = $1')) {
      const userId = Number(params[0]);
      const row = users.find((item) => Number(item.id) === userId);
      return row ? { rows: [{ id: row.id }], rowCount: 1 } : { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_INVITATION_DECLINES')) {
      const communityId = Number(params[0]);
      const inviteeUserId = Number(params[1]);
      const existing = state.declines.find(
        (item) =>
          Number(item.community_id) === communityId && Number(item.invitee_user_id) === inviteeUserId
      );
      if (!existing) {
        const now = new Date();
        state.declines.push({
          community_id: communityId,
          invitee_user_id: inviteeUserId,
          decline_count: 0,
          created_at: now,
          updated_at: now,
        });
      }
      return { rows: [], rowCount: existing ? 0 : 1 };
    }

    if (
      key.startsWith('SELECT DECLINE_COUNT FROM COMMUNITY_INVITATION_DECLINES') &&
      key.includes('FOR UPDATE')
    ) {
      const communityId = Number(params[0]);
      const inviteeUserId = Number(params[1]);
      if (session) {
        await session.acquire(`decline:${communityId}:${inviteeUserId}`);
      }
      const row = state.declines.find(
        (item) =>
          Number(item.community_id) === communityId && Number(item.invitee_user_id) === inviteeUserId
      );
      return row
        ? { rows: [{ decline_count: row.decline_count }], rowCount: 1 }
        : { rows: [], rowCount: 0 };
    }

    if (key.startsWith("UPDATE COMMUNITY_INVITATIONS") && key.includes("STATUS = 'REPLACED'")) {
      return { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_INVITATIONS')) {
      const communityId = Number(params[0]);
      const inviteeUserId = Number(params[1]);
      const invitedBy = Number(params[2]);
      const now = new Date();
      const row = {
        id: nextIds.invitation,
        community_id: communityId,
        invitee_user_id: inviteeUserId,
        invited_by_user_id: invitedBy,
        status: 'pending',
        created_at: now,
        updated_at: now,
      };
      nextIds.invitation += 1;
      state.invitations.push(row);
      return {
        rows: [
          {
            id: row.id,
            community_id: row.community_id,
            invitee_user_id: row.invitee_user_id,
            status: row.status,
            created_at: row.created_at,
          },
        ],
        rowCount: 1,
      };
    }

    if (key.startsWith('SELECT ID, COMMUNITY_ID, INVITEE_USER_ID, INVITED_BY_USER_ID, STATUS')) {
      const invitationId = Number(params[0]);
      const row = state.invitations.find((item) => Number(item.id) === invitationId);
      if (key.includes('FOR UPDATE') && session) {
        await session.acquire(`invitation:${invitationId}`);
      }
      return row
        ? {
            rows: [
              {
                id: row.id,
                community_id: row.community_id,
                invitee_user_id: row.invitee_user_id,
                invited_by_user_id: row.invited_by_user_id,
                status: row.status,
              },
            ],
            rowCount: 1,
          }
        : { rows: [], rowCount: 0 };
    }

    if (key.startsWith("UPDATE COMMUNITY_INVITATIONS") && key.includes("STATUS = 'ACCEPTED'")) {
      const invitationId = Number(params[0]);
      const row = state.invitations.find((item) => Number(item.id) === invitationId);
      if (!row || row.status !== 'pending') {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'accepted';
      row.updated_at = new Date();
      return { rows: [{ id: row.id }], rowCount: 1 };
    }

    if (
      key.startsWith('UPDATE COMMUNITY_INVITATION_DECLINES') &&
      key.includes('DECLINE_COUNT = 0')
    ) {
      const communityId = Number(params[0]);
      const inviteeUserId = Number(params[1]);
      const row = state.declines.find(
        (item) =>
          Number(item.community_id) === communityId && Number(item.invitee_user_id) === inviteeUserId
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.decline_count = 0;
      row.updated_at = new Date();
      return { rows: [{ ...row }], rowCount: 1 };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  function createSession() {
    const held = [];
    const session = {
      snapshot: null,
      async acquire(lockKey) {
        const release = await locks.acquire(lockKey);
        held.push(release);
      },
      releaseLocks() {
        while (held.length) {
          const release = held.pop();
          release();
        }
      },
      async query(sql, params = []) {
        return query(sql, params, session);
      },
      release() {},
    };
    return session;
  }

  return {
    state,
    users,
    seedCommunity(name, ownerId) {
      const now = new Date();
      const community = {
        id: nextIds.community,
        name,
        description: null,
        visibility: 'private',
        created_by: ownerId,
        created_at: now,
        updated_at: now,
      };
      nextIds.community += 1;
      state.communities.push(community);
      state.members.push({
        id: nextIds.member,
        community_id: community.id,
        user_id: ownerId,
        role: 'owner',
        created_at: now,
        updated_at: now,
      });
      nextIds.member += 1;
      return community;
    },
    addMember(communityId, userId, role) {
      const now = new Date();
      state.members.push({
        id: nextIds.member,
        community_id: Number(communityId),
        user_id: Number(userId),
        role,
        created_at: now,
        updated_at: now,
      });
      nextIds.member += 1;
    },
    declineCount(communityId, userId) {
      const row = state.declines.find(
        (item) =>
          Number(item.community_id) === Number(communityId) &&
          Number(item.invitee_user_id) === Number(userId)
      );
      return row ? Number(row.decline_count) : 0;
    },
    query(sql, params) {
      return query(sql, params, null);
    },
    connect() {
      return Promise.resolve(createSession());
    },
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

function startIndexServer(port) {
  const logs = [];
  const env = {
    ...process.env,
    PORT: String(port),
    JWT_SECRET: TEST_SECRET,
    JWT_ISSUER: TEST_ISSUER,
    JWT_AUDIENCE: TEST_AUDIENCE,
    JWT_EXPIRES_IN: '15m',
    REFRESH_TOKEN_EXPIRES_DAYS: '90',
    DEV_LOG_SMS_CODE: 'false',
    DATABASE_URL: '',
  };
  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: path.join(__dirname, '..'),
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const onData = (chunk) => logs.push(chunk.toString('utf8'));
  child.stdout.on('data', onData);
  child.stderr.on('data', onData);
  return { child, logs };
}

function waitForLog(logs, pattern, timeoutMs) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      if (logs.join('').includes(pattern)) {
        clearInterval(timer);
        resolve();
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(timer);
        reject(new Error(`server did not start: ${logs.join('')}`));
      }
    }, 50);
  });
}

function stopServer(child) {
  return new Promise((resolve) => {
    const t = setTimeout(() => {
      child.kill('SIGKILL');
      resolve();
    }, 2000);
    child.on('exit', () => {
      clearTimeout(t);
      resolve();
    });
    child.kill('SIGTERM');
  });
}

function tokenFor(userId, login) {
  return generateAccessToken({
    id: userId,
    login,
    auth_provider: 'local',
  });
}

function authFor(userId, login) {
  return { Authorization: `Bearer ${tokenFor(userId, login)}` };
}

function keysOf(item) {
  return Object.keys(item).sort().join(',');
}

function ownerListSafe(item) {
  return keysOf(item) === 'created_at,id,requester_login,status,updated_at';
}

function mineListSafe(item) {
  return keysOf(item) === 'community_id,community_name,created_at,id,status,updated_at';
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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://join-request-test/local';

  assert(JOIN_REQUEST_STATUSES.includes('cancelled'), 'cancelled status');
  parseJoinRequestCreateBody(undefined);
  parseJoinRequestCreateBody({});
  expectAppError(() => parseJoinRequestCreateBody({ user_id: 7 }), 400, 'user_id cannot be set');
  expectAppError(() => parseJoinRequestCreateBody({ phone: '+1' }), 400, 'phone cannot be set');
  expectAppError(() => parseJoinRequestId('abc'), 400, 'id is invalid');
  console.log('A OK validators join request body / id');

  const db = createJoinRequestMemory();
  const community = db.seedCommunity('Cercle demandes adhésion', OWNER_ID);
  db.addMember(community.id, ADMIN_ID, 'admin');

  const created = await createJoinRequest(REQUESTER_ID, community.id, {}, { db });
  assert(created.status === 'pending', 'created pending');
  assert(Number(created.community_id) === Number(community.id), 'community stored');
  assert(!Object.prototype.hasOwnProperty.call(created, 'phone'), 'create payload has no phone');
  console.log('B OK non-member creates pending join request');

  await expectAsyncAppError(
    createJoinRequest(REQUESTER_ID, community.id, {}, { db }),
    400,
    ALREADY_PENDING
  );
  await expectAsyncAppError(
    createJoinRequest(OWNER_ID, community.id, {}, { db }),
    400,
    ALREADY_MEMBER
  );
  await expectAsyncAppError(
    createJoinRequest(ADMIN_ID, community.id, {}, { db }),
    400,
    ALREADY_MEMBER
  );
  await expectAsyncAppError(createJoinRequest(REQUESTER_ID, 9999, {}, { db }), 404, NOT_FOUND);
  console.log('C OK duplicate pending / member / missing community refused');

  const ownerList = await listCommunityJoinRequests(OWNER_ID, community.id, { db });
  assert(ownerList.items.length === 1, 'owner sees pending');
  assert(ownerList.items[0].requester_login === 'invitee7', 'owner sees login');
  assert(ownerListSafe(ownerList.items[0]), `owner keys ${keysOf(ownerList.items[0])}`);
  await expectAsyncAppError(
    listCommunityJoinRequests(ADMIN_ID, community.id, { db }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(
    listCommunityJoinRequests(REQUESTER_ID, community.id, { db }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(
    listCommunityJoinRequests(STRANGER_ID, community.id, { db }),
    404,
    NOT_FOUND
  );
  console.log('D OK owner list; non-owners 404');

  const mine = await listMyJoinRequests(REQUESTER_ID, { db });
  assert(mine.items.length === 1, 'mine one item');
  assert(mineListSafe(mine.items[0]), `mine keys ${keysOf(mine.items[0])}`);
  assert(mine.items[0].community_name === 'Cercle demandes adhésion', 'mine community name');
  const ownerMine = await listMyJoinRequests(OWNER_ID, { db });
  assert(ownerMine.items.length === 0, 'owner has no own join requests');
  console.log('E OK GET mine scoped to requester');

  const declined = await declineJoinRequest(OWNER_ID, community.id, created.id, { db });
  assert(declined.status === 'declined', 'declined');
  assert(
    !db.state.members.some(
      (item) =>
        Number(item.community_id) === Number(community.id) && Number(item.user_id) === REQUESTER_ID
    ),
    'decline does not add membership'
  );
  assert(db.declineCount(community.id, REQUESTER_ID) === 0, 'join decline does not touch invitation counter');
  await expectAsyncAppError(
    declineJoinRequest(OWNER_ID, community.id, created.id, { db }),
    400,
    NOT_PENDING
  );
  const afterDecline = await createJoinRequest(REQUESTER_ID, community.id, {}, { db });
  assert(afterDecline.status === 'pending', 'new request after decline');
  assert(Number(afterDecline.id) !== Number(created.id), 'new id after decline');
  console.log('F OK decline without membership; renew after decline');

  db.state.declines.push({
    community_id: community.id,
    invitee_user_id: REQUESTER_ID,
    decline_count: 2,
    created_at: new Date(),
    updated_at: new Date(),
  });
  const pendingInvite = await createInvitation(
    OWNER_ID,
    community.id,
    { user_id: REQUESTER_ID },
    { db }
  );
  assert(pendingInvite.status === 'pending', 'invitation pending alongside join request');
  const accepted = await acceptJoinRequest(OWNER_ID, community.id, afterDecline.id, { db });
  assert(accepted.join_request.status === 'accepted', 'accepted');
  assert(accepted.membership.role === 'member', 'joined as member');
  const memberRow = db.state.members.find(
    (item) =>
      Number(item.community_id) === Number(community.id) && Number(item.user_id) === REQUESTER_ID
  );
  assert(memberRow && memberRow.role === 'member', 'member persisted');
  const closedInvite = db.state.invitations.find(
    (item) => Number(item.id) === Number(pendingInvite.id)
  );
  assert(closedInvite.status === 'cancelled', 'pending invitation cancelled not declined');
  assert(db.declineCount(community.id, REQUESTER_ID) === 2, 'accept join does not change invitation counter');
  await expectAsyncAppError(
    acceptJoinRequest(OWNER_ID, community.id, afterDecline.id, { db }),
    400,
    NOT_PENDING
  );
  await expectAsyncAppError(
    createJoinRequest(REQUESTER_ID, community.id, {}, { db }),
    400,
    ALREADY_MEMBER
  );
  console.log('G OK accept adds member, cancels pending invitation, counter unchanged');

  const otherCommunity = db.seedCommunity('Autre cercle demandes', OWNER_ID);
  const otherRequest = await createJoinRequest(STRANGER_ID, otherCommunity.id, {}, { db });
  await expectAsyncAppError(
    acceptJoinRequest(OWNER_ID, community.id, otherRequest.id, { db }),
    404,
    JOIN_REQUEST_NOT_FOUND
  );
  await expectAsyncAppError(
    declineJoinRequest(ADMIN_ID, otherCommunity.id, otherRequest.id, { db }),
    404,
    NOT_FOUND
  );
  console.log('H OK mismatched community / non-owner treat 404');

  const hookDb = createJoinRequestMemory();
  const hookCommunity = hookDb.seedCommunity('Cercle hook invitation', OWNER_ID);
  const hookJoin = await createJoinRequest(REQUESTER_ID, hookCommunity.id, {}, { db: hookDb });
  const hookInvite = await createInvitation(
    OWNER_ID,
    hookCommunity.id,
    { user_id: REQUESTER_ID },
    { db: hookDb }
  );
  hookDb.state.declines.push({
    community_id: hookCommunity.id,
    invitee_user_id: REQUESTER_ID,
    decline_count: 3,
    created_at: new Date(),
    updated_at: new Date(),
  });
  const acceptedInvite = await acceptInvitation(REQUESTER_ID, hookInvite.id, { db: hookDb });
  assert(acceptedInvite.invitation.status === 'accepted', 'invitation accepted');
  const cancelledJoin = hookDb.state.joinRequests.find(
    (item) => Number(item.id) === Number(hookJoin.id)
  );
  assert(cancelledJoin.status === 'cancelled', 'join request cancelled by invitation accept');
  assert(hookDb.declineCount(hookCommunity.id, REQUESTER_ID) === 0, 'invitation accept still resets its own counter');
  const ownerAfterHook = await listCommunityJoinRequests(OWNER_ID, hookCommunity.id, { db: hookDb });
  assert(
    !ownerAfterHook.items.some((item) => Number(item.id) === Number(hookJoin.id)),
    'cancelled join excluded from owner active/history list'
  );
  const mineAfterHook = await listMyJoinRequests(REQUESTER_ID, { db: hookDb });
  assert(
    mineAfterHook.items.some(
      (item) => Number(item.id) === Number(hookJoin.id) && item.status === 'cancelled'
    ),
    'mine still shows cancelled'
  );
  console.log('I OK invitation accept cancels pending join request');

  const concDb = createJoinRequestMemory();
  const concCommunity = concDb.seedCommunity('Cercle concurrence demandes', OWNER_ID);
  const concCreates = await Promise.allSettled([
    createJoinRequest(REQUESTER_ID, concCommunity.id, {}, { db: concDb }),
    createJoinRequest(REQUESTER_ID, concCommunity.id, {}, { db: concDb }),
  ]);
  assert(concCreates.filter((item) => item.status === 'fulfilled').length === 1, 'one pending join');
  assert(
    concDb.state.joinRequests.filter(
      (item) =>
        Number(item.community_id) === Number(concCommunity.id) &&
        Number(item.user_id) === REQUESTER_ID &&
        item.status === 'pending'
    ).length === 1,
    'single pending row'
  );
  const pendingId = concDb.state.joinRequests.find(
    (item) => item.status === 'pending' && Number(item.user_id) === REQUESTER_ID
  ).id;
  const concAccepts = await Promise.allSettled([
    acceptJoinRequest(OWNER_ID, concCommunity.id, pendingId, { db: concDb }),
    acceptJoinRequest(OWNER_ID, concCommunity.id, pendingId, { db: concDb }),
  ]);
  assert(concAccepts.filter((item) => item.status === 'fulfilled').length === 1, 'one accept wins');
  assert(
    concDb.state.members.filter(
      (item) =>
        Number(item.community_id) === Number(concCommunity.id) && Number(item.user_id) === REQUESTER_ID
    ).length === 1,
    'single membership'
  );
  console.log('J OK concurrent create/accept');

  const origQuery = pool.query;
  const origConnect = pool.connect;
  pool.query = (sql, params) => db.query(sql, params);
  pool.connect = () => db.connect();

  const app = express();
  app.use(express.json({ limit: '32kb' }));
  app.use('/communities', communityRoutes);
  app.use('/invitations', invitationRoutes);
  app.use('/join-requests', joinRequestRoutes);
  app.use(errorHandler);
  const server = await new Promise((resolve) => {
    const httpServer = app.listen(HTTP_PORT, '127.0.0.1', () => resolve(httpServer));
  });

  try {
    const ownerAuth = authFor(OWNER_ID, 'owner42');
    const requesterAuth = authFor(REQUESTER_ID, 'invitee7');
    const adminAuth = authFor(ADMIN_ID, 'admin9');
    const strangerAuth = authFor(STRANGER_ID, 'stranger11');

    const httpCommunity = db.seedCommunity('HTTP demandes', OWNER_ID);
    db.addMember(httpCommunity.id, ADMIN_ID, 'admin');

    const createdHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/join-requests`,
      headers: requesterAuth,
      body: {},
    });
    assert(createdHttp.status === 201, `http create ${createdHttp.status} ${createdHttp.raw}`);
    assert(createdHttp.json.join_request.status === 'pending', 'http pending');
    assert(!JSON.stringify(createdHttp.json).includes('phone'), 'http leaked phone');
    const requestId = createdHttp.json.join_request.id;

    const listed = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${httpCommunity.id}/join-requests`,
      headers: ownerAuth,
    });
    assert(listed.status === 200, `owner list ${listed.status}`);
    assert(listed.json.items.some((item) => Number(item.id) === Number(requestId)), 'owner list contains');
    for (const item of listed.json.items) {
      assert(ownerListSafe(item), `http owner keys ${keysOf(item)}`);
    }

    const adminList = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${httpCommunity.id}/join-requests`,
      headers: adminAuth,
    });
    assert(adminList.status === 404, `admin list ${adminList.status}`);

    const mineHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/join-requests/mine',
      headers: requesterAuth,
    });
    assert(mineHttp.status === 200, `mine ${mineHttp.status}`);
    assert(
      mineHttp.json.items.some(
        (item) => Number(item.id) === Number(requestId) && Number(item.community_id) === Number(httpCommunity.id)
      ),
      'mine contains own request'
    );
    const ownerMineHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/join-requests/mine',
      headers: ownerAuth,
    });
    assert(
      !ownerMineHttp.json.items.some((item) => Number(item.id) === Number(requestId)),
      'owner mine does not include requester item'
    );

    const declinedHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/join-requests/${requestId}/decline`,
      headers: ownerAuth,
    });
    assert(declinedHttp.status === 200, `decline http ${declinedHttp.status}`);
    assert(declinedHttp.json.join_request.status === 'declined', 'http declined');

    const renewedHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/join-requests`,
      headers: requesterAuth,
      body: {},
    });
    assert(renewedHttp.status === 201, `renew ${renewedHttp.status}`);
    const acceptHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/join-requests/${renewedHttp.json.join_request.id}/accept`,
      headers: ownerAuth,
    });
    assert(acceptHttp.status === 200, `accept http ${acceptHttp.status} ${acceptHttp.raw}`);
    assert(acceptHttp.json.join_request.status === 'accepted', 'http accepted');
    assert(acceptHttp.json.membership.role === 'member', 'http member');

    const strangerCreate = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/join-requests`,
      headers: strangerAuth,
      body: {},
    });
    assert(strangerCreate.status === 201, `stranger create ${strangerCreate.status}`);
    const adminAccept = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpCommunity.id}/join-requests/${strangerCreate.json.join_request.id}/accept`,
      headers: adminAuth,
    });
    assert(adminAccept.status === 404, `admin accept ${adminAccept.status}`);
    console.log('K OK HTTP create/list/mine/decline/accept and authz');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    pool.query = origQuery;
    pool.connect = origConnect;
  }

  const { child, logs } = startIndexServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);
    const unauthCreate = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/communities/1/join-requests',
      body: {},
    });
    assert(unauthCreate.status === 401, `unauth create ${unauthCreate.status}`);
    const unauthList = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/communities/1/join-requests',
    });
    assert(unauthList.status === 401, `unauth list ${unauthList.status}`);
    const unauthMine = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/join-requests/mine',
    });
    assert(unauthMine.status === 401, `unauth mine ${unauthMine.status}`);
    console.log('L OK unauthenticated join-request routes -> 401');
  } finally {
    await stopServer(child);
    process.env.JWT_SECRET = previous.JWT_SECRET;
    process.env.JWT_ISSUER = previous.JWT_ISSUER;
    process.env.JWT_AUDIENCE = previous.JWT_AUDIENCE;
    if (!previous.DATABASE_URL) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = previous.DATABASE_URL;
    }
  }

  console.log('Community join-request check succeeded (mock DB, sans Neon ni R2).');
}

main().catch((err) => {
  console.error('Community join-request check failed:', err.message);
  process.exitCode = 1;
});
