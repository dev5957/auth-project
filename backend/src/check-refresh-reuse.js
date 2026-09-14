const crypto = require('crypto');
const { generateRefreshToken, hashRefreshToken } = require('./services/tokenService');
const { refreshAuthTokens } = require('./services/refreshTokenService');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function normalizeSql(sql) {
  return sql.replace(/\s+/g, ' ').trim().toUpperCase();
}

function createMemoryDb({ users, tokens }) {
  const state = {
    users: users.map((user) => ({ ...user })),
    tokens: tokens.map((token) => ({ ...token })),
    insertCount: 0,
    queries: [],
  };

  let nextId = state.tokens.reduce((max, token) => Math.max(max, token.id), 0) + 1;

  const client = {
    async query(sql, params = []) {
      const normalized = normalizeSql(sql);
      state.queries.push({ sql: normalized, params });

      if (normalized === 'BEGIN' || normalized === 'COMMIT' || normalized === 'ROLLBACK') {
        return { rows: [], rowCount: 0 };
      }

      if (normalized.includes('FROM REFRESH_TOKENS') && normalized.includes('TOKEN_HASH')) {
        const hash = params[0];
        const row = state.tokens.find((token) => token.token_hash === hash);
        return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
      }

      if (normalized.includes('FROM USERS') && normalized.includes('WHERE ID')) {
        const user = state.users.find((item) => item.id === params[0]);
        return { rows: user ? [{ ...user }] : [], rowCount: user ? 1 : 0 };
      }

      if (normalized.startsWith('INSERT INTO REFRESH_TOKENS')) {
        state.insertCount += 1;
        state.tokens.push({
          id: nextId,
          user_id: params[0],
          token_hash: params[1],
          expires_at: params[2],
          revoked_at: null,
        });
        nextId += 1;
        return { rows: [], rowCount: 1 };
      }

      if (
        normalized.includes('UPDATE REFRESH_TOKENS') &&
        normalized.includes('USER_ID') &&
        normalized.includes('REVOKED_AT IS NULL')
      ) {
        const userId = params[0];
        let count = 0;
        for (const token of state.tokens) {
          if (token.user_id === userId && token.revoked_at == null) {
            token.revoked_at = new Date();
            count += 1;
          }
        }
        return { rows: [], rowCount: count };
      }

      if (normalized.includes('UPDATE REFRESH_TOKENS') && normalized.includes('WHERE ID')) {
        const token = state.tokens.find((item) => item.id === params[0]);
        if (token) {
          token.revoked_at = new Date();
        }
        return { rows: [], rowCount: token ? 1 : 0 };
      }

      throw new Error(`Unsupported query in memory db: ${normalized}`);
    },
    release() {},
  };

  return {
    state,
    async connect() {
      return client;
    },
  };
}

function activeTokens(state, userId) {
  return state.tokens.filter((token) => token.user_id === userId && token.revoked_at == null);
}

async function expectInvalidRefresh(body, db) {
  try {
    await refreshAuthTokens(body, db);
    throw new Error('expected Invalid refresh token');
  } catch (err) {
    assert(err.statusCode === 401, `expected 401, got ${err.statusCode}`);
    assert(err.message === 'Invalid refresh token', `unexpected message: ${err.message}`);
  }
}

async function runMemoryCases() {
  process.env.JWT_SECRET = 'test-jwt-secret-not-for-production';
  process.env.JWT_ISSUER = 'auth-project';
  process.env.JWT_AUDIENCE = 'auth-project-app';
  process.env.DATABASE_URL = 'mock://local-refresh-tests';

  const user = {
    id: 42,
    login: 'reuse-test',
    email: 'reuse-test@example.com',
    auth_provider: 'local',
  };

  const first = generateRefreshToken();
  const extra = generateRefreshToken();
  const future = new Date(Date.now() + 60 * 60 * 1000);
  const past = new Date(Date.now() - 60 * 1000);

  const db = createMemoryDb({
    users: [user],
    tokens: [
      {
        id: 1,
        user_id: user.id,
        token_hash: first.token_hash,
        expires_at: future,
        revoked_at: null,
      },
      {
        id: 2,
        user_id: user.id,
        token_hash: extra.token_hash,
        expires_at: future,
        revoked_at: null,
      },
    ],
  });

  const rotated = await refreshAuthTokens({ refresh_token: first.token }, db);
  assert(rotated.access_token && rotated.refresh_token, 'A: missing rotated tokens');
  assert(rotated.refresh_token !== first.token, 'A: refresh token was not rotated');
  assert(db.state.insertCount === 1, 'A: expected one insert');
  const afterRotation = db.state.tokens.find((token) => token.id === 1);
  assert(afterRotation.revoked_at, 'A: original token should be revoked');
  assert(activeTokens(db.state, user.id).length === 2, 'A: extra active + new token');
  console.log('A OK refresh valide -> rotation');

  const insertsAfterRotation = db.state.insertCount;
  await expectInvalidRefresh({ refresh_token: first.token }, db);
  console.log('B OK ancien refresh après rotation -> 401');

  const leftoverActive = activeTokens(db.state, user.id);
  assert(leftoverActive.length === 0, 'C: expected all active tokens revoked');
  console.log('C OK réutilisation -> tous les refresh actifs révoqués');

  assert(db.state.insertCount === insertsAfterRotation, 'D: reuse must not insert a token');
  console.log('D OK aucun nouveau refresh token à la réutilisation');

  const insertsBeforeUnknown = db.state.insertCount;
  await expectInvalidRefresh({ refresh_token: crypto.randomBytes(32).toString('hex') }, db);
  assert(db.state.insertCount === insertsBeforeUnknown, 'E: unknown token inserted a row');
  console.log('E OK token inconnu -> 401');

  const expiredPlain = generateRefreshToken();
  const otherActive = generateRefreshToken();
  const expiredDb = createMemoryDb({
    users: [user],
    tokens: [
      {
        id: 10,
        user_id: user.id,
        token_hash: expiredPlain.token_hash,
        expires_at: past,
        revoked_at: null,
      },
      {
        id: 11,
        user_id: user.id,
        token_hash: otherActive.token_hash,
        expires_at: future,
        revoked_at: null,
      },
    ],
  });
  await expectInvalidRefresh({ refresh_token: expiredPlain.token }, expiredDb);
  assert(expiredDb.state.insertCount === 0, 'F: expired token inserted a row');
  const expiredRow = expiredDb.state.tokens.find((token) => token.id === 10);
  const otherRow = expiredDb.state.tokens.find((token) => token.id === 11);
  assert(expiredRow.revoked_at == null, 'F: expired token should not be mass-revoked');
  assert(otherRow.revoked_at == null, 'F: other active token should stay active');
  console.log('F OK token expiré -> 401 sans révoquer les autres');

  const hashedUnknown = hashRefreshToken('unused');
  assert(typeof hashedUnknown === 'string', 'hash helper available');
}

async function main() {
  await runMemoryCases();
  console.log('Refresh reuse checks succeeded.');
}

main().catch((err) => {
  console.error('Refresh reuse checks failed:', err.message);
  process.exitCode = 1;
});
