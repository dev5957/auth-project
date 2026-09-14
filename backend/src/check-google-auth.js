const { verifyGoogleIdToken, isGoogleAuthConfigured } = require('./services/googleAuthService');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function expectStatus(fn, statusCode, message) {
  try {
    await fn();
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    if (message) {
      assert(err.message === message, `unexpected message: ${err.message}`);
    }
  }
}

function captureLogs(fn) {
  const logs = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args) => {
    logs.push(args.map(String).join(' '));
  };
  console.error = (...args) => {
    logs.push(args.map(String).join(' '));
  };
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      console.log = originalLog;
      console.error = originalError;
    })
    .then((result) => ({ result, logs: logs.join('\n') }));
}

function mockTicket(payload) {
  return {
    getPayload() {
      return payload;
    },
  };
}

async function main() {
  const previous = {
    GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID,
  };

  const clientId = 'test-google-client-id.apps.googleusercontent.com';
  const idToken = 'google-id-token-must-not-be-logged';

  delete process.env.GOOGLE_CLIENT_ID;
  assert(isGoogleAuthConfigured() === false, 'Google should be off without env');
  await expectStatus(() => verifyGoogleIdToken(idToken), 503, 'Google authentication is not configured');
  console.log('OK sans GOOGLE_CLIENT_ID -> 503');

  process.env.GOOGLE_CLIENT_ID = clientId;
  assert(isGoogleAuthConfigured() === true, 'Google should be on with env');
  await expectStatus(() => verifyGoogleIdToken(''), 400, 'id_token is required');
  await expectStatus(() => verifyGoogleIdToken('   '), 400, 'id_token is required');
  console.log('OK id_token absent -> 400');

  const validPayload = {
    iss: 'https://accounts.google.com',
    aud: clientId,
    exp: Math.floor(Date.now() / 1000) + 3600,
    sub: 'google-user-123',
    email: 'user@example.com',
    given_name: 'Ada',
    family_name: 'Lovelace',
  };

  const calls = [];
  const mockClient = {
    verifyIdToken: async (options) => {
      calls.push(options);
      return mockTicket(validPayload);
    },
  };

  const captured = await captureLogs(async () => {
    const identity = await verifyGoogleIdToken(idToken, { client: mockClient });
    assert(identity.provider_user_id === 'google-user-123', 'provider_user_id');
    assert(identity.email === 'user@example.com', 'email');
    assert(identity.first_name === 'Ada', 'first_name');
    assert(identity.last_name === 'Lovelace', 'last_name');
    assert(Object.keys(identity).sort().join(',') === 'email,first_name,last_name,provider_user_id', 'extra fields');
    assert(calls.length === 1, 'verifyIdToken should be called once');
    assert(calls[0].idToken === idToken, 'idToken forwarded');
    assert(calls[0].audience === clientId, 'audience is GOOGLE_CLIENT_ID');
    return identity;
  });
  assert(!captured.logs.includes(idToken), 'logs leaked id_token');
  assert(!JSON.stringify(captured.result).includes(idToken), 'result leaked id_token');
  console.log('OK token Google valide -> identite mappee');

  await expectStatus(
    () =>
      verifyGoogleIdToken(idToken, {
        client: {
          verifyIdToken: async () => mockTicket({ ...validPayload, iss: 'https://evil.example' }),
        },
      }),
    401,
    'Unauthorized'
  );
  console.log('OK mauvais emetteur -> 401');

  await expectStatus(
    () =>
      verifyGoogleIdToken(idToken, {
        client: {
          verifyIdToken: async () => mockTicket({ ...validPayload, aud: 'other-client-id' }),
        },
      }),
    401,
    'Unauthorized'
  );
  console.log('OK mauvaise audience -> 401');

  await expectStatus(
    () =>
      verifyGoogleIdToken(idToken, {
        client: {
          verifyIdToken: async () =>
            mockTicket({ ...validPayload, exp: Math.floor(Date.now() / 1000) - 3600 }),
        },
      }),
    401,
    'Unauthorized'
  );
  console.log('OK token expire -> 401');

  await expectStatus(
    () =>
      verifyGoogleIdToken(idToken, {
        client: {
          verifyIdToken: async () => {
            throw new Error(`Invalid token signature: ${idToken}`);
          },
        },
      }),
    401,
    'Unauthorized'
  );
  console.log('OK signature Google refusee -> 401');

  const failedLogs = await captureLogs(async () => {
    await expectStatus(
      () =>
        verifyGoogleIdToken(idToken, {
          client: {
            verifyIdToken: async () => {
              throw new Error(`Invalid token signature: ${idToken}`);
            },
          },
        }),
      401,
      'Unauthorized'
    );
  });
  assert(!failedLogs.logs.includes(idToken), 'error logs leaked id_token');
  console.log('OK logs sans id_token');

  Object.entries(previous).forEach(([key, value]) => {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  });

  console.log('Google id token verification checks succeeded.');
}

main().catch((err) => {
  console.error('Google id token verification checks failed:', err.message);
  process.exitCode = 1;
});
