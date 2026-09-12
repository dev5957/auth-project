const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const { parseCorsOrigins, isAllowedOrigin } = require('./middleware/cors');

const TEST_SECRET = 'cors-test-secret-ok';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30445;
const LOCAL_ORIGIN = 'http://localhost:5500';
const OTHER_ORIGIN = 'http://evil.example';
const ID_TOKEN = 'google-id-token-must-not-appear-in-cors-logs';

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function header(res, name) {
  return res.headers[name.toLowerCase()] || null;
}

function httpRequest({ port, method, urlPath, headers = {}, body }) {
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
          resolve({ status: res.statusCode, json, raw, headers: res.headers });
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
}

function startTestServer(port, extraEnv = {}) {
  const logs = [];
  const env = {
    ...process.env,
    PORT: String(port),
    JWT_SECRET: TEST_SECRET,
    JWT_ISSUER: TEST_ISSUER,
    JWT_AUDIENCE: TEST_AUDIENCE,
    JWT_EXPIRES_IN: '15m',
    GOOGLE_CLIENT_ID: 'cors-test-google-client-id',
    DEV_LOG_SMS_CODE: 'false',
    ...extraEnv,
  };
  delete env.DATABASE_URL;

  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: path.join(__dirname, '..'),
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const onData = (chunk) => {
    logs.push(chunk.toString('utf8'));
  };
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

function assertNoWildcard(res) {
  const allowOrigin = header(res, 'access-control-allow-origin');
  assert(allowOrigin !== '*', 'must not use Access-Control-Allow-Origin: *');
}

async function withServer(extraEnv, fn) {
  const { child, logs } = startTestServer(TEST_PORT, extraEnv);
  try {
    await waitForLog(logs, 'Server listening', 8000);
    await fn(logs);
  } finally {
    await stopServer(child);
  }
}

async function main() {
  assert(parseCorsOrigins(undefined).length === 0, 'unset CORS_ORIGINS');
  assert(parseCorsOrigins('').length === 0, 'empty CORS_ORIGINS');
  assert(JSON.stringify(parseCorsOrigins('http://localhost:5500')) === JSON.stringify([LOCAL_ORIGIN]), 'single origin');
  assert(
    JSON.stringify(parseCorsOrigins(' http://localhost:5500 , https://app.example ')) ===
      JSON.stringify([LOCAL_ORIGIN, 'https://app.example']),
    'comma list'
  );
  assert(parseCorsOrigins('*').length === 0, '* must be ignored');
  assert(parseCorsOrigins('*,http://localhost:5500').length === 1, '* stripped from list');
  assert(isAllowedOrigin(LOCAL_ORIGIN, [LOCAL_ORIGIN]) === true, 'allow listed origin');
  assert(isAllowedOrigin(OTHER_ORIGIN, [LOCAL_ORIGIN]) === false, 'deny other origin');
  assert(isAllowedOrigin('*', ['*']) === false, 'never allow * as a request origin');
  console.log('OK parseCorsOrigins / allowlist');

  await withServer({ CORS_ORIGINS: LOCAL_ORIGIN }, async (logs) => {
    const preflight = await httpRequest({
      port: TEST_PORT,
      method: 'OPTIONS',
      urlPath: '/auth/google/start',
      headers: {
        Origin: LOCAL_ORIGIN,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'content-type',
      },
    });
    assert(preflight.status === 204, `preflight status ${preflight.status} ${preflight.raw}`);
    assertNoWildcard(preflight);
    assert(header(preflight, 'access-control-allow-origin') === LOCAL_ORIGIN, 'preflight ACAO');
    const methods = String(header(preflight, 'access-control-allow-methods') || '').toUpperCase();
    assert(methods.includes('POST'), 'preflight allows POST');
    assert(methods.includes('OPTIONS'), 'preflight allows OPTIONS');
    const allowHeaders = String(header(preflight, 'access-control-allow-headers') || '').toLowerCase();
    assert(allowHeaders.includes('content-type'), 'preflight allows Content-Type');
    console.log('OK OPTIONS preflight localhost:5500');

    const denied = await httpRequest({
      port: TEST_PORT,
      method: 'OPTIONS',
      urlPath: '/auth/google/start',
      headers: {
        Origin: OTHER_ORIGIN,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'content-type',
      },
    });
    assert(denied.status === 204, `denied preflight status ${denied.status}`);
    assertNoWildcard(denied);
    assert(header(denied, 'access-control-allow-origin') == null, 'denied origin must not be reflected');
    console.log('OK OPTIONS origine inconnue sans ACAO');

    const post = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/google/start',
      headers: { Origin: LOCAL_ORIGIN },
      body: { id_token: ID_TOKEN },
    });
    assert(post.status === 401 || post.status === 503, `POST status ${post.status} ${post.raw}`);
    assertNoWildcard(post);
    assert(header(post, 'access-control-allow-origin') === LOCAL_ORIGIN, 'POST ACAO');
    assert(!post.raw.includes(ID_TOKEN), 'response leaked id_token');
    assert(!logs.join('').includes(ID_TOKEN), 'logs leaked id_token');
    console.log('OK POST /auth/google/start reflète localhost:5500, sans * ni id_token');

    const postDenied = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/auth/google/start',
      headers: { Origin: OTHER_ORIGIN },
      body: {},
    });
    assertNoWildcard(postDenied);
    assert(header(postDenied, 'access-control-allow-origin') == null, 'POST other origin has no ACAO');
    console.log('OK POST origine inconnue sans ACAO');
  });

  await withServer({ CORS_ORIGINS: '' }, async () => {
    const preflight = await httpRequest({
      port: TEST_PORT,
      method: 'OPTIONS',
      urlPath: '/auth/google/start',
      headers: {
        Origin: LOCAL_ORIGIN,
        'Access-Control-Request-Method': 'POST',
      },
    });
    assertNoWildcard(preflight);
    assert(header(preflight, 'access-control-allow-origin') == null, 'empty CORS_ORIGINS must not allow localhost');
    console.log('OK CORS_ORIGINS vide : aucune origine (prod par défaut)');
  });

  console.log('CORS checks succeeded.');
}

main().catch((err) => {
  console.error('CORS checks failed:', err.message);
  process.exitCode = 1;
});
