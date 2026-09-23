require('dotenv').config();

const crypto = require('crypto');
const fs = require('fs/promises');
const http = require('http');
const https = require('https');
const path = require('path');
const { URL } = require('url');
const storageService = require('./services/storageService');

const REQUIRED_VARS = [
  'R2_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET',
  'R2_ENDPOINT',
];
const SAMPLE_TEXT = 'appLumina R2 integration test';
const TMP_DIR = path.join(__dirname, '..', 'tmp');
const TMP_FILE = path.join(TMP_DIR, 'r2-test-file.txt');

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

function isLiveConfigPresent() {
  const provider = readTrimmed('STORAGE_PROVIDER');
  if (!provider || provider.toLowerCase() !== 'r2') {
    return false;
  }
  return REQUIRED_VARS.every((name) => readTrimmed(name));
}

function assertSignedShape(result, method) {
  assert(result && result.method === method, `method ${method}`);
  assert(typeof result.url === 'string' && result.url.startsWith('http'), 'signed url missing');
  assert(typeof result.expires_at === 'string' && !Number.isNaN(Date.parse(result.expires_at)), 'expires_at');
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

async function main() {
  if (!isLiveConfigPresent()) {
    console.log('R2 live test skipped: Storage is not configured');
    return;
  }

  const storageKey = `tests/r2/${crypto.randomUUID()}/sample.txt`;
  const body = Buffer.from(SAMPLE_TEXT, 'utf8');
  const byteSize = body.length;
  let objectCreated = false;

  await fs.mkdir(TMP_DIR, { recursive: true });
  await fs.writeFile(TMP_FILE, body);

  try {
    const storage = storageService.getStorage();
    assert(typeof storage.createDirectUpload === 'function', 'StorageService adapter');
    console.log('A OK R2 configuration');

    const upload = await storageService.createDirectUpload({
      storageKey,
      contentType: 'text/plain',
      byteSize,
    });
    assertSignedShape(upload, 'PUT');
    assert(upload.headers && upload.headers['Content-Type'] === 'text/plain', 'Content-Type');
    console.log('B OK signed upload URL');

    const status = await putBuffer(upload.url, upload.headers, body);
    assert(status >= 200 && status < 300, `real upload failed: HTTP ${status}`);
    objectCreated = true;
    console.log('C OK real upload');

    const head = await storageService.head(storageKey);
    assert(head != null, 'head missing');
    assert(Number(head.byteSize) === byteSize, 'head byteSize');
    assert(head.contentType === 'text/plain', 'head contentType');
    console.log('D OK head object');

    const read = await storageService.createReadUrl(storageKey);
    assertSignedShape(read, 'GET');
    console.log('E OK signed read URL');

    await storageService.delete(storageKey);
    objectCreated = false;
    const after = await storageService.head(storageKey);
    assert(after === null, 'head after delete');
    console.log('F OK delete object');

    console.log('Storage R2 live check succeeded.');
  } finally {
    if (objectCreated) {
      try {
        await storageService.delete(storageKey);
      } catch (_) {
        // ignore cleanup errors
      }
    }
    try {
      await fs.unlink(TMP_FILE);
    } catch (_) {
      // ignore missing temp file
    }
  }
}

main().catch((err) => {
  console.error('Storage R2 live check failed:', err.message);
  process.exitCode = 1;
});
