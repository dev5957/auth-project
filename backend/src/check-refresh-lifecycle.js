const {
  MAX_ACTIVE_REFRESH_TOKENS,
  storeLoginRefreshToken,
  purgeStaleRefreshTokens,
} = require('./services/refreshSessionService');
const { generateRefreshToken } = require('./services/tokenService');
const { refreshAuthTokens } = require('./services/refreshTokenService');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function normalizeSql(sql) {
  return sql.replace(/\s+/g, ' ').trim().toUpperCase();
}

function createMemoryDb({ users = [], tokens = [] } = {}) {
  const state = {
    users: users.map((user) => ({ ...user })),
    tokens: tokens.map((token) => ({ ...token })),
  };
  let nextId = state.tokens.reduce((max, token) => Math.max(max, token.id), 0) + 1;

  const client = {
    async query(sql, params = []) {
      const normalized = normalizeSql(sql);

      if (normalized === 'BEGIN' || normalized === 'COMMIT' || normalized === 'ROLLBACK') {
        return { rows: [], rowCount: 0 };
      }

      if (normalized.includes('FROM REFRESH_TOKENS') && normalized.includes('TOKEN_HASH')) {
        const row = state.tokens.find((token) => token.token_hash === params[0]);
        return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
      }

      if (
        normalized.includes('FROM REFRESH_TOKENS') &&
        normalized.includes('USER_ID') &&
        normalized.includes('ORDER BY CREATED_AT')
      ) {
        const now = Date.now();
        const rows = state.tokens
          .filter(
            (token) =>
              token.user_id === params[0] &&
              token.revoked_at == null &&
              new Date(token.expires_at).getTime() > now
          )
          .sort((a, b) => {
            const created = new Date(a.created_at) - new Date(b.created_at);
            return created !== 0 ? created : a.id - b.id;
          })
          .map((token) => ({ id: token.id }));
        return { rows, rowCount: rows.length };
      }

      if (normalized.includes('FROM USERS') && normalized.includes('WHERE ID')) {
        const user = state.users.find((item) => item.id === params[0]);
        return { rows: user ? [{ ...user }] : [], rowCount: user ? 1 : 0 };
      }

      if (normalized.startsWith('INSERT INTO REFRESH_TOKENS')) {
        state.tokens.push({
          id: nextId,
          user_id: params[0],
          token_hash: params[1],
          expires_at: params[2],
          created_at: new Date(),
          revoked_at: null,
        });
        nextId += 1;
        return { rows: [], rowCount: 1 };
      }

      if (normalized.includes('UPDATE REFRESH_TOKENS') && normalized.includes('ANY(')) {
        const ids = params[0];
        let count = 0;
        for (const token of state.tokens) {
          if (ids.includes(token.id) && token.revoked_at == null) {
            token.revoked_at = new Date();
            count += 1;
          }
        }
        return { rows: [], rowCount: count };
      }

      if (
        normalized.includes('UPDATE REFRESH_TOKENS') &&
        normalized.includes('USER_ID') &&
        normalized.includes('REVOKED_AT IS NULL')
      ) {
        let count = 0;
        for (const token of state.tokens) {
          if (token.user_id === params[0] && token.revoked_at == null) {
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

      if (normalized.startsWith('DELETE FROM REFRESH_TOKENS')) {
        const days = Number(params[0]);
        const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
        const remaining = [];
        const deleted = [];
        for (const token of state.tokens) {
          const expiredLongAgo = new Date(token.expires_at).getTime() < cutoff;
          const revokedLongAgo =
            token.revoked_at != null && new Date(token.revoked_at).getTime() < cutoff;
          if (expiredLongAgo || revokedLongAgo) {
            deleted.push(token);
          } else {
            remaining.push(token);
          }
        }
        state.tokens = remaining;
        return { rows: deleted.map((token) => ({ id: token.id })), rowCount: deleted.length };
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
    query: (...args) => client.query(...args),
  };
}

function activeTokens(state, userId) {
  const now = Date.now();
  return state.tokens.filter(
    (token) =>
      token.user_id === userId &&
      token.revoked_at == null &&
      new Date(token.expires_at).getTime() > now
  );
}

async function main() {
  process.env.JWT_SECRET = 'test-jwt-secret-not-for-production';
  process.env.DATABASE_URL = 'mock://local-refresh-lifecycle';

  const user = {
    id: 7,
    login: 'session-test',
    email: 'session-test@example.com',
    auth_provider: 'local',
  };
  const future = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000);
  const db = createMemoryDb({ users: [user], tokens: [] });

  const plains = [];
  for (let i = 0; i < 6; i += 1) {
    const generated = generateRefreshToken();
    plains.push(generated.token);
    await storeLoginRefreshToken(user.id, generated.token_hash, future, db);
    if (i === 0) {
      assert(activeTokens(db.state, user.id).length === 1, 'A: login should create one active token');
      console.log('A OK login -> un refresh token actif');
    }
  }

  const active = activeTokens(db.state, user.id);
  assert(active.length === MAX_ACTIVE_REFRESH_TOKENS, `B: expected ${MAX_ACTIVE_REFRESH_TOKENS} active`);
  assert(db.state.tokens.length === 6, 'B: oldest session should be revoked, not deleted');
  assert(db.state.tokens.filter((token) => token.revoked_at).length === 1, 'B: one oldest revoked');
  console.log('B OK 6 sessions -> 5 actives, plus ancienne révoquée');

  const rotated = await refreshAuthTokens({ refresh_token: plains[5] }, db);
  assert(rotated.access_token && rotated.refresh_token, 'D: active refresh should rotate');
  assert(rotated.refresh_token !== plains[5], 'D: refresh token should rotate');
  console.log('D OK refresh actif -> rotation');

  try {
    await refreshAuthTokens({ refresh_token: plains[0] }, db);
    throw new Error('C: expected revoked token to fail');
  } catch (err) {
    assert(err.statusCode === 401, `C: expected 401, got ${err.statusCode}`);
    assert(err.message === 'Invalid refresh token', 'C: unexpected message');
  }
  console.log('C OK refresh révoqué -> 401');

  const beforePurgeActive = activeTokens(db.state, user.id).length;
  const deleted = await purgeStaleRefreshTokens({ confirm: true, olderThanDays: 30, executor: db });
  assert(deleted === 0, `E: purge removed ${deleted} row(s) including possibly active tokens`);
  assert(activeTokens(db.state, user.id).length === beforePurgeActive, 'E: active count changed');
  console.log('E OK purge -> tokens actifs conservés');

  const staleDb = createMemoryDb({
    users: [user],
    tokens: [
      {
        id: 100,
        user_id: user.id,
        token_hash: 'stale-revoked',
        expires_at: future,
        created_at: new Date(Date.now() - 40 * 24 * 60 * 60 * 1000),
        revoked_at: new Date(Date.now() - 40 * 24 * 60 * 60 * 1000),
      },
      {
        id: 101,
        user_id: user.id,
        token_hash: 'still-active',
        expires_at: future,
        created_at: new Date(),
        revoked_at: null,
      },
    ],
  });
  const staleDeleted = await purgeStaleRefreshTokens({
    confirm: true,
    olderThanDays: 30,
    executor: staleDb,
  });
  assert(staleDeleted === 1, 'E: expected one stale revoked row deleted');
  assert(staleDb.state.tokens.length === 1, 'E: active row should remain');
  assert(staleDb.state.tokens[0].token_hash === 'still-active', 'E: wrong row kept');

  try {
    await purgeStaleRefreshTokens({ executor: db });
    throw new Error('E: purge without confirm should fail');
  } catch (err) {
    assert(/confirm/.test(err.message), 'E: missing confirm should refuse');
  }
  console.log('E OK purge exige --confirm et ignore les tokens actifs');

  console.log('Refresh lifecycle checks succeeded.');
}

main().catch((err) => {
  console.error('Refresh lifecycle checks failed:', err.message);
  process.exitCode = 1;
});
