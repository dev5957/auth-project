/**
 * Diagnostic local — ne change pas le comportement de production.
 *
 * Rejoue createGoogleOAuthClient() puis OAuth2Client.verifyIdToken(),
 * puis les mêmes contrôles que assertVerifiedGooglePayload().
 *
 * Usage (depuis backend/) :
 *   GOOGLE_ID_TOKEN_FILE=./.google-id-token npm run diagnose:google-id-token
 */

const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const {
  GOOGLE_ISSUERS,
  getGoogleClientId,
  createGoogleOAuthClient,
} = require('./services/googleAuthService');

const CLOCK_SKEW_SECONDS = 300;
const JWT_LIKE = /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g;
const SECRET_ENV_KEYS = [
  'GOOGLE_ID_TOKEN',
  'GOOGLE_CLIENT_SECRET',
  'JWT_SECRET',
  'DATABASE_URL',
  'TWILIO_AUTH_TOKEN',
  'TWILIO_ACCOUNT_SID',
  'TWILIO_PHONE_NUMBER',
  'REFRESH_TOKEN',
];

function readTrimmedEnv(name) {
  const value = process.env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function safeClaims(payload) {
  if (!payload || typeof payload !== 'object') {
    return {
      iss: null,
      aud: null,
      azp: null,
      exp: null,
      sub: null,
      email_verified: null,
    };
  }
  return {
    iss: payload.iss ?? null,
    aud: payload.aud ?? null,
    azp: payload.azp ?? null,
    exp: payload.exp ?? null,
    sub: payload.sub ?? null,
    email_verified: payload.email_verified ?? null,
  };
}

function redactEmbeddedJson(text) {
  return String(text).replace(/\{[^{}]*\}/g, (blob) => {
    try {
      const obj = JSON.parse(blob);
      if (obj && typeof obj === 'object' && (obj.iss || obj.aud || obj.email || obj.sub || obj.azp)) {
        return JSON.stringify(safeClaims(obj));
      }
    } catch (_) {
      // Keep non-JSON braces unchanged.
    }
    return blob;
  });
}

function sanitizeText(text, extraForbidden = []) {
  let out = redactEmbeddedJson(String(text ?? ''));
  out = out.replace(JWT_LIKE, '[id_token omitted]');
  for (const piece of extraForbidden) {
    if (typeof piece === 'string' && piece.length >= 8) {
      out = out.split(piece).join('[redacted]');
    }
  }
  for (const key of SECRET_ENV_KEYS) {
    const value = process.env[key];
    if (typeof value === 'string' && value.trim().length >= 8) {
      out = out.split(value).join(`[${key} omitted]`);
      out = out.split(value.trim()).join(`[${key} omitted]`);
    }
  }
  return out;
}

function classifyLibraryError(message) {
  const m = String(message || '');
  if (/Failed to retrieve verification certificates/i.test(m)) {
    return 'certs_fetch';
  }
  if (/No pem found for envelope/i.test(m)) {
    return 'signature_kid';
  }
  if (/Invalid token signature/i.test(m)) {
    return 'signature';
  }
  if (/Wrong recipient/i.test(m)) {
    return 'audience';
  }
  if (/Invalid issuer/i.test(m)) {
    return 'issuer';
  }
  if (/Token used too late|Token used too early|Expiration time too far|No issue time|No expiration time|iat field|exp field/i.test(m)) {
    return 'expiration';
  }
  if (/Wrong number of segments|Can't parse token|The verifyIdToken method requires an ID Token/i.test(m)) {
    return 'token_format';
  }
  return 'unknown_library_error';
}

function decodeUnverifiedJwt(idToken) {
  const segments = idToken.split('.');
  if (segments.length !== 3) {
    return null;
  }
  try {
    const padded = segments[1] + '='.repeat((4 - (segments[1].length % 4)) % 4);
    return JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
  } catch (_) {
    return null;
  }
}

function errorFields(err, extraForbidden = []) {
  if (!err || typeof err !== 'object') {
    return {
      name: null,
      code: null,
      message: sanitizeText(String(err), extraForbidden),
    };
  }
  return {
    name: typeof err.name === 'string' ? err.name : null,
    code: err.code == null || err.code === '' ? null : String(err.code),
    message: sanitizeText(err.message || '', extraForbidden),
  };
}

function printReport({ classified, err, claims, extraForbidden = [] }) {
  const fields = err ? errorFields(err, extraForbidden) : { name: null, code: null, message: null };
  const view = safeClaims(claims);
  console.log(sanitizeText(`classified=${classified}`, extraForbidden));
  console.log(sanitizeText(`err.name=${fields.name || '-'}`, extraForbidden));
  console.log(sanitizeText(`err.code=${fields.code || '-'}`, extraForbidden));
  console.log(sanitizeText(`message=${fields.message || '-'}`, extraForbidden));
  console.log(sanitizeText(`iss=${view.iss == null ? '-' : view.iss}`, extraForbidden));
  console.log(sanitizeText(`aud=${view.aud == null ? '-' : JSON.stringify(view.aud)}`, extraForbidden));
  console.log(sanitizeText(`azp=${view.azp == null ? '-' : JSON.stringify(view.azp)}`, extraForbidden));
  console.log(sanitizeText(`exp=${view.exp == null ? '-' : view.exp}`, extraForbidden));
  console.log(sanitizeText(`sub=${view.sub == null ? '-' : view.sub}`, extraForbidden));
  console.log(
    sanitizeText(
      `email_verified=${view.email_verified == null ? '-' : JSON.stringify(view.email_verified)}`,
      extraForbidden
    )
  );
}

async function withSanitizedConsole(extraForbidden, fn) {
  const original = {
    log: console.log,
    error: console.error,
    warn: console.warn,
    info: console.info,
  };
  const wrap = (write) => (...args) => {
    write(sanitizeText(args.map(String).join(' '), extraForbidden));
  };
  console.log = wrap(original.log);
  console.error = wrap(original.error);
  console.warn = wrap(original.warn);
  console.info = wrap(original.info);
  try {
    return await fn();
  } finally {
    console.log = original.log;
    console.error = original.error;
    console.warn = original.warn;
    console.info = original.info;
  }
}

function readIdTokenFile() {
  const filePath = readTrimmedEnv('GOOGLE_ID_TOKEN_FILE');
  if (!filePath) {
    return {
      error: {
        classified: 'token_file_missing',
        err: new Error('Set GOOGLE_ID_TOKEN_FILE=./.google-id-token'),
      },
    };
  }

  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) {
    return {
      error: {
        classified: 'token_file_missing',
        err: new Error('Token file not found'),
      },
    };
  }

  let raw;
  try {
    raw = fs.readFileSync(resolved, 'utf8');
  } catch (err) {
    return {
      error: {
        classified: 'token_file_missing',
        err: new Error('Token file is not readable'),
      },
    };
  }

  const idToken = String(raw).trim();
  if (!idToken) {
    return {
      error: {
        classified: 'token_file_empty',
        err: new Error('Token file is empty'),
      },
    };
  }

  return { idToken };
}

