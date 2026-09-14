const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const {
  APPLE_ISSUER,
  verifyAppleIdentityToken,
  isAppleAuthConfigured,
} = require('./services/appleAuthService');

const CLIENT_ID = 'com.example.authproject.service';
const KID = 'apple-test-kid';

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

function createKeyPair() {
  return crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
}

function signIdentityToken(privateKey, claims, options = {}) {
  return jwt.sign(claims, privateKey, {
    algorithm: 'RS256',
    issuer: options.issuer || APPLE_ISSUER,
    audience: options.audience || CLIENT_ID,
    expiresIn: options.expiresIn || '1h',
    keyid: options.kid || KID,
  });
}

function decodeJwtSegment(segment) {
  const padded = segment + '='.repeat((4 - (segment.length % 4)) % 4);
  return JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
}

function decodeJwtHeader(token) {
  return decodeJwtSegment(token.split('.')[0]);
}

function decodeJwtPayload(token) {
  return decodeJwtSegment(token.split('.')[1]);
}

function unsignedNoneToken(claims) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(
    JSON.stringify({ alg: 'none', typ: 'JWT', kid: KID })
  ).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({
      iss: APPLE_ISSUER,
      aud: CLIENT_ID,
      exp: now + 3600,
      iat: now,
      ...claims,
    })
  ).toString('base64url');
  return `${header}.${payload}.`;
}

async function main() {
  const previous = {
    APPLE_CLIENT_ID: process.env.APPLE_CLIENT_ID,
  };
  const { publicKey, privateKey } = createKeyPair();
  const getSigningKey = async () => publicKey;

  delete process.env.APPLE_CLIENT_ID;
  assert(isAppleAuthConfigured() === false, 'Apple should be off without env');
  await expectStatus(
    () => verifyAppleIdentityToken('header.payload.signature'),
    503,
    'Apple authentication is not configured'
  );
  console.log('OK sans APPLE_CLIENT_ID -> 503');

  process.env.APPLE_CLIENT_ID = CLIENT_ID;
  assert(isAppleAuthConfigured() === true, 'Apple should be on with env');
  await expectStatus(() => verifyAppleIdentityToken(''), 400, 'identity_token is required');
  await expectStatus(() => verifyAppleIdentityToken('   '), 400, 'identity_token is required');
  console.log('OK identity_token absent -> 400');

  const validToken = signIdentityToken(privateKey, {
    sub: 'apple-user-001',
    email: 'user@example.com',
    given_name: 'Ada',
    family_name: 'Lovelace',
  });

  const captured = await captureLogs(async () => {
    const identity = await verifyAppleIdentityToken(validToken, { getSigningKey });
    assert(identity.provider_user_id === 'apple-user-001', 'provider_user_id');
    assert(identity.email === 'user@example.com', 'email');
    assert(identity.first_name === 'Ada', 'first_name');
    assert(identity.last_name === 'Lovelace', 'last_name');
    return identity;
  });
  assert(!captured.logs.includes(validToken), 'logs leaked identity_token');
  assert(!JSON.stringify(captured.result).includes(validToken), 'result leaked identity_token');
  console.log('OK identity_token Apple valide -> identite mappee');

  const reconnectToken = signIdentityToken(privateKey, {
    sub: 'apple-user-reconnect',
  });
  const reconnect = await verifyAppleIdentityToken(reconnectToken, { getSigningKey });
  assert(reconnect.provider_user_id === 'apple-user-reconnect', 'reconnect sub');
  assert(reconnect.email === null, 'reconnect email may be absent');
  assert(reconnect.first_name === null, 'reconnect first_name may be absent');
  assert(reconnect.last_name === null, 'reconnect last_name may be absent');
  console.log('OK reconnexion sans email ni noms -> identite minimale');

  const wrongAud = signIdentityToken(
    privateKey,
    { sub: 'apple-user-001' },
    { audience: 'com.other.app' }
  );
  await expectStatus(
    () => verifyAppleIdentityToken(wrongAud, { getSigningKey }),
    401,
    'Unauthorized'
  );
  console.log('OK mauvaise audience -> 401');

  const wrongIss = signIdentityToken(
    privateKey,
    { sub: 'apple-user-001' },
    { issuer: 'https://evil.example' }
  );
  await expectStatus(
    () => verifyAppleIdentityToken(wrongIss, { getSigningKey }),
    401,
    'Unauthorized'
  );
  console.log('OK mauvais emetteur -> 401');

  const expired = jwt.sign(
    { sub: 'apple-user-001', exp: Math.floor(Date.now() / 1000) - 400 },
    privateKey,
    { algorithm: 'RS256', issuer: APPLE_ISSUER, audience: CLIENT_ID, keyid: KID }
  );
  await expectStatus(
    () => verifyAppleIdentityToken(expired, { getSigningKey }),
    401,
    'Unauthorized'
  );
  console.log('OK token expire -> 401');

  const hs256 = jwt.sign(
    { sub: 'apple-user-001', email: 'user@example.com' },
    'hmac-secret-must-not-be-accepted-as-apple-jwks',
    {
      algorithm: 'HS256',
      issuer: APPLE_ISSUER,
      audience: CLIENT_ID,
      expiresIn: '1h',
      keyid: KID,
    }
  );
  assert(decodeJwtHeader(hs256).alg === 'HS256', 'HS256 token header alg');
  await expectStatus(
    () => verifyAppleIdentityToken(hs256, { getSigningKey }),
    401,
    'Unauthorized'
  );
  console.log('OK alg HS256 -> 401');

  const noneToken = unsignedNoneToken({
    sub: 'apple-user-001',
    email: 'user@example.com',
  });
  assert(decodeJwtHeader(noneToken).alg === 'none', 'none token header alg');
  await expectStatus(
    () => verifyAppleIdentityToken(noneToken, { getSigningKey }),
    401,
    'Unauthorized'
  );
  console.log('OK alg none -> 401');

  const missingSub = signIdentityToken(privateKey, {
    email: 'user@example.com',
  });
  assert(decodeJwtHeader(missingSub).alg === 'RS256', 'missing sub token alg');
  assert(decodeJwtPayload(missingSub).sub === undefined, 'sub claim must be absent');
  await expectStatus(
    () => verifyAppleIdentityToken(missingSub, { getSigningKey }),
    401,
    'Unauthorized'
  );
  console.log('OK RS256 sans sub -> 401');

  const failedLogs = await captureLogs(async () => {
    await expectStatus(
      () => verifyAppleIdentityToken(validToken, {
        getSigningKey: async () => {
          throw new Error(`Invalid Apple signature: ${validToken}`);
        },
      }),
      401,
      'Unauthorized'
    );
  });
  assert(!failedLogs.logs.includes(validToken), 'error logs leaked identity_token');
  console.log('OK signature Apple refusee -> 401, logs sans identity_token');

  Object.entries(previous).forEach(([key, value]) => {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  });

  console.log('Apple identity token verification checks succeeded.');
}

main().catch((err) => {
  console.error('Apple identity token verification checks failed:', err.message);
  process.exitCode = 1;
});
