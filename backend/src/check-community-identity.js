const http = require('http');
const express = require('express');
const { generateAccessToken } = require('./services/tokenService');
const AppError = require('./errors/AppError');
const {
  parseIdentityUploadInput,
  parseIdentityCompleteInput,
  MAX_BYTES,
} = require('./validators/communityIdentityFields');
const { createCommunity } = require('./services/communityService');
const {
  createIdentityUpload,
  completeIdentityUpload,
} = require('./services/communityIdentityService');
const mockStorage = require('./services/mockStorageService');
const pool = require('./db');
const errorHandler = require('./middleware/errorHandler');
const communityRoutes = require('./routes/communities');

const TEST_SECRET = 'community-identity-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const HTTP_PORT = 30471;
const OWNER_ID = 42;
const ADMIN_ID = 7;
const MEMBER_ID = 9;
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

function assertNoSecrets(payload) {
  const text = JSON.stringify(payload);
  assert(!text.includes('avatar_storage_key'), 'leaked avatar_storage_key');
  assert(!text.includes('banner_storage_key'), 'leaked banner_storage_key');
  assert(!text.includes('storage_key'), 'leaked storage_key');
  assert(!text.includes('password'), 'leaked password');
}

function createMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner42' },
    { id: ADMIN_ID, login: 'admin7' },
    { id: MEMBER_ID, login: 'member9' },
    { id: STRANGER_ID, login: 'stranger11' },
  ];
  const state = {
    communities: [],
    members: [],
  };
  let nextCommunityId = 1;
  let nextMemberId = 1;
  let snapshot = null;

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

    if (key.startsWith('UPDATE COMMUNITIES')) {
      const nextKey = params[0];
      const id = Number(params[1]);
      const community = state.communities.find((item) => Number(item.id) === id);
      if (!community) {
        return { rows: [], rowCount: 0 };
      }
      if (key.includes('AVATAR_STORAGE_KEY')) {
        community.avatar_storage_key = nextKey;
      }
      if (key.includes('BANNER_STORAGE_KEY')) {
        community.banner_storage_key = nextKey;
      }
      community.updated_at = new Date();
      return { rows: [{ ...community }], rowCount: 1 };
    }

    if (key.includes('FROM COMMUNITIES') && key.includes('FOR UPDATE') && !key.includes('JOIN')) {
      const id = Number(params[0]);
      const community = state.communities.find((item) => Number(item.id) === id);
      if (!community) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rows: [
          {
            id: community.id,
            created_by: community.created_by,
            avatar_storage_key: community.avatar_storage_key,
            banner_storage_key: community.banner_storage_key,
          },
        ],
        rowCount: 1,
      };
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

    if (key.includes('INNER JOIN COMMUNITY_MEMBERS M') && key.includes('M.USER_ID = $1') && !key.includes('WHERE C.ID')) {
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
          avatar_storage_key: community.avatar_storage_key,
          member_count: memberCount(community.id),
        }));
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
    users,
    addMember(communityId, userId, role) {
      state.members.push({
        id: nextMemberId,
        community_id: Number(communityId),
        user_id: Number(userId),
        role,
        role_assigned_at: null,
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
          ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': payload.length } : {}),
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try {
            json = raw ? JSON.parse(raw) : null;
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

function tokenFor(id, login) {
  return generateAccessToken({ id, login, auth_provider: 'local' });
}

async function putObjectFromUpload(upload, byteSize) {
  const encoded = String(upload.url).split('/upload/')[1];
  const storageKey = decodeURIComponent(encoded);
  mockStorage.put(storageKey, { byteSize, contentType: 'image/jpeg' });
  return storageKey;
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
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://community-identity-test/local';

  mockStorage.reset();

  expectAppError(() => parseIdentityUploadInput({}), 400, 'content_type is invalid');
  expectAppError(
    () => parseIdentityUploadInput({ content_type: 'image/heic', byte_size: 12 }),
    400,
    'content_type is invalid'
  );
  expectAppError(
    () => parseIdentityUploadInput({ content_type: 'image/jpeg', byte_size: MAX_BYTES + 1 }),
    400,
    'Media quota exceeded'
  );
  expectAppError(
    () => parseIdentityUploadInput({ content_type: 'image/jpeg', byte_size: 12, storage_key: 'x' }),
    400,
    'storage_key cannot be set'
  );
  parseIdentityUploadInput({ content_type: 'image/png', byte_size: 24 });
  expectAppError(() => parseIdentityCompleteInput({}), 400, 'upload_id is required');
  expectAppError(
    () => parseIdentityCompleteInput({ upload_id: 'abc', avatar_storage_key: 'x' }),
    400,
    'avatar_storage_key cannot be set'
  );
  console.log('A OK identity validators');

  const db = createMemory();
  const created = await createCommunity(OWNER_ID, { name: 'Jardin secret' }, { db, storage: mockStorage });
  db.addMember(created.id, ADMIN_ID, 'admin');
  db.addMember(created.id, MEMBER_ID, 'member');
  assert(!created.avatar_read_url, 'new community has no avatar url');
  assert(!created.banner_read_url, 'new community has no banner url');
  assertNoSecrets(created);

  await expectAsyncAppError(
    createIdentityUpload(ADMIN_ID, created.id, 'avatar', { content_type: 'image/jpeg', byte_size: 12 }, { db, storage: mockStorage }),
    403,
    'Forbidden'
  );
  await expectAsyncAppError(
    createIdentityUpload(MEMBER_ID, created.id, 'banner', { content_type: 'image/jpeg', byte_size: 12 }, { db, storage: mockStorage }),
    403,
    'Forbidden'
  );
  await expectAsyncAppError(
    createIdentityUpload(STRANGER_ID, created.id, 'avatar', { content_type: 'image/jpeg', byte_size: 12 }, { db, storage: mockStorage }),
    404,
    'Community not found'
  );
  console.log('B OK owner-only identity writes');

  const initAvatar = await createIdentityUpload(
    OWNER_ID,
    created.id,
    'avatar',
    { content_type: 'image/jpeg', byte_size: 12 },
    { db, storage: mockStorage }
  );
  assert(typeof initAvatar.upload_id === 'string' && initAvatar.upload_id.length > 20, 'opaque upload_id');
  assert(initAvatar.slot === 'avatar', 'avatar slot');
  assert(initAvatar.upload && initAvatar.upload.method === 'PUT', 'signed PUT');
  assertNoSecrets(initAvatar);
  const firstKey = await putObjectFromUpload(initAvatar.upload, 12);
  const completed = await completeIdentityUpload(
    OWNER_ID,
    created.id,
    'avatar',
    { upload_id: initAvatar.upload_id },
    { db, storage: mockStorage }
  );
  assert(typeof completed.community.avatar_read_url === 'string', 'avatar read url after complete');
  assert(!completed.community.banner_read_url, 'banner still empty');
  assert(db.state.communities[0].avatar_storage_key === firstKey, 'key persisted');
  assertNoSecrets(completed);
  console.log('C OK avatar init/complete');

  const failInit = await createIdentityUpload(
    OWNER_ID,
    created.id,
    'avatar',
    { content_type: 'image/png', byte_size: 40 },
    { db, storage: mockStorage }
  );
  await expectAsyncAppError(
    completeIdentityUpload(
      OWNER_ID,
      created.id,
      'avatar',
      { upload_id: failInit.upload_id },
      { db, storage: mockStorage }
    ),
    400,
    'Upload is incomplete'
  );
  assert(db.state.communities[0].avatar_storage_key === firstKey, 'failed complete keeps previous key');
  console.log('D OK incomplete upload keeps previous avatar');

  const replaceInit = await createIdentityUpload(
    OWNER_ID,
    created.id,
    'avatar',
    { content_type: 'image/webp', byte_size: 18 },
    { db, storage: mockStorage }
  );
  const secondKey = await putObjectFromUpload(replaceInit.upload, 18);
  const replaced = await completeIdentityUpload(
    OWNER_ID,
    created.id,
    'avatar',
    { upload_id: replaceInit.upload_id },
    { db, storage: mockStorage }
  );
  assert(db.state.communities[0].avatar_storage_key === secondKey, 'replacement key stored');
  assert(mockStorage.getObject(firstKey) == null, 'previous r2 object deleted');
  assert(mockStorage.getObject(secondKey), 'new r2 object kept');
  assert(replaced.community.avatar_read_url.includes(encodeURIComponent(secondKey)), 'new signed url');
  console.log('E OK avatar replacement deletes previous object after success');

  const bannerInit = await createIdentityUpload(
    OWNER_ID,
    created.id,
    'banner',
    { content_type: 'image/jpeg', byte_size: 30 },
    { db, storage: mockStorage }
  );
  await putObjectFromUpload(bannerInit.upload, 30);
  const bannerDone = await completeIdentityUpload(
    OWNER_ID,
    created.id,
    'banner',
    { upload_id: bannerInit.upload_id },
    { db, storage: mockStorage }
  );
  assert(typeof bannerDone.community.banner_read_url === 'string', 'banner read url');
  assert(typeof bannerDone.community.avatar_read_url === 'string', 'avatar still present');
  assertNoSecrets(bannerDone);
  console.log('F OK banner complete is independent');

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
    const ownerAuth = { Authorization: `Bearer ${tokenFor(OWNER_ID, 'owner42')}` };
    const adminAuth = { Authorization: `Bearer ${tokenFor(ADMIN_ID, 'admin7')}` };
    const memberAuth = { Authorization: `Bearer ${tokenFor(MEMBER_ID, 'member9')}` };
    const strangerAuth = { Authorization: `Bearer ${tokenFor(STRANGER_ID, 'stranger11')}` };

    const listed = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/communities',
      headers: ownerAuth,
    });
    assert(listed.status === 200, `list ${listed.status}`);
    assert(typeof listed.json.items[0].avatar_read_url === 'string', 'list includes avatar url');
    assert(!Object.prototype.hasOwnProperty.call(listed.json.items[0], 'banner_read_url'), 'list omits banner url');
    assertNoSecrets(listed.json);

    const searched = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: '/communities/search?q=Jardin',
      headers: strangerAuth,
    });
    assert(searched.status === 200, `search ${searched.status}`);
    assert(typeof searched.json.items[0].avatar_read_url === 'string', 'search includes avatar url');
    assert(!Object.prototype.hasOwnProperty.call(searched.json.items[0], 'banner_read_url'), 'search omits banner');
    assertNoSecrets(searched.json);

    const detail = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${created.id}`,
      headers: memberAuth,
    });
    assert(detail.status === 200, `member get ${detail.status}`);
    assert(typeof detail.json.community.avatar_read_url === 'string', 'member sees avatar');
    assert(typeof detail.json.community.banner_read_url === 'string', 'member sees banner');
    assertNoSecrets(detail.json);

    const hidden = await httpRequest({
      port: HTTP_PORT,
      method: 'GET',
      urlPath: `/communities/${created.id}`,
      headers: strangerAuth,
    });
    assert(hidden.status === 404, `stranger get ${hidden.status}`);

    const adminInit = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${created.id}/avatar/uploads`,
      headers: adminAuth,
      body: { content_type: 'image/jpeg', byte_size: 12 },
    });
    assert(adminInit.status === 403, `admin upload ${adminInit.status}`);

    const memberInit = await httpRequest({
      port: HTTP_PORT,
      method: 'POST',
      urlPath: `/communities/${created.id}/banner/uploads`,
      headers: memberAuth,
      body: { content_type: 'image/jpeg', byte_size: 12 },
    });
    assert(memberInit.status === 403, `member upload ${memberInit.status}`);
    console.log('G OK HTTP read urls, search, owner-only writes');
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

  console.log('Community identity check succeeded (mock DB / mock storage, sans Neon ni R2).');
}

main().catch((err) => {
  console.error('Community identity check failed:', err.message);
  process.exitCode = 1;
});
