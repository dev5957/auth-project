const fs = require('fs');
const path = require('path');
const AppError = require('./errors/AppError');
const { createPublication, listFeed, getPublication, deletePublication } = require('./services/communityPublicationService');
const { likePublication, unlikePublication } = require('./services/communityPublicationLikeService');
const {
  favoritePublication,
  unfavoritePublication,
  listMyFavorites,
} = require('./services/communityPublicationFavoriteService');
const { leaveCommunity, removeMember } = require('./services/communityService');

const OWNER_ID = 1;
const MEMBER_ID = 2;
const ADMIN_ID = 3;
const MEMBER_B_ID = 5;
const STRANGER_ID = 99;
const COMMUNITY_A = 10;
const COMMUNITY_B = 11;
const SQL_PATH = path.join(__dirname, '..', 'sql', '019_create_community_publication_favorites.sql');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function expectReject(promise, statusCode) {
  try {
    await promise;
    throw new Error(`expected ${statusCode}`);
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err && err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode} got ${err.statusCode}: ${err.message}`);
  }
}

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function validPub(overrides = {}) {
  return {
    title: 'Soiree jardin',
    body: 'Un texte communautaire assez long.',
    publish: 'now',
    comments_enabled: true,
    ...overrides,
  };
}

function inspectSqlFile() {
  const sql = fs.readFileSync(SQL_PATH, 'utf8');
  const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
  assert(/MANUELLEMENT/i.test(sql), '019 must be documented as manual');
  assert(/CREATE TABLE IF NOT EXISTS community_publication_favorites/i.test(sql), '019 favorites table');
  assert(/UNIQUE \(community_publication_id, user_id\)/i.test(sql), '019 unique favorite');
  assert(/favorited_at/i.test(sql), '019 favorited_at');
  assert(/ON DELETE CASCADE/i.test(sql), '019 cascade from publication');
  assert(/community_publication_favorites_user_favorited_idx/i.test(sql), '019 user index');
  assert(!/like_count/i.test(code), '019 must not alter like_count');
  assert(!/favorite_count/i.test(code), '019 must not materialize favorite_count');
  assert(!/community_members/i.test(code), '019 must not FK community_members');
  console.log('SQL file OK (sql/019_create_community_publication_favorites.sql inspected, not applied).');
}

function inspectRoutes() {
  const communities = fs.readFileSync(path.join(__dirname, 'routes', 'communities.js'), 'utf8');
  const me = fs.readFileSync(path.join(__dirname, 'routes', 'meCommunityFavorites.js'), 'utf8');
  assert(/router\.use\(requireAuth\)/.test(communities), 'community routes require auth');
  assert(/publications\/:publicationId\/favorite/.test(communities), 'favorite mutation routes');
  assert(/router\.use\(requireAuth\)/.test(me), 'me favorites require auth');
}

function createMemory() {
  const users = [
    { id: OWNER_ID, login: 'owner1' },
    { id: MEMBER_ID, login: 'member2' },
    { id: ADMIN_ID, login: 'admin3' },
    { id: MEMBER_B_ID, login: 'member5' },
    { id: STRANGER_ID, login: 'stranger99' },
  ];
  const state = {
    communities: [
      { id: COMMUNITY_A, name: 'Jardin secret', created_by: OWNER_ID },
      { id: COMMUNITY_B, name: 'Atelier photo', created_by: OWNER_ID },
    ],
    members: [
      { community_id: COMMUNITY_A, user_id: OWNER_ID, role: 'owner' },
      { community_id: COMMUNITY_A, user_id: MEMBER_ID, role: 'member' },
      { community_id: COMMUNITY_A, user_id: ADMIN_ID, role: 'admin' },
      { community_id: COMMUNITY_A, user_id: MEMBER_B_ID, role: 'member' },
      { community_id: COMMUNITY_B, user_id: OWNER_ID, role: 'owner' },
      { community_id: COMMUNITY_B, user_id: MEMBER_ID, role: 'member' },
    ],
    publications: [],
    likes: [],
    favorites: [],
    comments: [],
  };
  let nextPubId = 1;
  let nextLikeId = 1;
  let nextFavoriteId = 1;
  let nextCommentId = 1;
  let snapshot = null;

  function cloneState() {
    return {
      publications: state.publications.map((item) => ({ ...item })),
      likes: state.likes.map((item) => ({ ...item })),
      favorites: state.favorites.map((item) => ({ ...item })),
      comments: state.comments.map((item) => ({ ...item })),
      members: state.members.map((item) => ({ ...item })),
      nextPubId,
      nextLikeId,
      nextFavoriteId,
      nextCommentId,
    };
  }

  function hydratePublication(item) {
    const community = state.communities.find((row) => Number(row.id) === Number(item.community_id)) || {};
    return {
      ...item,
      author_login: (users.find((u) => Number(u.id) === Number(item.author_user_id)) || {}).login,
      community_name: community.name,
      is_former_member: !state.members.some(
        (m) => Number(m.community_id) === Number(item.community_id) && Number(m.user_id) === Number(item.author_user_id)
      ),
    };
  }

  async function query(sql, params = []) {
    const key = sqlKey(sql);
    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      if (key === 'BEGIN') {
        snapshot = cloneState();
      } else if (key === 'COMMIT') {
        snapshot = null;
      } else if (snapshot) {
        state.publications = snapshot.publications;
        state.likes = snapshot.likes;
        state.favorites = snapshot.favorites;
        state.comments = snapshot.comments;
        state.members = snapshot.members;
        nextPubId = snapshot.nextPubId;
        nextLikeId = snapshot.nextLikeId;
        nextFavoriteId = snapshot.nextFavoriteId;
        nextCommentId = snapshot.nextCommentId;
        snapshot = null;
      }
      return { rows: [], rowCount: 0 };
    }
    if (
      key.includes('FROM COMMUNITY_MEMBERS') &&
      key.includes('USER_ID') &&
      (key.includes('LIMIT 1') || key.includes('FOR UPDATE')) &&
      !key.includes('COUNT(*)')
    ) {
      const row = state.members.find(
        (item) => Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return {
        rows: row ? [{ user_id: row.user_id, role: row.role, role_assigned_at: null }] : [],
        rowCount: row ? 1 : 0,
      };
    }
    if (key.includes('COUNT(*)') && key.includes('FROM COMMUNITY_MEMBERS') && key.includes("ROLE = 'OWNER'")) {
      const count = state.members.filter(
        (item) => Number(item.community_id) === Number(params[0]) && item.role === 'owner'
      ).length;
      return { rows: [{ owner_count: count }], rowCount: 1 };
    }
    if (key.startsWith('SELECT ID, LOGIN FROM USERS')) {
      const user = users.find((item) => Number(item.id) === Number(params[0]));
      return { rows: user ? [user] : [], rowCount: user ? 1 : 0 };
    }
    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATIONS')) {
      const now = new Date();
      const row = {
        id: nextPubId,
        community_id: params[0],
        author_user_id: params[1],
        title: params[2],
        body: params[3],
        status: params[4],
        scheduled_at: params[5],
        published_at: params[6],
        is_time_limited: params[7],
        expires_at: params[8],
        comments_enabled: params[9],
        like_count: 0,
        comment_count: 0,
        created_at: now,
        updated_at: now,
        expired_at: null,
        purge_after: null,
        deleted_at: null,
        deleted_by_user_id: null,
      };
      nextPubId += 1;
      state.publications.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATIONS P') && key.includes("P.STATUS = 'ACTIVE'") && key.includes('P.COMMUNITY_ID = $1')) {
      let rows = state.publications.filter(
        (item) => Number(item.community_id) === Number(params[0]) && item.status === 'active'
      );
      rows.sort((a, b) => {
        const ta = a.published_at ? new Date(a.published_at).getTime() : 0;
        const tb = b.published_at ? new Date(b.published_at).getTime() : 0;
        return tb - ta || Number(b.id) - Number(a.id);
      });
      const limit = Number(params[params.length - 1]);
      rows = rows.slice(0, limit).map(hydratePublication);
      return { rows, rowCount: rows.length };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('ID = $1 AND COMMUNITY_ID = $2')) {
      const row = state.publications.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.community_id) === Number(params[1])
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATIONS') && key.includes('WHERE ID = $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }
    if (key.startsWith('SELECT * FROM COMMUNITY_PUBLICATION_MEDIA')) {
      return { rows: [], rowCount: 0 };
    }
    if (key.startsWith('SELECT 1') && key.includes('FROM COMMUNITY_PUBLICATION_LIKES')) {
      const row = state.likes.find(
        (item) =>
          Number(item.community_publication_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [1] : [], rowCount: row ? 1 : 0 };
    }
    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATION_LIKES')) {
      const exists = state.likes.some(
        (item) =>
          Number(item.community_publication_id) === Number(params[1]) && Number(item.user_id) === Number(params[2])
      );
      if (exists) {
        return { rows: [], rowCount: 0 };
      }
      const row = {
        id: nextLikeId,
        community_id: params[0],
        community_publication_id: params[1],
        user_id: params[2],
      };
      nextLikeId += 1;
      state.likes.push(row);
      return { rows: [{ id: row.id }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = LIKE_COUNT + 1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.like_count = (Number(row.like_count) || 0) + 1;
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = GREATEST(LIKE_COUNT - 1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.like_count = Math.max((Number(row.like_count) || 0) - 1, 0);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = GREATEST(LIKE_COUNT - $1')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[1]));
      row.like_count = Math.max((Number(row.like_count) || 0) - Number(params[0]), 0);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('COMMENT_COUNT = (')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.comment_count = state.comments.filter(
        (item) => Number(item.community_publication_id) === Number(params[0]) && item.status === 'visible'
      ).length;
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATION_COMMENTS')) {
      const row = {
        id: nextCommentId,
        community_id: params[0],
        community_publication_id: params[1],
        author_user_id: params[2],
        body: params[3],
        status: params[4],
        parent_comment_id: params[5] == null ? null : params[5],
      };
      nextCommentId += 1;
      state.comments.push(row);
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATION_FAVORITES') && key.includes('ANY($1')) {
      const ids = (Array.isArray(params[0]) ? params[0] : []).map((value) => Number(value));
      const userId = Number(params[1]);
      const grouped = new Map();
      for (const item of state.favorites) {
        const publicationId = Number(item.community_publication_id);
        if (!ids.includes(publicationId)) {
          continue;
        }
        const current = grouped.get(publicationId) || { favorite_count: 0, favorited_by_me: false };
        current.favorite_count += 1;
        if (Number(item.user_id) === userId) {
          current.favorited_by_me = true;
        }
        grouped.set(publicationId, current);
      }
      const rows = [...grouped.entries()].map(([community_publication_id, value]) => ({
        community_publication_id,
        ...value,
      }));
      return { rows, rowCount: rows.length };
    }
    if (key.startsWith('SELECT COUNT(*)') && key.includes('FROM COMMUNITY_PUBLICATION_FAVORITES')) {
      const count = state.favorites.filter(
        (item) => Number(item.community_publication_id) === Number(params[0])
      ).length;
      return { rows: [{ favorite_count: count }], rowCount: 1 };
    }
    if (key.startsWith('INSERT INTO COMMUNITY_PUBLICATION_FAVORITES')) {
      const exists = state.favorites.some(
        (item) =>
          Number(item.community_publication_id) === Number(params[1]) && Number(item.user_id) === Number(params[2])
      );
      if (exists) {
        return { rows: [], rowCount: 0 };
      }
      const row = {
        id: nextFavoriteId,
        community_id: params[0],
        community_publication_id: params[1],
        user_id: params[2],
        favorited_at: new Date(Date.now() + nextFavoriteId),
      };
      nextFavoriteId += 1;
      state.favorites.push(row);
      return { rows: [{ id: row.id }], rowCount: 1 };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATION_FAVORITES FAV')) {
      const userId = Number(params[0]);
      let rows = state.favorites
        .filter((item) => Number(item.user_id) === userId)
        .map((fav) => {
          const pub = state.publications.find((item) => Number(item.id) === Number(fav.community_publication_id));
          return pub
            ? {
                ...hydratePublication(pub),
                favorite_id: fav.id,
                favorited_at: fav.favorited_at,
              }
            : null;
        })
        .filter((item) => item && item.status === 'active' && Number(item.author_user_id) !== userId)
        .filter((item) =>
          state.members.some(
            (member) => Number(member.community_id) === Number(item.community_id) && Number(member.user_id) === userId
          )
        );
      rows.sort(
        (a, b) =>
          new Date(b.favorited_at).getTime() - new Date(a.favorited_at).getTime() ||
          Number(b.favorite_id) - Number(a.favorite_id)
      );
      if (key.includes('$2::TIMESTAMPTZ')) {
        const beforeAt = new Date(params[1]).getTime();
        const beforeId = Number(params[2]);
        rows = rows.filter((item) => {
          const at = new Date(item.favorited_at).getTime();
          return at < beforeAt || (at === beforeAt && Number(item.favorite_id) < beforeId);
        });
      }
      const limit = Number(params[params.length - 1]);
      rows = rows.slice(0, limit);
      return { rows, rowCount: rows.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_FAVORITES') && key.includes('USER_ID = $2')) {
      const before = state.favorites.length;
      if (key.includes('COMMUNITY_ID = $1')) {
        state.favorites = state.favorites.filter(
          (item) => !(Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
        );
      } else {
        state.favorites = state.favorites.filter(
          (item) =>
            !(Number(item.community_publication_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
        );
      }
      return { rows: [], rowCount: before - state.favorites.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_FAVORITES')) {
      const before = state.favorites.length;
      state.favorites = state.favorites.filter(
        (item) => Number(item.community_publication_id) !== Number(params[0])
      );
      return { rows: [], rowCount: before - state.favorites.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('COMMUNITY_ID = $1')) {
      const ids = [
        ...new Set(
          state.likes
            .filter(
              (item) => Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
            )
            .map((item) => Number(item.community_publication_id))
        ),
      ];
      if (key.includes('DISTINCT')) {
        return {
          rows: ids.sort((a, b) => a - b).map((community_publication_id) => ({ community_publication_id })),
          rowCount: ids.length,
        };
      }
      state.likes = state.likes.filter(
        (item) => !(Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: [], rowCount: 0 };
    }
    if (key.includes('FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('DISTINCT')) {
      const ids = [
        ...new Set(
          state.likes
            .filter(
              (item) => Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
            )
            .map((item) => Number(item.community_publication_id))
        ),
      ].sort((a, b) => a - b);
      return {
        rows: ids.map((community_publication_id) => ({ community_publication_id })),
        rowCount: ids.length,
      };
    }
    if (key.startsWith('SELECT ID') && key.includes('FROM COMMUNITY_PUBLICATIONS') && key.includes('ANY($1')) {
      const ids = (Array.isArray(params[0]) ? params[0] : []).map((value) => Number(value));
      const rows = state.publications
        .filter((item) => ids.includes(Number(item.id)))
        .sort((a, b) => Number(a.id) - Number(b.id))
        .map((item) => ({ id: item.id }));
      return { rows, rowCount: rows.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES') && key.includes('USER_ID')) {
      const removed = state.likes.filter(
        (item) =>
          Number(item.community_publication_id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      state.likes = state.likes.filter(
        (item) =>
          !(Number(item.community_publication_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: removed.map((item) => ({ id: item.id })), rowCount: removed.length };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_LIKES')) {
      state.likes = state.likes.filter((item) => Number(item.community_publication_id) !== Number(params[0]));
      return { rows: [], rowCount: 0 };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_PUBLICATION_COMMENTS')) {
      state.comments = state.comments.filter((item) => Number(item.community_publication_id) !== Number(params[0]));
      return { rows: [], rowCount: 0 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('LIKE_COUNT = 0')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[0]));
      row.like_count = 0;
      row.comment_count = 0;
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('UPDATE COMMUNITY_PUBLICATIONS') && key.includes('DELETED_BY_USER_ID')) {
      const row = state.publications.find((item) => Number(item.id) === Number(params[3]));
      row.status = 'deleted';
      row.deleted_at = params[1];
      row.deleted_by_user_id = params[2];
      return { rows: [{ ...row }], rowCount: 1 };
    }
    if (key.startsWith('DELETE FROM COMMUNITY_MEMBERS')) {
      state.members = state.members.filter(
        (item) => !(Number(item.community_id) === Number(params[0]) && Number(item.user_id) === Number(params[1]))
      );
      return { rows: [], rowCount: 1 };
    }
    if (key.includes('FROM COMMUNITIES') && key.includes('FOR UPDATE')) {
      const row = state.communities.find((item) => Number(item.id) === Number(params[0]));
      return { rows: row ? [{ id: row.id, created_by: row.created_by }] : [], rowCount: row ? 1 : 0 };
    }
    if (key.includes("STATUS = 'DRAFT'") && key.includes('AUTHOR_USER_ID')) {
      return { rows: [], rowCount: 0 };
    }
    if (key.includes('COMMUNITY_PUBLICATION_MEDIA')) {
      return { rows: [], rowCount: 0 };
    }
    throw new Error(`unexpected sql: ${key.slice(0, 180)}`);
  }

  return {
    state,
    query,
    connect: async () => ({ query, release() {} }),
  };
}

async function main() {
  inspectSqlFile();
  inspectRoutes();
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://community-favorites-test/local';
  const db = createMemory();
  const deps = { db };

  const ownerPubA = await createPublication(OWNER_ID, COMMUNITY_A, validPub({ title: 'Owner A' }), deps);
  const memberPubA = await createPublication(MEMBER_ID, COMMUNITY_A, validPub({ title: 'Member A' }), deps);
  const ownerPubB = await createPublication(OWNER_ID, COMMUNITY_B, validPub({ title: 'Owner B' }), deps);
  const draft = await createPublication(OWNER_ID, COMMUNITY_A, validPub({ publish: 'draft', title: 'Draft A' }), deps);
  const scheduled = await createPublication(
    OWNER_ID,
    COMMUNITY_A,
    validPub({ publish: 'schedule', scheduled_at: new Date(Date.now() + 3600000).toISOString(), title: 'Later' }),
    deps
  );

  const first = await favoritePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  assert(first.favorited === true && first.favorited_by_me === true, 'favorite personal flag');
  assert(first.favorite_count === 1, 'favorite count after add');
  const again = await favoritePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  assert(again.favorite_count === 1, 'idempotent add does not increment');
  assert(
    db.state.favorites.filter(
      (item) => Number(item.community_publication_id) === Number(ownerPubA.id) && Number(item.user_id) === MEMBER_ID
    ).length === 1,
    'unique association'
  );

  const liked = await likePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  assert(liked.like_count === 1, 'like remains independent');
  const still = await favoritePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  assert(still.favorite_count === 1 && liked.like_count === 1, 'favorite does not change likes');
  const afterComment = db.state.publications.find((item) => Number(item.id) === Number(ownerPubA.id));
  afterComment.comment_count = 1;
  db.state.comments.push({
    id: 1,
    community_id: COMMUNITY_A,
    community_publication_id: ownerPubA.id,
    author_user_id: MEMBER_ID,
    body: 'Super soiree',
    status: 'visible',
  });
  assert(Number(afterComment.comment_count) === 1, 'comment stays independent');

  const other = await favoritePublication(MEMBER_B_ID, COMMUNITY_A, ownerPubA.id, deps);
  assert(other.favorite_count === 2, 'second user increments count');
  const concurrent = await Promise.all([
    favoritePublication(ADMIN_ID, COMMUNITY_A, ownerPubA.id, deps),
    favoritePublication(ADMIN_ID, COMMUNITY_A, ownerPubA.id, deps),
  ]);
  assert(
    concurrent.every((item) => item.favorite_count === 3 && item.favorited_by_me === true),
    'concurrent add stays unique'
  );
  assert(
    db.state.favorites.filter(
      (item) => Number(item.community_publication_id) === Number(ownerPubA.id) && Number(item.user_id) === ADMIN_ID
    ).length === 1,
    'one admin association'
  );

  const removed = await unfavoritePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  assert(removed.favorited === false && removed.favorite_count === 2, 'unfavorite decrements via count');
  const removedAgain = await unfavoritePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  assert(removedAgain.favorite_count === 2, 'idempotent unfavorite');
  await unlikePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  const pubAfterUnlike = db.state.publications.find((item) => Number(item.id) === Number(ownerPubA.id));
  assert(Number(pubAfterUnlike.like_count) === 0, 'unlike independent from favorites');
  assert(Number(pubAfterUnlike.comment_count) === 1, 'comments untouched by unfavorite');

  await expectReject(favoritePublication(OWNER_ID, COMMUNITY_A, ownerPubA.id, deps), 403);
  await expectReject(favoritePublication(MEMBER_ID, COMMUNITY_A, memberPubA.id, deps), 403);
  await expectReject(favoritePublication(STRANGER_ID, COMMUNITY_A, ownerPubA.id, deps), 404);
  await expectReject(favoritePublication(MEMBER_ID, COMMUNITY_B, ownerPubA.id, deps), 404);
  await expectReject(favoritePublication(MEMBER_ID, COMMUNITY_A, draft.id, deps), 404);
  await expectReject(favoritePublication(MEMBER_ID, COMMUNITY_A, scheduled.id, deps), 404);
  await expectReject(favoritePublication(MEMBER_ID, COMMUNITY_A, 99999, deps), 404);

  const ownerFav = await favoritePublication(OWNER_ID, COMMUNITY_A, memberPubA.id, deps);
  assert(ownerFav.favorited_by_me === true, 'owner can favorite another member publication as self');
  const adminFav = await favoritePublication(ADMIN_ID, COMMUNITY_A, memberPubA.id, deps);
  assert(adminFav.favorite_count === 2, 'admin favorites as self, not on behalf of author');

  await favoritePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps);
  await favoritePublication(MEMBER_ID, COMMUNITY_B, ownerPubB.id, deps);
  const sameTime = new Date('2026-10-08T12:00:00.000Z');
  const memberFavs = db.state.favorites.filter((item) => Number(item.user_id) === MEMBER_ID);
  memberFavs[0].favorited_at = sameTime;
  memberFavs[1].favorited_at = sameTime;
  const listedEqual = await listMyFavorites(MEMBER_ID, { limit: 20 }, deps);
  assert(listedEqual.items.length === 2, 'two favorites listed');
  assert(
    Number(listedEqual.items[0].id) === Number(memberFavs.sort((a, b) => Number(b.id) - Number(a.id))[0].community_publication_id),
    'equal favorited_at uses favorite id DESC'
  );

  const later = new Date('2026-10-09T12:00:00.000Z');
  const earlier = new Date('2026-10-07T12:00:00.000Z');
  const favA = db.state.favorites.find(
    (item) => Number(item.user_id) === MEMBER_ID && Number(item.community_publication_id) === Number(ownerPubA.id)
  );
  const favB = db.state.favorites.find(
    (item) => Number(item.user_id) === MEMBER_ID && Number(item.community_publication_id) === Number(ownerPubB.id)
  );
  favA.favorited_at = earlier;
  favB.favorited_at = later;
  const ordered = await listMyFavorites(MEMBER_ID, { limit: 20 }, deps);
  assert(Number(ordered.items[0].id) === Number(ownerPubB.id), 'most recent favorite first');
  assert(Number(ordered.items[1].id) === Number(ownerPubA.id), 'older favorite second');
  assert(ordered.items.every((item) => Number(item.author.user_id) !== MEMBER_ID), 'own publications excluded');

  const page1 = await listMyFavorites(MEMBER_ID, { limit: 1 }, deps);
  assert(page1.items.length === 1 && page1.next, 'pagination next');
  const page2 = await listMyFavorites(MEMBER_ID, { limit: 1, before_at: page1.next.before_at, before_id: page1.next.before_id }, deps);
  assert(page2.items.length === 1, 'second page');
  assert(Number(page1.items[0].id) !== Number(page2.items[0].id), 'pages have no duplicate');

  const feed = await listFeed(MEMBER_ID, COMMUNITY_A, {}, deps);
  const feedOwner = feed.items.find((item) => Number(item.id) === Number(ownerPubA.id));
  assert(feedOwner.favorited_by_me === true, 'feed personal flag');
  assert(feedOwner.favorite_count === 3, 'feed aggregate count');
  const feedOwn = feed.items.find((item) => Number(item.id) === Number(memberPubA.id));
  assert(feedOwn.favorited_by_me === false, 'author cannot be marked favorited_by_me');

  await expectReject(getPublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps), 404);

  const expired = await createPublication(OWNER_ID, COMMUNITY_A, validPub({ title: 'Expire soon' }), deps);
  await favoritePublication(MEMBER_ID, COMMUNITY_A, expired.id, deps);
  const expiredRow = db.state.publications.find((item) => Number(item.id) === Number(expired.id));
  expiredRow.status = 'expired';
  const afterExpire = await listMyFavorites(MEMBER_ID, {}, deps);
  assert(!afterExpire.items.some((item) => Number(item.id) === Number(expired.id)), 'expired excluded');
  await expectReject(favoritePublication(MEMBER_ID, COMMUNITY_A, expired.id, deps), 404);

  const toDelete = await createPublication(OWNER_ID, COMMUNITY_A, validPub({ title: 'To delete' }), deps);
  await favoritePublication(ADMIN_ID, COMMUNITY_A, toDelete.id, deps);
  await deletePublication(OWNER_ID, COMMUNITY_A, toDelete.id, deps);
  assert(
    !db.state.favorites.some((item) => Number(item.community_publication_id) === Number(toDelete.id)),
    'delete publication removes favorite associations'
  );

  const otherKeep = db.state.favorites.filter(
    (item) => Number(item.user_id) === MEMBER_B_ID && Number(item.community_publication_id) === Number(ownerPubA.id)
  );
  assert(otherKeep.length === 1, 'other member favorites remain before leave');

  await leaveCommunity(MEMBER_ID, COMMUNITY_A, deps);
  assert(
    !db.state.favorites.some(
      (item) => Number(item.user_id) === MEMBER_ID && Number(item.community_id) === COMMUNITY_A
    ),
    'leave deletes community A favorites'
  );
  assert(
    db.state.favorites.some(
      (item) => Number(item.user_id) === MEMBER_ID && Number(item.community_publication_id) === Number(ownerPubB.id)
    ),
    'community B favorites kept'
  );
  assert(
    db.state.publications.some((item) => Number(item.id) === Number(ownerPubA.id) && item.status === 'active'),
    'publication remains'
  );
  assert(
    db.state.favorites.some(
      (item) => Number(item.user_id) === MEMBER_B_ID && Number(item.community_publication_id) === Number(ownerPubA.id)
    ),
    'other users favorites kept'
  );
  const afterLeaveFeed = await listFeed(OWNER_ID, COMMUNITY_A, {}, deps);
  const counted = afterLeaveFeed.items.find((item) => Number(item.id) === Number(ownerPubA.id));
  const actualFavs = db.state.favorites.filter(
    (item) => Number(item.community_publication_id) === Number(ownerPubA.id)
  ).length;
  assert(counted.favorite_count === actualFavs, 'count matches remaining associations after leave');
  await expectReject(favoritePublication(MEMBER_ID, COMMUNITY_A, ownerPubA.id, deps), 404);
  const mineAfterLeave = await listMyFavorites(MEMBER_ID, {}, deps);
  assert(
    mineAfterLeave.items.length === 1 && Number(mineAfterLeave.items[0].id) === Number(ownerPubB.id),
    'list only remaining community'
  );

  await favoritePublication(MEMBER_B_ID, COMMUNITY_A, memberPubA.id, deps);
  await removeMember(OWNER_ID, COMMUNITY_A, MEMBER_B_ID, deps);
  assert(
    !db.state.favorites.some((item) => Number(item.user_id) === MEMBER_B_ID && Number(item.community_id) === COMMUNITY_A),
    'remove member deletes favorites'
  );
  assert(
    db.state.publications.some((item) => Number(item.id) === Number(memberPubA.id)),
    'removed member publication remains'
  );

  const ownerDetail = await getPublication(OWNER_ID, COMMUNITY_A, ownerPubA.id, deps);
  const remainingOwnerPubFavs = db.state.favorites.filter(
    (item) => Number(item.community_publication_id) === Number(ownerPubA.id)
  ).length;
  assert(ownerDetail.favorited_by_me === false, 'author detail never favorited_by_me');
  assert(ownerDetail.favorite_count === remainingOwnerPubFavs, 'author still sees aggregate count');

  console.log('Community publication favorites checks succeeded.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