function classifyPayloadChecks(payload, audience) {
  if (!payload || typeof payload !== 'object') {
    return 'payload';
  }
  if (typeof payload.iss !== 'string' || !GOOGLE_ISSUERS.includes(payload.iss)) {
    return 'issuer';
  }
  if (payload.aud !== audience) {
    return 'audience';
  }
  const exp = Number(payload.exp);
  if (!Number.isFinite(exp)) {
    return 'expiration';
  }
  const nowSeconds = Date.now() / 1000;
  if (nowSeconds > exp + CLOCK_SKEW_SECONDS) {
    return 'expiration';
  }
  if (typeof payload.sub !== 'string' || payload.sub.trim() === '') {
    return 'sub';
  }
  if (typeof payload.email !== 'string' || payload.email.trim() === '') {
    return 'email';
  }
  return null;
}

async function main() {
  const fileResult = readIdTokenFile();
  if (fileResult.error) {
    printReport({
      classified: fileResult.error.classified,
      err: fileResult.error.err,
      claims: null,
    });
    process.exitCode = 1;
    return;
  }

  const idToken = fileResult.idToken;
  const extraForbidden = [idToken];
  const decoded = decodeUnverifiedJwt(idToken);

  const clientId = getGoogleClientId();
  if (!clientId) {
    printReport({
      classified: 'google_client_id_missing',
      err: new Error('GOOGLE_CLIENT_ID is not configured'),
      claims: decoded,
      extraForbidden,
    });
    process.exitCode = 1;
    return;
  }

  const client = createGoogleOAuthClient(clientId);

  let ticket;
  try {
    ticket = await withSanitizedConsole(extraForbidden, () =>
      client.verifyIdToken({
        idToken,
        audience: clientId,
      })
    );
  } catch (err) {
    printReport({
      classified: classifyLibraryError(err && err.message),
      err,
      claims: decoded,
      extraForbidden,
    });
    process.exitCode = 1;
    return;
  }

  const payload = ticket.getPayload();
  const failedCheck = classifyPayloadChecks(payload, clientId);
  if (failedCheck) {
    printReport({
      classified: failedCheck,
      err: new Error(`assertVerifiedGooglePayload rejected: ${failedCheck}`),
      claims: payload || decoded,
      extraForbidden,
    });
    process.exitCode = 1;
    return;
  }

  printReport({
    classified: 'ok',
    err: null,
    claims: payload,
    extraForbidden,
  });
}

main().catch((err) => {
  printReport({
    classified: 'unknown_library_error',
    err,
    claims: null,
  });
  process.exitCode = 1;
});
