require('dotenv').config();

const crypto = require('crypto');
const fs = require('fs/promises');
const http = require('http');
const https = require('https');
const path = require('path');
const { URL } = require('url');
const express = require('express');
const pool = require('./db');
const { generateAccessToken } = require('./services/tokenService');
const storageService = require('./services/storageService');
const errorHandler = require('./middleware/errorHandler');
const { corsMiddleware } = require('./middleware/cors');
const chroniqueRoutes = require('./routes/chroniques');

const REQUIRED_R2_VARS = [
  'R2_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET',
  'R2_ENDPOINT',
];
const SAMPLE_TEXT = 'appLumina Chronique R2 live test';
const TEST_PORT = 30455;
const TMP_DIR = path.join(__dirname, '..', 'tmp');
const TMP_FILE = path.join(TMP_DIR, 'chronique-r2-live.txt');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function readTrimmed(name) {
  const value = process.env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function skipReason() {
  const provider = readTrimmed('STORAGE_PROVIDER');
  if (!provider || provider.toLowerCase() !== 'r2') {
    return 'R2 live test skipped: Storage is not configured';
  }
  if (!REQUIRED_R2_VARS.every((name) => readTrimmed(name))) {
    return 'R2 live test skipped: Storage is not configured';
  }
  if (!readTrimmed('DATABASE_URL')) {
    return 'R2 live test skipped: Database is not configured';
  }
  if (!readTrimmed('JWT_SECRET') || !readTrimmed('JWT_ISSUER') || !readTrimmed('JWT_AUDIENCE')) {
    return 'R2 live test skipped: JWT is not configured';
  }
  return null;
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
          ...(payload
            ? { 'Content-Type': 'application/json', 'Content-Length': String(payload.length) }
            : {}),
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
    req.on('error', reject);
    if (payload) {
      req.write(payload);
    }
    req.end();
  });
}

function putBuffer(urlString, headers, body) {
  return new Promise((resolve, reject) => {
    let url;
    try {
      url = new URL(urlString);
    } catch (_) {
      reject(new Error('signed upload url is invalid'));
      return;
    }
    const lib = url.protocol === 'https:' ? https : http;
    const req = lib.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || undefined,
        path: `${url.pathname}${url.search}`,
        method: 'PUT',
        headers,
      },
      (res) => {
        res.resume();
        res.on('end', () => resolve(res.statusCode));
      }
    );
    req.on('error', () => reject(new Error('real upload failed')));
    req.end(body);
  });
}

function storageKeyFromSignedUrl(urlString) {
  const url = new URL(urlString);
  const bucket = readTrimmed('R2_BUCKET');
  const parts = url.pathname.split('/').filter(Boolean).map((part) => decodeURIComponent(part));
  if (bucket && parts[0] === bucket) {
    return parts.slice(1).join('/');
  }
  return parts.join('/');
}

function assertNoSecrets(payload, raw) {
  const text = `${JSON.stringify(payload)}\n${raw}`;
  assert(!text.includes('storage_key'), 'leaked storage_key');
  assert(!/"user_id"/.test(text), 'leaked user_id');
  const secret = readTrimmed('R2_SECRET_ACCESS_KEY');
  const accessKey = readTrimmed('R2_ACCESS_KEY_ID');
  if (secret) {
    assert(!text.includes(secret), 'leaked R2 secret');
  }
  if (accessKey) {
    assert(!text.includes(accessKey), 'leaked R2 access key');
  }
}

async function createTestUser() {
  const suffix = crypto.randomUUID().replace(/-/g, '').slice(0, 12);
  const inserted = await pool.query(
    `INSERT INTO users (
       email,
       birth_date,
       phone_number,
       phone_verified,
       login,
       password_hash,
       auth_provider
     )
     VALUES ($1, '1990-01-15', $2, TRUE, $3, NULL, 'local')
     RETURNING id, login, auth_provider`,
    [`r2live.${suffix}@example.test`, `+33600${suffix.slice(0, 8)}`, `r2live_${suffix}`]
  );
  return inserted.rows[0];
}

async function hardDeletePublication(publicationId) {
  if (publicationId == null) {
    return;
  }
  await pool.query('DELETE FROM publication_media WHERE publication_id = $1', [publicationId]);
  await pool.query('DELETE FROM publications WHERE id = $1', [publicationId]);
}

async function hardDeleteUser(userId) {
  if (userId == null) {
    return;
  }
  await pool.query('DELETE FROM users WHERE id = $1', [userId]);
}

