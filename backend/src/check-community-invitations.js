const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const express = require('express');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const {
  parseInviteBody,
  parseInvitationId,
  DECLINE_LIMIT,
  INVITATION_STATUSES,
} = require('./validators/invitationFields');
const {
  createInvitation,
  listReceivedInvitations,
  listSentInvitations,
  acceptInvitation,
  declineInvitation,
  cancelInvitation,
  closePendingJoinRequestsIfPresent,
  NOT_FOUND,
  USER_NOT_FOUND,
  INVITATION_NOT_FOUND,
  ALREADY_MEMBER,
  CANNOT_INVITE_SELF,
  CANNOT_SEND,
  LIMIT_REACHED,
  NOT_PENDING,
} = require('./services/invitationService');
const pool = require('./db');
const errorHandler = require('./middleware/errorHandler');
const communityRoutes = require('./routes/communities');
const invitationRoutes = require('./routes/invitations');

const TEST_SECRET = 'invitation-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30480;
const HTTP_PORT = 30481;

const OWNER_ID = 42;
const INVITEE_ID = 7;
const ADMIN_ID = 9;
const STRANGER_ID = 11;
const MISSING_USER_ID = 999;

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

function createInvitationMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner42' },
    { id: INVITEE_ID, login: 'invitee7' },
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
  };
  const locks = createLockTable();

  function pendingForPair(communityId, inviteeUserId) {
    return state.invitations.find(
      (item) =>
        Number(item.community_id) === Number(communityId) &&
        Number(item.invitee_user_id) === Number(inviteeUserId) &&
        item.status === 'pending'
    );
  }

  function uniqueViolation() {
    const err = new Error('duplicate pending invitation');
    err.code = '23505';
    err.constraint = 'community_invitations_one_pending_per_pair_key';
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
          row.status = 'replaced';
          row.updated_at = now;
          count += 1;
        }
      }
      return { rows: [], rowCount: count };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_INVITATIONS')) {
      const communityId = Number(params[0]);
      const inviteeUserId = Number(params[1]);
      const invitedBy = Number(params[2]);
      if (inviteeUserId === invitedBy) {
        const err = new Error('self invite check');
        err.code = '23514';
        throw err;
      }
      if (pendingForPair(communityId, inviteeUserId)) {
        throw uniqueViolation();
      }
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

    if (
      key.includes('FROM COMMUNITY_INVITATIONS I') &&
      key.includes('INNER JOIN USERS U') &&
      !key.includes('INNER JOIN COMMUNITIES') &&
      key.includes("STATUS IN ('PENDING', 'ACCEPTED', 'DECLINED')")
    ) {
      const communityId = Number(params[0]);
      const rows = state.invitations
        .filter(
          (item) =>
            Number(item.community_id) === communityId &&
            (item.status === 'pending' || item.status === 'accepted' || item.status === 'declined')
        )
        .sort((a, b) => b.created_at - a.created_at || Number(b.id) - Number(a.id))
        .map((item) => {
          const invitee = users.find((entry) => Number(entry.id) === Number(item.invitee_user_id));
          return {
            id: item.id,
            invitee_login: invitee ? invitee.login : null,
            status: item.status,
            created_at: item.created_at,
            declined_at: item.status === 'declined' ? item.updated_at : null,
          };
        });
      return { rows, rowCount: rows.length };
    }

    if (
      key.includes('FROM COMMUNITY_INVITATIONS I') &&
      key.includes('INNER JOIN COMMUNITIES C') &&
      key.includes('INNER JOIN USERS U')
    ) {
      const inviteeUserId = Number(params[0]);
      const rows = state.invitations
        .filter((item) => Number(item.invitee_user_id) === inviteeUserId && item.status === 'pending')
        .sort((a, b) => b.created_at - a.created_at || Number(b.id) - Number(a.id))
        .map((item) => {
          const community = state.communities.find(
            (entry) => Number(entry.id) === Number(item.community_id)
          );
          const inviter = users.find((entry) => Number(entry.id) === Number(item.invited_by_user_id));
          return {
            id: item.id,
            community_id: item.community_id,
            community_name: community ? community.name : 'unknown',
            invited_by_login: inviter ? inviter.login : 'unknown',
            status: item.status,
            created_at: item.created_at,
          };
        });
      return { rows, rowCount: rows.length };
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

    if (key.startsWith('INSERT INTO COMMUNITY_MEMBERS')) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      const role = params[2] == null ? 'member' : params[2];
      const duplicate = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      if (duplicate) {
        const err = new Error('duplicate membership');
        err.code = '23505';
        throw err;
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

    if (key.startsWith("UPDATE COMMUNITY_INVITATIONS") && key.includes("STATUS = 'DECLINED'")) {
      const invitationId = Number(params[0]);
      const row = state.invitations.find((item) => Number(item.id) === invitationId);
      if (!row || row.status !== 'pending') {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'declined';
      row.updated_at = new Date();
      return { rows: [{ id: row.id }], rowCount: 1 };
    }

    if (key.startsWith("UPDATE COMMUNITY_INVITATIONS") && key.includes("STATUS = 'CANCELLED'")) {
      const invitationId = Number(params[0]);
      const row = state.invitations.find((item) => Number(item.id) === invitationId);
      if (!row || row.status !== 'pending') {
        return { rows: [], rowCount: 0 };
      }
      row.status = 'cancelled';
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

    if (
      key.startsWith('UPDATE COMMUNITY_INVITATION_DECLINES') &&
      key.includes('DECLINE_COUNT = DECLINE_COUNT + 1')
    ) {
      const communityId = Number(params[0]);
      const inviteeUserId = Number(params[1]);
      const limit = Number(params[2]);
      const row = state.declines.find(
        (item) =>
          Number(item.community_id) === communityId && Number(item.invitee_user_id) === inviteeUserId
      );
      if (!row || Number(row.decline_count) >= limit) {
        return { rows: [], rowCount: 0 };
      }
      row.decline_count += 1;
      row.updated_at = new Date();
      if (row.decline_count > 5) {
        const err = new Error('decline_count check');
        err.code = '23514';
        throw err;
      }
      return { rows: [{ ...row }], rowCount: 1 };
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
    removeMember(communityId, userId) {
      state.members = state.members.filter(
        (item) =>
          !(Number(item.community_id) === Number(communityId) && Number(item.user_id) === Number(userId))
      );
    },
    declineCount(communityId, inviteeUserId) {
      const row = state.declines.find(
        (item) =>
          Number(item.community_id) === Number(communityId) &&
          Number(item.invitee_user_id) === Number(inviteeUserId)
      );
      return row ? Number(row.decline_count) : 0;
    },
    query: (sql, params) => query(sql, params, null),
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

function inboxKeys(item) {
  return Object.keys(item).sort().join(',');
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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://invitation-test/local';

  assert(DECLINE_LIMIT === 5, 'decline limit 5');
  assert(INVITATION_STATUSES.includes('cancelled'), 'cancelled status');
  assert(INVITATION_STATUSES.includes('replaced'), 'replaced status');
  expectAppError(() => parseInviteBody({}), 400, 'user_id is required');
  expectAppError(() => parseInviteBody({ user_id: 'abc' }), 400, 'user_id is invalid');
  expectAppError(() => parseInviteBody({ user_id: 7, login: 'x' }), 400, 'login cannot be set');
  expectAppError(() => parseInviteBody({ user_id: 7, phone: '+1' }), 400, 'phone cannot be set');
  expectAppError(() => parseInvitationId('abc'), 400, 'id is invalid');
  parseInviteBody({ user_id: 7 });
  console.log('A OK validators invite body / invitation id');

  const db = createInvitationMemory();
  const community = db.seedCommunity('Cercle prive invitation', OWNER_ID);
  db.addMember(community.id, ADMIN_ID, 'admin');

  const created = await createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db });
  assert(created.status === 'pending', 'created pending');
  assert(Number(created.invitee_user_id) === INVITEE_ID, 'invitee stored as user_id');
  assert(!Object.prototype.hasOwnProperty.call(created, 'login'), 'create payload has no login');
  console.log('B OK owner invite creates pending');

  const inbox = await listReceivedInvitations(INVITEE_ID, { db });
  assert(inbox.items.length === 1, 'inbox one pending');
  assert(inboxItemsSafe(inbox.items[0]), 'inbox minimal');
  assert(inbox.items[0].community_name === 'Cercle prive invitation', 'inbox community name');
  assert(inbox.items[0].invited_by_login === 'owner42', 'inbox inviter login');
  const ownerInbox = await listReceivedInvitations(OWNER_ID, { db });
  assert(ownerInbox.items.length === 0, 'owner has no received pending');
  console.log('C OK invitee inbox pending only');

  const resent = await createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db });
  assert(resent.status === 'pending', 'resend pending');
  assert(Number(resent.id) !== Number(created.id), 'resend new id');
  const replaced = db.state.invitations.find((item) => Number(item.id) === Number(created.id));
  assert(replaced.status === 'replaced', 'previous replaced');
  assert(db.declineCount(community.id, INVITEE_ID) === 0, 'resend does not increment declines');
  const inboxAfterResend = await listReceivedInvitations(INVITEE_ID, { db });
  assert(inboxAfterResend.items.length === 1, 'inbox still one pending');
  assert(Number(inboxAfterResend.items[0].id) === Number(resent.id), 'inbox shows latest');
  console.log('D OK resend replaces pending without counting decline');

  await expectAsyncAppError(
    createInvitation(OWNER_ID, community.id, { user_id: OWNER_ID }, { db }),
    400,
    CANNOT_INVITE_SELF
  );
  await expectAsyncAppError(
    createInvitation(ADMIN_ID, community.id, { user_id: INVITEE_ID }, { db }),
    400,
    CANNOT_SEND
  );
  await expectAsyncAppError(
    createInvitation(INVITEE_ID, community.id, { user_id: ADMIN_ID }, { db }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(
    createInvitation(STRANGER_ID, community.id, { user_id: INVITEE_ID }, { db }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(
    createInvitation(OWNER_ID, 9999, { user_id: INVITEE_ID }, { db }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(
    createInvitation(OWNER_ID, community.id, { user_id: MISSING_USER_ID }, { db }),
    404,
    USER_NOT_FOUND
  );
  await expectAsyncAppError(
    createInvitation(OWNER_ID, community.id, { user_id: ADMIN_ID }, { db }),
    400,
    ALREADY_MEMBER
  );
  console.log('E OK negative create: self/admin/non-member/missing/already member');

  const accepted = await acceptInvitation(INVITEE_ID, resent.id, { db });
  assert(accepted.invitation.status === 'accepted', 'accepted status');
  assert(accepted.membership.role === 'member', 'joined as member');
  const memberRow = db.state.members.find(
    (item) => Number(item.community_id) === Number(community.id) && Number(item.user_id) === INVITEE_ID
  );
  assert(memberRow && memberRow.role === 'member', 'member persisted');
  const ownerStill = db.state.members.find(
    (item) => Number(item.community_id) === Number(community.id) && Number(item.user_id) === OWNER_ID
  );
  assert(ownerStill.role === 'owner', 'owner role unchanged');
  const emptyInbox = await listReceivedInvitations(INVITEE_ID, { db });
  assert(emptyInbox.items.length === 0, 'accepted leaves inbox');
  console.log('F OK accept adds member atomically');

  await expectAsyncAppError(
    createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db }),
    400,
    ALREADY_MEMBER
  );

  db.removeMember(community.id, INVITEE_ID);
  const afterLeave = await createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db });
  assert(afterLeave.status === 'pending', 'invite after leave');
  assert(db.declineCount(community.id, INVITEE_ID) === 0, 'counter still reset after leave');
  console.log('G OK invite again after leave with reset counter');

  const declined = await declineInvitation(INVITEE_ID, afterLeave.id, { db });
  assert(declined.status === 'declined', 'declined');
  assert(db.declineCount(community.id, INVITEE_ID) === 1, 'explicit decline increments');
  const declinedInbox = await listReceivedInvitations(INVITEE_ID, { db });
  assert(declinedInbox.items.length === 0, 'declined not in inbox');
  console.log('H OK explicit decline increments counter');

  await expectAsyncAppError(declineInvitation(INVITEE_ID, afterLeave.id, { db }), 400, NOT_PENDING);
  await expectAsyncAppError(acceptInvitation(INVITEE_ID, afterLeave.id, { db }), 400, NOT_PENDING);

  const toCancel = await createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db });
  assert(db.declineCount(community.id, INVITEE_ID) === 1, 'resend after decline keeps count');
  const cancelled = await cancelInvitation(OWNER_ID, toCancel.id, { db });
  assert(cancelled.status === 'cancelled', 'cancelled status');
  assert(db.declineCount(community.id, INVITEE_ID) === 1, 'cancel does not increment');
  const cancelInbox = await listReceivedInvitations(INVITEE_ID, { db });
  assert(cancelInbox.items.length === 0, 'cancelled not in inbox');
  await expectAsyncAppError(cancelInvitation(OWNER_ID, toCancel.id, { db }), 400, NOT_PENDING);
  await expectAsyncAppError(cancelInvitation(ADMIN_ID, toCancel.id, { db }), 400, CANNOT_SEND);
  await expectAsyncAppError(cancelInvitation(STRANGER_ID, toCancel.id, { db }), 404, NOT_FOUND);
  console.log('I OK cancel by owner, not a decline, hidden from inbox');

  for (let i = 0; i < 4; i += 1) {
    const nextInvite = await createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db });
    await declineInvitation(INVITEE_ID, nextInvite.id, { db });
  }
  assert(db.declineCount(community.id, INVITEE_ID) === 5, 'five explicit declines');
  await expectAsyncAppError(
    createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db }),
    400,
    LIMIT_REACHED
  );
  console.log('J OK fifth explicit decline blocks further invites');

  db.state.declines.find(
    (item) => Number(item.community_id) === Number(community.id) && Number(item.invitee_user_id) === INVITEE_ID
  ).decline_count = 2;
  const resetInvite = await createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db });
  await acceptInvitation(INVITEE_ID, resetInvite.id, { db });
  assert(db.declineCount(community.id, INVITEE_ID) === 0, 'accept resets counter');
  db.removeMember(community.id, INVITEE_ID);
  const afterReset = await createInvitation(OWNER_ID, community.id, { user_id: INVITEE_ID }, { db });
  assert(afterReset.status === 'pending', 'invite after accept reset');
  console.log('K OK accept resets counter; join-request declines are not this table');

  const alreadyMemberInvite = afterReset;
  db.addMember(community.id, INVITEE_ID, 'member');
  await expectAsyncAppError(
    acceptInvitation(INVITEE_ID, alreadyMemberInvite.id, { db }),
    400,
    ALREADY_MEMBER
  );
  const stillPending = db.state.invitations.find(
    (item) => Number(item.id) === Number(alreadyMemberInvite.id)
  );
  assert(stillPending.status === 'pending', 'already member leaves invitation pending');
  db.removeMember(community.id, INVITEE_ID);
  console.log('L OK accept while already member keeps pending');

  await expectAsyncAppError(
    acceptInvitation(STRANGER_ID, alreadyMemberInvite.id, { db }),
    404,
    INVITATION_NOT_FOUND
  );
  await expectAsyncAppError(
    declineInvitation(STRANGER_ID, alreadyMemberInvite.id, { db }),
    404,
    INVITATION_NOT_FOUND
  );
  await expectAsyncAppError(
    acceptInvitation(ADMIN_ID, alreadyMemberInvite.id, { db }),
    404,
    INVITATION_NOT_FOUND
  );
  assert(typeof closePendingJoinRequestsIfPresent === 'function', '2.4 hook exported');
  await closePendingJoinRequestsIfPresent(
    { query: async () => ({ rows: [], rowCount: 0 }) },
    community.id,
    INVITEE_ID
  );
  console.log('M OK third-party accept/decline 404; 2.4 hook closes pending join requests');

  const concDb = createInvitationMemory();
  const concCommunity = concDb.seedCommunity('Cercle concurrence invits', OWNER_ID);
  const firstPair = await Promise.allSettled([
    createInvitation(OWNER_ID, concCommunity.id, { user_id: INVITEE_ID }, { db: concDb }),
    createInvitation(OWNER_ID, concCommunity.id, { user_id: INVITEE_ID }, { db: concDb }),
  ]);
  const createdOk = firstPair.filter((item) => item.status === 'fulfilled');
  assert(createdOk.length >= 1, 'at least one concurrent create succeeds');
  const pendingRows = concDb.state.invitations.filter(
    (item) =>
      Number(item.community_id) === Number(concCommunity.id) &&
      Number(item.invitee_user_id) === INVITEE_ID &&
      item.status === 'pending'
  );
  assert(pendingRows.length === 1, 'exactly one pending after concurrent creates');
  console.log('N OK concurrent creates leave one pending');

  const pendingId = pendingRows[0].id;
  const acceptDecline = await Promise.allSettled([
    acceptInvitation(INVITEE_ID, pendingId, { db: concDb }),
    declineInvitation(INVITEE_ID, pendingId, { db: concDb }),
  ]);
  const adWins = acceptDecline.filter((item) => item.status === 'fulfilled');
  const adFails = acceptDecline.filter((item) => item.status === 'rejected');
  assert(adWins.length === 1 && adFails.length === 1, 'accept vs decline one winner');
  const afterAd = concDb.state.invitations.find((item) => Number(item.id) === Number(pendingId));
  assert(afterAd.status === 'accepted' || afterAd.status === 'declined', 'terminal accept/decline');
  if (afterAd.status === 'accepted') {
    concDb.removeMember(concCommunity.id, INVITEE_ID);
    concDb.state.declines.forEach((row) => {
      if (Number(row.invitee_user_id) === INVITEE_ID) {
        row.decline_count = 0;
      }
    });
  }
  console.log('O OK concurrent accept vs decline one winner');

  const dualInvite = await createInvitation(
    OWNER_ID,
    concCommunity.id,
    { user_id: INVITEE_ID },
    { db: concDb }
  );
  const twoAccepts = await Promise.allSettled([
    acceptInvitation(INVITEE_ID, dualInvite.id, { db: concDb }),
    acceptInvitation(INVITEE_ID, dualInvite.id, { db: concDb }),
  ]);
  assert(
    twoAccepts.filter((item) => item.status === 'fulfilled').length === 1,
    'one concurrent accept wins'
  );
  assert(
    twoAccepts.filter((item) => item.status === 'rejected').length === 1,
    'loser concurrent accept rejected'
  );
  const memberCount = concDb.state.members.filter(
    (item) => Number(item.community_id) === Number(concCommunity.id) && Number(item.user_id) === INVITEE_ID
  ).length;
  assert(memberCount === 1, 'single membership after two accepts');
  concDb.removeMember(concCommunity.id, INVITEE_ID);
  console.log('P OK concurrent double accept');

  const cancelRaceInvite = await createInvitation(
    OWNER_ID,
    concCommunity.id,
    { user_id: INVITEE_ID },
    { db: concDb }
  );
  const cancelAccept = await Promise.allSettled([
    cancelInvitation(OWNER_ID, cancelRaceInvite.id, { db: concDb }),
    acceptInvitation(INVITEE_ID, cancelRaceInvite.id, { db: concDb }),
  ]);
  assert(cancelAccept.filter((item) => item.status === 'fulfilled').length === 1, 'cancel vs accept one winner');
  const afterCancelRace = concDb.state.invitations.find(
    (item) => Number(item.id) === Number(cancelRaceInvite.id)
  );
  assert(
    afterCancelRace.status === 'cancelled' || afterCancelRace.status === 'accepted',
    'cancel/accept terminal'
  );
  if (afterCancelRace.status === 'accepted') {
    concDb.removeMember(concCommunity.id, INVITEE_ID);
  }
  console.log('Q OK concurrent cancel vs accept');

  const sentDb = createInvitationMemory();
  const sentCommunity = sentDb.seedCommunity('Cercle envoyees', OWNER_ID);
  sentDb.addMember(sentCommunity.id, ADMIN_ID, 'admin');
  const acceptedInvite = await createInvitation(
    OWNER_ID,
    sentCommunity.id,
    { user_id: INVITEE_ID },
    { db: sentDb }
  );
  await acceptInvitation(INVITEE_ID, acceptedInvite.id, { db: sentDb });
  sentDb.removeMember(sentCommunity.id, INVITEE_ID);
  const declinedInvite = await createInvitation(
    OWNER_ID,
    sentCommunity.id,
    { user_id: INVITEE_ID },
    { db: sentDb }
  );
  await declineInvitation(INVITEE_ID, declinedInvite.id, { db: sentDb });
  const pendingInvite = await createInvitation(
    OWNER_ID,
    sentCommunity.id,
    { user_id: INVITEE_ID },
    { db: sentDb }
  );
  const cancelledInvite = await createInvitation(
    OWNER_ID,
    sentCommunity.id,
    { user_id: STRANGER_ID },
    { db: sentDb }
  );
  await cancelInvitation(OWNER_ID, cancelledInvite.id, { db: sentDb });
  const replacedInvite = await createInvitation(
    OWNER_ID,
    sentCommunity.id,
    { user_id: STRANGER_ID },
    { db: sentDb }
  );
  const replacementInvite = await createInvitation(
    OWNER_ID,
    sentCommunity.id,
    { user_id: STRANGER_ID },
    { db: sentDb }
  );
  const replacedRow = sentDb.state.invitations.find(
    (item) => Number(item.id) === Number(replacedInvite.id)
  );
  assert(replacedRow.status === 'replaced', 'sent list fixture replaced');

  const sentList = await listSentInvitations(OWNER_ID, sentCommunity.id, { db: sentDb });
  const sentIds = sentList.items.map((item) => Number(item.id));
  assert(sentIds.includes(Number(pendingInvite.id)), 'sent list pending');
  assert(sentIds.includes(Number(declinedInvite.id)), 'sent list declined');
  assert(sentIds.includes(Number(acceptedInvite.id)), 'sent list accepted');
  assert(sentIds.includes(Number(replacementInvite.id)), 'sent list latest pending stranger');
  assert(!sentIds.includes(Number(cancelledInvite.id)), 'sent list excludes cancelled');
  assert(!sentIds.includes(Number(replacedInvite.id)), 'sent list excludes replaced');
  for (const item of sentList.items) {
    assert(sentItemsSafe(item), `sent keys ${inboxKeys(item)}`);
    assert(!Object.prototype.hasOwnProperty.call(item, 'phone'), 'sent phone');
    assert(!Object.prototype.hasOwnProperty.call(item, 'phone_number'), 'sent phone_number');
    assert(!Object.prototype.hasOwnProperty.call(item, 'email'), 'sent email');
    assert(!Object.prototype.hasOwnProperty.call(item, 'invitee_user_id'), 'sent invitee id');
  }
  const declinedItem = sentList.items.find((item) => Number(item.id) === Number(declinedInvite.id));
  assert(declinedItem.status === 'declined', 'declined status');
  assert(declinedItem.invitee_login === 'invitee7', 'declined login');
  assert(typeof declinedItem.declined_at === 'string' && declinedItem.declined_at.length > 0, 'declined_at');
  const pendingItem = sentList.items.find((item) => Number(item.id) === Number(pendingInvite.id));
  assert(pendingItem.declined_at === null, 'pending declined_at null');
  const acceptedItem = sentList.items.find((item) => Number(item.id) === Number(acceptedInvite.id));
  assert(acceptedItem.declined_at === null, 'accepted declined_at null');

  await expectAsyncAppError(
    listSentInvitations(ADMIN_ID, sentCommunity.id, { db: sentDb }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(
    listSentInvitations(INVITEE_ID, sentCommunity.id, { db: sentDb }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(
    listSentInvitations(STRANGER_ID, sentCommunity.id, { db: sentDb }),
    404,
    NOT_FOUND
  );
  await expectAsyncAppError(listSentInvitations(OWNER_ID, 9999, { db: sentDb }), 404, NOT_FOUND);
  console.log('Q2 OK owner sent list pending/declined/accepted; others 404; no secrets');

  const threshDb = createInvitationMemory();
  const threshCommunity = threshDb.seedCommunity('Cercle seuil refus', OWNER_ID);
  threshDb.state.declines.push({
    community_id: threshCommunity.id,
    invitee_user_id: INVITEE_ID,
    decline_count: 4,
    created_at: new Date(),
    updated_at: new Date(),
  });
  const nearLimit = await createInvitation(
    OWNER_ID,
    threshCommunity.id,
    { user_id: INVITEE_ID },
    { db: threshDb }
  );
  const twoDeclines = await Promise.allSettled([
    declineInvitation(INVITEE_ID, nearLimit.id, { db: threshDb }),
    declineInvitation(INVITEE_ID, nearLimit.id, { db: threshDb }),
  ]);
  assert(twoDeclines.filter((item) => item.status === 'fulfilled').length === 1, 'one decline near limit');
  assert(threshDb.declineCount(threshCommunity.id, INVITEE_ID) === 5, 'counter stops at 5');
  await expectAsyncAppError(
    createInvitation(OWNER_ID, threshCommunity.id, { user_id: INVITEE_ID }, { db: threshDb }),
    400,
    LIMIT_REACHED
  );
  console.log('R OK concurrent declines near threshold');

  const origQuery = pool.query;
  const origConnect = pool.connect;
  pool.query = (sql, params) => db.query(sql, params);
  pool.connect = () => db.connect();

  const app = express();
  app.use(express.json({ limit: '32kb' }));
  app.use('/communities', communityRoutes);
  app.use('/invitations', invitationRoutes);
  app.use(errorHandler);
  const server = await new Promise((resolve) => {
    const httpServer = app.listen(HTTP_PORT, '127.0.0.1', () => resolve(httpServer));
  });

  try {
    const ownerAuth = authFor(OWNER_ID, 'owner42');
    const inviteeAuth = authFor(INVITEE_ID, 'invitee7');
    const adminAuth = authFor(ADMIN_ID, 'admin9');
    const strangerAuth = authFor(STRANGER_ID, 'stranger11');

    const httpInvite = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${community.id}/invitations`,
      headers: ownerAuth,
      body: { user_id: INVITEE_ID },
    });
    assert(httpInvite.status === 201, `http create ${httpInvite.status} ${httpInvite.raw}`);
    assert(httpInvite.json.invitation.status === 'pending', 'http pending');
    assert(!JSON.stringify(httpInvite.json).includes('phone'), 'http leaked phone');
    const invitationId = httpInvite.json.invitation.id;

    const listed = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/invitations',
      headers: inviteeAuth,
    });
    assert(listed.status === 200, `inbox ${listed.status}`);
    assert(listed.json.items.some((item) => Number(item.id) === Number(invitationId)), 'inbox contains');
    for (const item of listed.json.items) {
      assert(inboxItemsSafe(item), `inbox keys ${inboxKeys(item)}`);
    }

    const adminCreate = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${community.id}/invitations`,
      headers: adminAuth,
      body: { user_id: STRANGER_ID },
    });
    assert(adminCreate.status === 400, `admin invite ${adminCreate.status}`);
    assert(adminCreate.json.error === CANNOT_SEND, adminCreate.raw);

    const strangerCreate = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${community.id}/invitations`,
      headers: strangerAuth,
      body: { user_id: INVITEE_ID },
    });
    assert(strangerCreate.status === 404, `stranger invite ${strangerCreate.status}`);
    assert(strangerCreate.json.error === NOT_FOUND, strangerCreate.raw);

    const selfInvite = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${community.id}/invitations`,
      headers: ownerAuth,
      body: { user_id: OWNER_ID },
    });
    assert(selfInvite.status === 400 && selfInvite.json.error === CANNOT_INVITE_SELF, selfInvite.raw);

    const thirdAccept = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/invitations/${invitationId}/accept`,
      headers: strangerAuth,
    });
    assert(thirdAccept.status === 404, `third accept ${thirdAccept.status}`);

    const acceptedHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/invitations/${invitationId}/accept`,
      headers: inviteeAuth,
    });
    assert(acceptedHttp.status === 200, `accept http ${acceptedHttp.status} ${acceptedHttp.raw}`);
    assert(acceptedHttp.json.invitation.status === 'accepted', 'http accepted');
    assert(acceptedHttp.json.membership.role === 'member', 'http member');

    db.removeMember(community.id, INVITEE_ID);
    const declineInvite = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${community.id}/invitations`,
      headers: ownerAuth,
      body: { user_id: INVITEE_ID },
    });
    const declineId = declineInvite.json.invitation.id;
    const declinedHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/invitations/${declineId}/decline`,
      headers: inviteeAuth,
    });
    assert(declinedHttp.status === 200, `decline http ${declinedHttp.status}`);
    assert(declinedHttp.json.invitation.status === 'declined', 'http declined');

    const cancelInvite = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${community.id}/invitations`,
      headers: ownerAuth,
      body: { user_id: INVITEE_ID },
    });
    const cancelId = cancelInvite.json.invitation.id;
    const cancelByAdmin = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/invitations/${cancelId}/cancel`,
      headers: adminAuth,
    });
    assert(cancelByAdmin.status === 400, `admin cancel ${cancelByAdmin.status}`);
    const cancelledHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/invitations/${cancelId}/cancel`,
      headers: ownerAuth,
    });
    assert(cancelledHttp.status === 200, `cancel http ${cancelledHttp.status}`);
    assert(cancelledHttp.json.invitation.status === 'cancelled', 'http cancelled');

    const httpSentCommunity = db.seedCommunity('HTTP envoyees', OWNER_ID);
    db.addMember(httpSentCommunity.id, ADMIN_ID, 'admin');
    const httpPendingInvite = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpSentCommunity.id}/invitations`,
      headers: ownerAuth,
      body: { user_id: INVITEE_ID },
    });
    assert(httpPendingInvite.status === 201, `http sent pending ${httpPendingInvite.status}`);
    const httpPendingId = httpPendingInvite.json.invitation.id;
    const httpDeclineInvite = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${httpSentCommunity.id}/invitations`,
      headers: ownerAuth,
      body: { user_id: STRANGER_ID },
    });
    const httpDeclineId = httpDeclineInvite.json.invitation.id;
    const httpDeclined = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/invitations/${httpDeclineId}/decline`,
      headers: strangerAuth,
    });
    assert(httpDeclined.status === 200, `http sent decline ${httpDeclined.status}`);

    const ownerSentHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${httpSentCommunity.id}/invitations`,
      headers: ownerAuth,
    });
    assert(ownerSentHttp.status === 200, `owner sent http ${ownerSentHttp.status} ${ownerSentHttp.raw}`);
    const httpSentIds = ownerSentHttp.json.items.map((item) => Number(item.id));
    assert(httpSentIds.includes(Number(httpPendingId)), 'http sent pending');
    assert(httpSentIds.includes(Number(httpDeclineId)), 'http sent declined');
    for (const item of ownerSentHttp.json.items) {
      assert(sentItemsSafe(item), `http sent keys ${inboxKeys(item)}`);
    }
    assert(!JSON.stringify(ownerSentHttp.json).includes('phone'), 'http sent leaked phone');

    const adminSentHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${httpSentCommunity.id}/invitations`,
      headers: adminAuth,
    });
    assert(adminSentHttp.status === 404, `admin sent ${adminSentHttp.status}`);
    assert(adminSentHttp.json.error === NOT_FOUND, adminSentHttp.raw);

    const strangerSentHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${httpSentCommunity.id}/invitations`,
      headers: strangerAuth,
    });
    assert(strangerSentHttp.status === 404, `stranger sent ${strangerSentHttp.status}`);

    const missingSentHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/communities/99999/invitations',
      headers: ownerAuth,
    });
    assert(missingSentHttp.status === 404, `missing sent ${missingSentHttp.status}`);
    console.log('S OK HTTP create/inbox/accept/decline/cancel and authz');
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
      urlPath: '/communities/1/invitations',
      body: { user_id: 7 },
    });
    assert(unauthCreate.status === 401, `unauth create ${unauthCreate.status}`);
    const unauthList = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/invitations',
    });
    assert(unauthList.status === 401, `unauth list ${unauthList.status}`);
    const unauthAccept = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/invitations/1/accept',
    });
    assert(unauthAccept.status === 401, `unauth accept ${unauthAccept.status}`);
    const unauthSent = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/communities/1/invitations',
    });
    assert(unauthSent.status === 401, `unauth sent ${unauthSent.status}`);
    console.log('T OK unauthenticated invitation routes -> 401');
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

  console.log('Community invitation check succeeded (mock DB, sans Neon ni R2).');
}

function inboxItemsSafe(item) {
  const keys = inboxKeys(item);
  return keys === 'community_id,community_name,created_at,id,invited_by_login,status';
}

function sentItemsSafe(item) {
  const keys = inboxKeys(item);
  return keys === 'created_at,declined_at,id,invitee_login,status';
}

main().catch((err) => {
  console.error('Community invitation check failed:', err.message);
  process.exitCode = 1;
});
