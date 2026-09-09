const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const jwt = require('jsonwebtoken');
const { generateAccessToken } = require('./services/tokenService');

const TEST_SECRET = 'auth-me-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30436;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function httpRequest({ port, method, urlPath, headers = {} }) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: urlPath,
        method,
        headers,
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
    req.end();
  });
}

function startTestServer(port) {
  const logs = [];
  const env = {
    ...process.env,
    PORT: String(port),
    JWT_SECRET: TEST_SECRET,
    JWT_ISSUER: TEST_ISSUER,
    JWT_AUDIENCE: TEST_AUDIENCE,
    JWT_EXPIRES_IN: '15m',
    DEV_LOG_SMS_CODE: 'false',
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

function tamperJwt(token) {
  const chars = token.split('');
  for (let i = chars.length - 1; i >= 0; i -= 1) {
    if (/[A-Za-z0-9]/.test(chars[i])) {
      chars[i] = chars[i] === 'A' ? 'B' : 'A';
      const tampered = chars.join('');
      if (tampered !== token) {
        return tampered;
      }
    }
  }
  throw new Error('could not tamper JWT');
}

async function main() {
  const previousSecret = process.env.JWT_SECRET;
  const previousIssuer = process.env.JWT_ISSUER;
  const previousAudience = process.env.JWT_AUDIENCE;
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;

  const { child, logs } = startTestServer(TEST_PORT);

  try {
    await waitForLog(logs, 'Server listening', 8000);

    const health = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/health',
    });
    assert(health.status === 200, `E: health status ${health.status}`);
    assert(health.json && health.json.status === 'ok', 'E: health body');
    console.log('E OK GET /health -> 200');

    const missing = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
    });
    assert(missing.status === 401, `A: expected 401, got ${missing.status}`);
    assert(missing.json && missing.json.error === 'Unauthorized', `A: body ${missing.raw}`);
    console.log('A OK GET /auth/me sans Authorization -> 401');

    const bad = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: 'Bearer mauvais_token' },
    });
    assert(bad.status === 401, `B: expected 401, got ${bad.status}`);
    assert(bad.json && bad.json.error === 'Unauthorized', `B: body ${bad.raw}`);
    console.log('B OK GET /auth/me Bearer mauvais_token -> 401');

    const accessToken = generateAccessToken({
      id: 42,
      login: 'test_user',
      auth_provider: 'local',
    });

    const ok = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    assert(ok.status === 200, `C: expected 200, got ${ok.status} ${ok.raw}`);
    assert(ok.json && ok.json.user && ok.json.user.userId === 42, 'C: userId');
    assert(ok.json.user.login === 'test_user', 'C: login');
    assert(ok.json.user.auth_provider === 'local', 'C: auth_provider');
    assert(ok.json.user.email === undefined, 'C: email must not be returned');
    assert(ok.json.user.password === undefined, 'C: password must not be returned');
    assert(ok.raw.includes(accessToken) === false, 'C: response must not echo JWT');
    console.log('C OK GET /auth/me avec access_token (même émission que login) -> 200');

    const tampered = tamperJwt(accessToken);
    const mutated = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${tampered}` },
    });
    assert(mutated.status === 401, `D: expected 401, got ${mutated.status}`);
    assert(mutated.json && mutated.json.error === 'Unauthorized', `D: body ${mutated.raw}`);
    console.log('D OK JWT modifié d’un caractère -> 401');

    const expired = jwt.sign(
      { userId: 42, login: 'test_user', auth_provider: 'local' },
      TEST_SECRET,
      { algorithm: 'HS256', expiresIn: -10, issuer: TEST_ISSUER, audience: TEST_AUDIENCE }
    );
    const expiredRes = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: '/auth/me',
      headers: { Authorization: `Bearer ${expired}` },
    });
    assert(expiredRes.status === 401, `expired: expected 401, got ${expiredRes.status}`);

    const combinedLogs = logs.join('');
    assert(!combinedLogs.includes(accessToken), 'F: logs leaked full access JWT');
    assert(!combinedLogs.includes(tampered), 'F: logs leaked tampered JWT');
    assert(!combinedLogs.includes(TEST_SECRET), 'F: logs leaked JWT_SECRET');
    assert(!combinedLogs.includes('JsonWebTokenError'), 'F: logs leaked JWT error name');
    assert(!combinedLogs.includes('TokenExpiredError'), 'F: logs leaked JWT expiry name');
    console.log('F OK logs sans JWT complet ni secret');
  } finally {
    await stopServer(child);
    if (!previousSecret) {
      delete process.env.JWT_SECRET;
    } else {
      process.env.JWT_SECRET = previousSecret;
    }
    if (!previousIssuer) {
      delete process.env.JWT_ISSUER;
    } else {
      process.env.JWT_ISSUER = previousIssuer;
    }
    if (!previousAudience) {
      delete process.env.JWT_AUDIENCE;
    } else {
      process.env.JWT_AUDIENCE = previousAudience;
    }
  }

  console.log('Auth /me checks succeeded.');
}

main().catch((err) => {
  console.error('Auth /me checks failed:', err.message);
  process.exitCode = 1;
});
