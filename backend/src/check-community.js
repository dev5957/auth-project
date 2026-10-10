const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const express = require('express');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const {
  parseCreateCommunityInput,
  parseSearchQuery,
  parseRolePatch,
  parseCommunityId,
} = require('./validators/communityFields');
const {
  createCommunity,
  listMyCommunities,
  getCommunityById,
  searchCommunities,
  listCommunityMembers,
  updateMemberRole,
  NOT_FOUND,
} = require('./services/communityService');
const pool = require('./db');
const errorHandler = require('./middleware/errorHandler');
const communityRoutes = require('./routes/communities');

const TEST_SECRET = 'community-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30460;
const HTTP_PORT = 30461;
const OWNER_ID = 42;
const OTHER_ID = 7;
const THIRD_ID = 9;

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

function createCommunityMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner42' },
    { id: OTHER_ID, login: 'member7' },
    { id: THIRD_ID, login: 'user9' },
  ];
  const state = {
    communities: [],
    members: [],
  };
  let nextCommunityId = 1;
  let nextMemberId = 1;
  let snapshot = null;
  let failMemberInsert = false;

  function memberCount(communityId) {
    return state.members.filter((item) => Number(item.community_id) === Number(communityId)).length;
  }

  async function query(sql, params = []) {
    const key = sqlKey(sql);
    if (key === 'BEGIN') {
      snapshot = {
        communities: state.communities.map((row) => ({ ...row })),
        members: state.members.map((row) => ({ ...row })),
        nextCommunityId,
        nextMemberId,
      };
      return { rows: [], rowCount: 0 };
    }
    if (key === 'COMMIT') {
      snapshot = null;
      return { rows: [], rowCount: 0 };
    }
    if (key === 'ROLLBACK') {
      if (snapshot) {
        state.communities = snapshot.communities;
        state.members = snapshot.members;
        nextCommunityId = snapshot.nextCommunityId;
        nextMemberId = snapshot.nextMemberId;
        snapshot = null;
      }
      return { rows: [], rowCount: 0 };
    }

    if (
      key.includes('COMMUNITY_PUBLICATIONS') ||
      key.includes('COMMUNITY_PUBLICATION_MEDIA') ||
      key.includes('COMMUNITY_PUBLICATION_LIKES') ||
      key.includes('COMMUNITY_PUBLICATION_FAVORITES')
    ) {
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
        avatar_storage_key: null,
        banner_storage_key: null,
        created_at: now,
        updated_at: now,
      };
      nextCommunityId += 1;
      state.communities.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }

    if (key.startsWith('INSERT INTO COMMUNITY_MEMBERS')) {
      if (failMemberInsert) {
        throw new Error('member insert failed');
      }
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
      const communityId = Number(params[0]);
      const ownerCount = state.members.filter(
        (item) => Number(item.community_id) === communityId && item.role === 'owner'
      ).length;
      return { rows: [{ owner_count: ownerCount }], rowCount: 1 };
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
        .slice(0, 1)
        .map((item) => ({
          user_id: item.user_id,
          role: item.role,
          role_assigned_at: item.role_assigned_at,
        }));
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('UPDATE COMMUNITY_MEMBERS') && key.includes("ROLE = 'OWNER'")) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
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

    if (key.includes('INNER JOIN COMMUNITY_MEMBERS M') && key.includes('M.USER_ID = $1')) {
      const userId = Number(params[0]);
      const limit = Number(params[1]);
      const rows = state.communities
        .filter((community) =>
          state.members.some(
            (item) => Number(item.community_id) === Number(community.id) && Number(item.user_id) === userId
          )
        )
        .sort((a, b) => b.created_at - a.created_at || Number(b.id) - Number(a.id))
        .slice(0, limit)
        .map((community) => {
          const membership = state.members.find(
            (item) => Number(item.community_id) === Number(community.id) && Number(item.user_id) === userId
          );
          return {
            ...community,
            my_role: membership.role,
            member_count: memberCount(community.id),
          };
        });
      return { rows, rowCount: rows.length };
    }

    if (key.includes('ILIKE')) {
      const pattern = String(params[0]);
      const limit = Number(params[1]);
      const needle = pattern.replace(/^%/, '').replace(/%$/, '').replace(/\\/g, '');
      const rows = state.communities
        .filter((item) => String(item.name).toLowerCase().includes(needle.toLowerCase()))
        .sort((a, b) => String(a.name).localeCompare(String(b.name)) || Number(a.id) - Number(b.id))
        .slice(0, limit)
        .map((community) => ({
          id: community.id,
          name: community.name,
          description: community.description,
          member_count: memberCount(community.id),
        }));
      return { rows, rowCount: rows.length };
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
      return { rows: [{ user_id: row.user_id, login: user.login, role: row.role, role_assigned_at: row.role_assigned_at || null }], rowCount: 1 };
    }

    if (key.includes('INNER JOIN USERS U') && key.includes('WHERE M.COMMUNITY_ID = $1')) {
      const communityId = Number(params[0]);
      const order = { owner: 0, admin: 1, member: 2 };
      const rows = state.members
        .filter((item) => Number(item.community_id) === communityId)
        .map((item) => {
          const user = users.find((entry) => Number(entry.id) === Number(item.user_id));
          return { user_id: item.user_id, login: user ? user.login : 'unknown', role: item.role, role_assigned_at: item.role_assigned_at || null };
        })
        .sort((a, b) => (order[a.role] ?? 9) - (order[b.role] ?? 9) || Number(a.user_id) - Number(b.user_id));
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM COMMUNITY_MEMBERS') && key.includes('USER_ID = $2')) {
      const communityId = Number(params[0]);
      const userId = Number(params[1]);
      const row = state.members.find(
        (item) => Number(item.community_id) === communityId && Number(item.user_id) === userId
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [{ user_id: row.user_id, role: row.role, role_assigned_at: row.role_assigned_at || null }], rowCount: 1 };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  return {
    state,
    setFailMemberInsert(value) {
      failMemberInsert = value;
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
    connect: async () => ({
      query,
      release() {},
    }),
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

function validName(overrides = 'Jardin secret') {
  return overrides;
}

function assertNoSecrets(payload) {
  const text = JSON.stringify(payload);
  assert(!text.includes('avatar_storage_key'), 'leaked avatar_storage_key');
  assert(!text.includes('banner_storage_key'), 'leaked banner_storage_key');
  assert(!text.includes('must-never-leak'), 'leaked storage key value');
  assert(!text.includes('password'), 'leaked password');
  assert(!/"email"/.test(text), 'leaked email');
  assert(!text.includes('phone'), 'leaked phone');
  assert(!text.includes('publication'), 'leaked publication');
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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://community-test/local';

  expectAppError(() => parseCreateCommunityInput({}), 400, 'name is required');
  expectAppError(() => parseCreateCommunityInput({ name: '   short   ' }), 400, 'name is too short');
  expectAppError(() => parseCreateCommunityInput({ name: 'abcdefghi' }), 400, 'name is too short');
  parseCreateCommunityInput({ name: 'abcdefghij' });
  expectAppError(() => parseCreateCommunityInput({ name: `${'a'.repeat(101)}` }), 400, 'name is too long');
  expectAppError(
    () => parseCreateCommunityInput({ name: validName(), description: 'x'.repeat(501) }),
    400,
    'description is too long'
  );
  const trimmed = parseCreateCommunityInput({
    name: '  Jardin secret  ',
    description: '  hello  ',
  });
  assert(trimmed.name === 'Jardin secret', 'name trimmed');
  assert(trimmed.description === 'hello', 'description trimmed');
  expectAppError(() => parseCreateCommunityInput({ name: validName(), visibility: 'public' }), 400, 'visibility cannot be set');
  expectAppError(() => parseCreateCommunityInput({ name: validName(), created_by: 1 }), 400, 'created_by cannot be set');
  expectAppError(() => parseSearchQuery({}), 400, 'q is required');
  parseSearchQuery({ q: ' jardin ' });
  expectAppError(() => parseRolePatch({ role: 'owner' }), 400, 'role is invalid');
  expectAppError(() => parseCommunityId('abc'), 400, 'id is invalid');
  console.log('A OK validators name/description/search/role');

  const db = createCommunityMemory();
  const created = await createCommunity(OWNER_ID, { name: validName(), description: 'Un cercle privé' }, { db });
  assert(created.my_role === 'owner', 'creator is owner');
  assert(created.member_count === 1, 'owner is first member');
  assert(created.visibility === 'private', 'private default');
  assert(created.name === 'Jardin secret', 'created name');
  assertNoSecrets(created);
  assert(db.state.communities.length === 1, 'community persisted');
  assert(db.state.members.length === 1 && db.state.members[0].role === 'owner', 'owner row');
  console.log('B OK create community + owner atomically');

  const twin = await createCommunity(OWNER_ID, { name: validName() }, { db });
  assert(Number(twin.id) !== Number(created.id), 'homonyms get distinct ids');
  assert(twin.name === created.name, 'homonyms allowed');
  console.log('C OK homonyms allowed');

  db.setFailMemberInsert(true);
  try {
    await createCommunity(OWNER_ID, { name: 'Rollback club' }, { db });
    throw new Error('expected member insert to fail');
  } catch (err) {
    assert(String(err.message).includes('member insert failed'), err.message);
  }
  db.setFailMemberInsert(false);
  assert(
    db.state.communities.every((row) => row.name !== 'Rollback club'),
    'community rolled back when owner insert fails'
  );
  console.log('D OK rollback if owner member insert fails');

  const other = await createCommunity(OTHER_ID, { name: 'Cercle des autres' }, { db });
  const mine = await listMyCommunities(OWNER_ID, {}, { db });
  assert(
    mine.items.every((item) => Number(item.id) !== Number(other.id)),
    'list excludes others communities'
  );
  assert(
    mine.items.every((item) => item.my_role === 'owner' || item.my_role === 'admin' || item.my_role === 'member'),
    'list has roles'
  );
  console.log('E OK personal list is membership-only');

  const detail = await getCommunityById(OWNER_ID, created.id, { db });
  assert(detail.id === created.id, 'member detail');
  await expectAsyncAppError(getCommunityById(OTHER_ID, created.id, { db }), 404, NOT_FOUND);
  await expectAsyncAppError(getCommunityById(OWNER_ID, 9999, { db }), 404, NOT_FOUND);
  console.log('F OK detail member vs 404 non-member/missing');

  const found = await searchCommunities(OWNER_ID, { q: 'Jardin' }, { db });
  assert(found.items.length >= 1, 'search hits');
  for (const item of found.items) {
    assert(item.id != null && item.name != null, 'search preview identity');
    assert(Object.keys(item).sort().join(',') === 'description,id,member_count,name', `search keys ${Object.keys(item)}`);
    assertNoSecrets(item);
  }
  console.log('G OK search limited preview');

  db.addMember(created.id, OTHER_ID, 'member');
  const members = await listCommunityMembers(OWNER_ID, created.id, { db });
  assert(members.items.some((item) => Number(item.user_id) === OTHER_ID && item.role === 'member'), 'member listed');
  await expectAsyncAppError(listCommunityMembers(THIRD_ID, created.id, { db }), 404, NOT_FOUND);

  await expectAsyncAppError(
    updateMemberRole(OTHER_ID, created.id, OTHER_ID, { role: 'admin' }, { db }),
    400,
    'role cannot be set'
  );
  await expectAsyncAppError(
    updateMemberRole(OWNER_ID, created.id, OWNER_ID, { role: 'admin' }, { db }),
    400,
    'role cannot be set'
  );
  await expectAsyncAppError(
    updateMemberRole(OWNER_ID, created.id, OTHER_ID, { role: 'owner' }, { db }),
    400,
    'role is invalid'
  );

  const promoted = await updateMemberRole(OWNER_ID, created.id, OTHER_ID, { role: 'admin' }, { db });
  assert(promoted.role === 'admin', 'owner can name admin');
  assert(promoted.role_assigned_at, 'promotion stamps role_assigned_at');
  const demoted = await updateMemberRole(OWNER_ID, created.id, OTHER_ID, { role: 'member' }, { db });
  assert(demoted.role === 'member', 'owner can demote admin');
  assert(demoted.role_assigned_at == null, 'demotion clears role_assigned_at');
  await updateMemberRole(OWNER_ID, created.id, OTHER_ID, { role: 'admin' }, { db });
  await expectAsyncAppError(
    updateMemberRole(OTHER_ID, created.id, THIRD_ID, { role: 'member' }, { db }),
    400,
    'role cannot be set'
  );
  await expectAsyncAppError(
    updateMemberRole(OWNER_ID, created.id, OWNER_ID, { role: 'member' }, { db }),
    400,
    'role cannot be set'
  );
  const ownerRow = db.state.members.find(
    (item) => Number(item.community_id) === Number(created.id) && Number(item.user_id) === OWNER_ID
  );
  assert(ownerRow.role === 'owner', 'owner role unchanged');
  console.log('H OK roles: owner manages admin/member, owner protected, admin has no extra power');

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
    const token = generateAccessToken({
      id: OWNER_ID,
      login: 'owner42',
      auth_provider: 'local',
    });
    const auth = { Authorization: `Bearer ${token}` };
    const createdHttp = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: '/communities',
      headers: auth,
      body: { name: 'Atelier lumineux' },
    });
    assert(createdHttp.status === 201, `http create ${createdHttp.status} ${createdHttp.raw}`);
    assert(createdHttp.json.community.my_role === 'owner', 'http owner');
    assertNoSecrets(createdHttp.json);

    const listed = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/communities',
      headers: auth,
    });
    assert(listed.status === 200, `http list ${listed.status}`);
    assert(Array.isArray(listed.json.items), 'http list items');

    const missing = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/communities/99999',
      headers: auth,
    });
    assert(missing.status === 404, `http missing ${missing.status}`);
    assert(missing.json.error === NOT_FOUND, missing.raw);

    const strangerToken = generateAccessToken({
      id: THIRD_ID,
      login: 'user9',
      auth_provider: 'local',
    });
    const hidden = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${createdHttp.json.community.id}`,
      headers: { Authorization: `Bearer ${strangerToken}` },
    });
    assert(hidden.status === 404, `http stranger ${hidden.status}`);
    assert(hidden.json.error === missing.json.error, 'same 404 contract');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    pool.query = origQuery;
    pool.connect = origConnect;
  }
  console.log('I OK HTTP create/list/detail 404 contract');

  const { child, logs } = startIndexServer(TEST_PORT);
  try {
    await waitForLog(logs, 'Server listening', 8000);
    const unauth = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/communities',
      body: { name: validName() },
    });
    assert(unauth.status === 401, `unauth ${unauth.status} ${unauth.raw}`);
    assert(unauth.json && unauth.json.error === 'Unauthorized', unauth.raw);
    const unauthGet = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/communities',
    });
    assert(unauthGet.status === 401, `unauth get ${unauthGet.status}`);
    console.log('J OK unauthenticated -> 401');
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

  console.log('Community check succeeded (mock DB, sans Neon ni R2).');
}

main().catch((err) => {
  console.error('Community check failed:', err.message);
  process.exitCode = 1;
});
