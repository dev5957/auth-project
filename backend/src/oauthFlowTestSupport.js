'use strict';

const http = require('http');

function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function createOauthFlowMemoryDb() {
  const stats = {
    usersCreated: 0,
    refreshCreated: 0,
    refreshRevoked: 0,
  };
  const state = {
    users: [],
    tokens: [],
    verifications: [],
  };
  let nextUserId = 1;
  let nextTokenId = 1;
  let nextVerificationId = 1;

  function reset(seed = {}) {
    state.users = (seed.users || []).map((user) => ({ ...user }));
    state.tokens = (seed.tokens || []).map((token) => ({ ...token }));
    state.verifications = (seed.verifications || []).map((row, index) => ({
      id: row.id || index + 1,
      verified_at: row.verified_at ?? null,
      attempts: row.attempts ?? 0,
      ...row,
    }));
    nextUserId = state.users.reduce((max, user) => Math.max(max, user.id || 0), 0) + 1;
    nextTokenId = state.tokens.reduce((max, token) => Math.max(max, token.id || 0), 0) + 1;
    nextVerificationId =
      state.verifications.reduce((max, row) => Math.max(max, row.id || 0), 0) + 1;
  }

  function revokeToken(token, reason) {
    if (!token || token.revoked_at) {
      return 0;
    }
    token.revoked_at = new Date();
    token.revoked_reason = reason;
    stats.refreshRevoked += 1;
    return 1;
  }

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('DELETE FROM PHONE_VERIFICATIONS')) {
      throw new Error('phone_verifications must not be deleted');
    }

    if (key.includes('FROM PHONE_VERIFICATIONS') && key.includes('VERIFICATION_TOKEN')) {
      const row = state.verifications.find((item) => item.verification_token === params[0]);
      return {
        rows: row
          ? [
              {
                id: row.id,
                code_hash: row.code_hash,
                expires_at: row.expires_at,
                attempts: row.attempts,
                verified_at: row.verified_at,
                registration_data: row.registration_data ? { ...row.registration_data } : null,
              },
            ]
          : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.startsWith('INSERT INTO PHONE_VERIFICATIONS')) {
      state.verifications.push({
        id: nextVerificationId,
        verification_token: params[0],
        phone_number: params[1],
        code_hash: params[2],
        expires_at: params[3],
        attempts: 0,
        verified_at: null,
        registration_data: params[4],
      });
      nextVerificationId += 1;
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('UPDATE PHONE_VERIFICATIONS') && key.includes('REGISTRATION_DATA')) {
      const row = state.verifications.find((item) => item.id === params[4]);
      if (!row || row.verified_at) {
        return { rows: [], rowCount: 0 };
      }
      row.phone_number = params[0];
      row.code_hash = params[1];
      row.expires_at = params[2];
      row.attempts = 0;
      row.registration_data = params[3];
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('UPDATE PHONE_VERIFICATIONS') && key.includes('ATTEMPTS')) {
      const row = state.verifications.find((item) => item.id === params[1]);
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.attempts = params[0];
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('UPDATE PHONE_VERIFICATIONS') && key.includes('VERIFIED_AT')) {
      const row = state.verifications.find((item) => item.id === params[0]);
      if (!row || row.verified_at) {
        return { rows: [], rowCount: 0 };
      }
      row.verified_at = new Date();
      return { rows: [], rowCount: 1 };
    }

    if (key.includes('EMAIL_PROVIDER') && key.includes('LOGIN_TAKEN')) {
      const emailUser = state.users.find((user) => user.email === params[0]);
      return {
        rows: [
          {
            email_provider: emailUser ? emailUser.auth_provider : null,
            login_taken: state.users.some((user) => user.login === params[1]),
            phone_taken: state.users.some((user) => user.phone_number === params[2]),
            provider_taken: state.users.some(
              (user) => user.auth_provider === params[3] && user.provider_user_id === params[4]
            ),
          },
        ],
        rowCount: 1,
      };
    }

    const providerLookup = key.match(/AUTH_PROVIDER = '(GOOGLE|APPLE)'/);
    if (key.includes('FROM USERS') && key.includes('PROVIDER_USER_ID') && providerLookup) {
      const authProvider = providerLookup[1].toLowerCase();
      const row = state.users.find(
        (user) => user.auth_provider === authProvider && user.provider_user_id === params[0]
      );
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('EXISTS') && key.includes('FROM USERS') && key.includes('PHONE_NUMBER')) {
      const taken = state.users.some((user) => user.phone_number === params[0]);
      return { rows: [{ phone_taken: taken }], rowCount: 1 };
    }

    if (key.includes('FROM USERS') && key.includes('WHERE EMAIL')) {
      const row = state.users.find((user) => user.email === params[0]);
      return {
        rows: row ? [{ auth_provider: row.auth_provider }] : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes('FROM USERS') && key.includes('WHERE ID')) {
      const row = state.users.find((user) => user.id === params[0]);
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }

    if (key.startsWith('INSERT INTO USERS')) {
      const user = {
        id: nextUserId,
        email: params[0],
        birth_date: params[1],
        phone_number: params[2],
        phone_verified: true,
        login: params[3],
        password_hash: null,
        auth_provider: params[4],
        provider_user_id: params[5],
        first_name: params[6],
        last_name: params[7],
      };
      state.users.push(user);
      nextUserId += 1;
      stats.usersCreated += 1;
      return {
        rows: [
          {
            id: user.id,
            login: user.login,
            email: user.email,
            auth_provider: user.auth_provider,
            provider_user_id: user.provider_user_id,
            phone_verified: user.phone_verified,
            password_hash: user.password_hash,
          },
        ],
        rowCount: 1,
      };
    }

    if (key.includes('FROM REFRESH_TOKENS') && key.includes('TOKEN_HASH')) {
      const row = state.tokens.find((token) => token.token_hash === params[0]);
      return {
        rows: row
          ? [{ id: row.id, user_id: row.user_id, expires_at: row.expires_at, revoked_at: row.revoked_at }]
          : [],
        rowCount: row ? 1 : 0,
      };
    }

    if (key.includes('FROM REFRESH_TOKENS') && key.includes('USER_ID')) {
      const rows = state.tokens.filter(
        (token) =>
          token.user_id === params[0] &&
          token.revoked_at == null &&
          (!token.expires_at || new Date(token.expires_at).getTime() > Date.now())
      );
      return { rows: rows.map((token) => ({ id: token.id })), rowCount: rows.length };
    }

    if (key.startsWith('INSERT INTO REFRESH_TOKENS')) {
      state.tokens.push({
        id: nextTokenId,
        user_id: params[0],
        token_hash: params[1],
        expires_at: params[2],
        revoked_at: null,
      });
      nextTokenId += 1;
      stats.refreshCreated += 1;
      return { rows: [], rowCount: 1 };
    }

    if (key.startsWith('UPDATE REFRESH_TOKENS') && key.includes('USER_ID')) {
      let count = 0;
      for (const token of state.tokens) {
        if (token.user_id === params[0] && token.revoked_at == null) {
          count += revokeToken(token, 'user');
        }
      }
      return { rows: [], rowCount: count };
    }

    if (key.startsWith('UPDATE REFRESH_TOKENS') && key.includes('ANY(')) {
      const ids = params[0] || [];
      let count = 0;
      for (const token of state.tokens) {
        if (ids.includes(token.id) && token.revoked_at == null) {
          count += revokeToken(token, 'overflow');
        }
      }
      return { rows: [], rowCount: count };
    }

    if (key.startsWith('UPDATE REFRESH_TOKENS')) {
      const row = state.tokens.find((token) => token.id === params[0]);
      const count = revokeToken(row, 'id');
      return { rows: [], rowCount: count };
    }

    throw new Error(`unexpected query: ${sql}`);
  }

  reset();

  return {
    state,
    stats,
    reset,
    query,
    async connect() {
      return {
        query,
        release() {},
      };
    },
  };
}