async function main() {
  const skipped = skipReason();
  if (skipped) {
    console.log(skipped);
    return;
  }

  const fileBody = Buffer.from(SAMPLE_TEXT, 'utf8');
  const byteSize = fileBody.length;
  let server;
  let userId = null;
  let chroniqueId = null;
  let storageKey = null;
  let objectCreated = false;

  await fs.mkdir(TMP_DIR, { recursive: true });
  await fs.writeFile(TMP_FILE, fileBody);

  const app = express();
  app.use(corsMiddleware);
  app.use(express.json({ limit: '32kb' }));
  app.use('/chroniques', chroniqueRoutes);
  app.use(errorHandler);

  try {
    server = await new Promise((resolve) => {
      const httpServer = app.listen(TEST_PORT, '127.0.0.1', () => resolve(httpServer));
    });

    const user = await createTestUser();
    userId = user.id;
    const token = generateAccessToken({
      id: user.id,
      login: user.login,
      auth_provider: user.auth_provider,
    });
    const auth = { Authorization: `Bearer ${token}` };

    const created = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: '/chroniques',
      headers: auth,
      body: {
        title: 'R2 live',
        body: 'Le texte de la chronique, d au moins vingt caracteres.',
        publish: 'now',
      },
    });
    assert(created.status === 201, `create failed: HTTP ${created.status}`);
    assert(created.json.chronique && created.json.chronique.status === 'active', 'not active');
    chroniqueId = created.json.chronique.id;
    console.log('A OK chronique créée');

    const init = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: `/chroniques/${chroniqueId}/media/uploads`,
      headers: auth,
      body: {
        kind: 'document',
        source_type: 'upload',
        content_type: 'text/plain',
        byte_size: byteSize,
        original_filename: 'chronique-r2-live.txt',
      },
    });
    assert(init.status === 201, `upload init failed: HTTP ${init.status}`);
    assert(init.json.media && init.json.media.status === 'pending_upload', 'pending_upload');
    assert(init.json.upload && init.json.upload.method === 'PUT', 'PUT method');
    assert(typeof init.json.upload.url === 'string' && init.json.upload.url.startsWith('http'), 'signed url');
    assert(init.json.upload.headers && init.json.upload.headers['Content-Type'] === 'text/plain', 'Content-Type');
    storageKey = storageKeyFromSignedUrl(init.json.upload.url);
    console.log('B OK upload signé R2');

    const putStatus = await putBuffer(init.json.upload.url, init.json.upload.headers, fileBody);
    assert(putStatus >= 200 && putStatus < 300, `real upload failed: HTTP ${putStatus}`);
    objectCreated = true;
    console.log('C OK fichier envoyé R2');

    const complete = await httpRequest({
      port: TEST_PORT,
      method: 'POST',
      urlPath: `/chroniques/${chroniqueId}/media/${init.json.media.id}/complete`,
      headers: auth,
    });
    assert(complete.status === 200, `complete failed: HTTP ${complete.status}`);
    const ready = (complete.json.chronique.media || []).find((item) => item.id === init.json.media.id);
    assert(ready && ready.status === 'ready', 'complete not ready');
    console.log('D OK complete -> ready');

    const read = await httpRequest({
      port: TEST_PORT,
      method: 'GET',
      urlPath: `/chroniques/${chroniqueId}`,
      headers: auth,
    });
    assert(read.status === 200, `GET failed: HTTP ${read.status}`);
    assert(Array.isArray(read.json.chronique.media) && read.json.chronique.media.length >= 1, 'media missing');
    const listed = read.json.chronique.media.find((item) => item.id === init.json.media.id);
    assert(listed && listed.status === 'ready', 'GET not ready');
    assertNoSecrets(read.json, read.raw);
    console.log('E OK lecture chronique avec média');

    const deleted = await httpRequest({
      port: TEST_PORT,
      method: 'DELETE',
      urlPath: `/chroniques/${chroniqueId}/media/${init.json.media.id}`,
      headers: auth,
    });
    assert(deleted.status === 200, `delete media failed: HTTP ${deleted.status}`);
    objectCreated = false;
    const gone = await storageService.head(storageKey);
    assert(gone === null, 'R2 object still present');
    console.log('F OK suppression média + R2 delete');

    const removed = await httpRequest({
      port: TEST_PORT,
      method: 'DELETE',
      urlPath: `/chroniques/${chroniqueId}`,
      headers: auth,
    });
    assert(removed.status === 200, `delete chronique failed: HTTP ${removed.status}`);
    await hardDeletePublication(chroniqueId);
    chroniqueId = null;
    await hardDeleteUser(userId);
    userId = null;
    console.log('G OK nettoyage');

    console.log('Chronique full-flow R2 live check succeeded.');
  } finally {
    if (objectCreated && storageKey) {
      try {
        await storageService.delete(storageKey);
      } catch (_) {
        // ignore cleanup errors
      }
    }
    try {
      await hardDeletePublication(chroniqueId);
    } catch (_) {
      // ignore cleanup errors
    }
    try {
      await hardDeleteUser(userId);
    } catch (_) {
      // ignore cleanup errors
    }
    try {
      await fs.unlink(TMP_FILE);
    } catch (_) {
      // ignore missing temp file
    }
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
    try {
      await pool.end();
    } catch (_) {
      // ignore
    }
  }
}

main().catch((err) => {
  console.error('Chronique full-flow R2 live check failed:', err.message);
  process.exitCode = 1;
});