function installMemoryDb(pool) {
  const dbPath = require.resolve('./db');
  require.cache[dbPath] = {
    id: dbPath,
    filename: dbPath,
    loaded: true,
    exports: pool,
  };
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function createHttpClient({ port, getClientIp }) {
  return function httpRequest({ method, urlPath, headers = {}, body }) {
    return new Promise((resolve, reject) => {
      const data = body === undefined ? null : JSON.stringify(body);
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port,
          path: urlPath,
          method,
          headers: {
            ...(data
              ? {
                  'Content-Type': 'application/json',
                  'Content-Length': Buffer.byteLength(data),
                }
              : {}),
            'X-Forwarded-For': getClientIp(),
            ...headers,
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
      req.setTimeout(10000, () => {
        req.destroy();
        reject(new Error('request timeout'));
      });
      req.on('error', reject);
      if (data) {
        req.write(data);
      }
      req.end();
    });
  };
}

async function withOtpCapture(fn) {
  const codes = [];
  const originalLog = console.log;
  console.log = (...args) => {
    const text = args.map(String).join(' ');
    const match = text.match(/\[DEV\] SMS verification code:\s*(\d{6})/);
    if (match) {
      codes.push(match[1]);
      return;
    }
    originalLog.apply(console, args);
  };
  try {
    const result = await fn();
    return { result, code: codes[0] || null };
  } finally {
    console.log = originalLog;
  }
}

module.exports = {
  createOauthFlowMemoryDb,
  installMemoryDb,
  assert,
  createHttpClient,
  withOtpCapture,
};
