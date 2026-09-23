const AppError = require('./errors/AppError');
const { getStorage } = require('./services/storageService');
const mockStorage = require('./services/mockStorageService');
const { createR2Storage, readR2Config } = require('./services/r2StorageService');

const TEST_KEY = 'publications/1/media/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/original';
const SECRET = 'r2-test-secret-must-not-appear-in-output';

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
    assert(err instanceof AppError, `expected AppError: ${err && err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    assert(err.message === message, `unexpected message: ${err.message}`);
  }
}

function validEnv(overrides = {}) {
  return {
    R2_ACCOUNT_ID: 'acc123',
    R2_ACCESS_KEY_ID: 'AKIA_TEST_NOT_REAL',
    R2_SECRET_ACCESS_KEY: SECRET,
    R2_BUCKET: 'chronique-media',
    R2_ENDPOINT: 'https://acc123.r2.cloudflarestorage.com',
    R2_REGION: 'auto',
    ...overrides,
  };
}

function createFakeClient({ onSend }) {
  return {
    async send(command) {
      return onSend(command);
    },
  };
}

function notFoundError() {
  const err = new Error('missing');
  err.name = 'NotFound';
  err.$metadata = { httpStatusCode: 404 };
  return err;
}

async function main() {
  assert(getStorage() === mockStorage, 'default provider is mock');
  assert(getStorage(undefined, { STORAGE_PROVIDER: 'mock' }) === mockStorage, 'explicit mock');
  await expectStatus(
    async () => getStorage(undefined, { STORAGE_PROVIDER: 's3' }),
    503,
    'Storage is not configured'
  );
  console.log('A OK factory mock par defaut / provider invalide -> 503');

  await expectStatus(
    async () => readR2Config({}),
    503,
    'Storage is not configured'
  );
  await expectStatus(
    async () =>
      createR2Storage({ env: validEnv({ R2_BUCKET: '' }) }).createDirectUpload({
        storageKey: TEST_KEY,
        contentType: 'image/jpeg',
        byteSize: 10,
      }),
    503,
    'Storage is not configured'
  );
  console.log('B OK configuration R2 absente -> Storage is not configured');

  const signed = createR2Storage({
    env: validEnv({ R2_SIGNED_UPLOAD_TTL_SECONDS: '900', R2_SIGNED_READ_TTL_SECONDS: '300' }),
    client: createFakeClient({
      onSend: async () => {
        throw new Error('sign must not send');
      },
    }),
    signUrl: async (_client, command, { expiresIn }) => {
      const name = command.constructor.name;
      if (name === 'PutObjectCommand') {
        assert(expiresIn === 900, `upload ttl ${expiresIn}`);
        return `https://acc123.r2.cloudflarestorage.com/chronique-media/${TEST_KEY}?X-Amz-Expires=${expiresIn}`;
      }
      if (name === 'GetObjectCommand') {
        assert(expiresIn === 300, `read ttl ${expiresIn}`);
        return `https://acc123.r2.cloudflarestorage.com/chronique-media/${TEST_KEY}?X-Amz-Expires=${expiresIn}`;
      }
      throw new Error(`unexpected command ${name}`);
    },
  });

  const upload = await signed.createDirectUpload({
    storageKey: TEST_KEY,
    contentType: 'image/jpeg',
    byteSize: 2048,
  });
  assert(upload.method === 'PUT', 'upload method');
  assert(typeof upload.url === 'string' && upload.url.includes(TEST_KEY), 'upload url');
  assert(upload.headers['Content-Type'] === 'image/jpeg', 'content-type header');
  assert(typeof upload.expires_at === 'string' && !Number.isNaN(Date.parse(upload.expires_at)), 'expires_at');
  assert(!JSON.stringify(upload).includes(SECRET), 'upload leaked secret');
  assert(!upload.url.includes(SECRET), 'url leaked secret');

  const read = await signed.createReadUrl(TEST_KEY);
  assert(read.method === 'GET', 'read method');
  assert(read.url.includes(TEST_KEY), 'read url');
  assert(!JSON.stringify(read).includes(SECRET), 'read leaked secret');
  console.log('C OK createDirectUpload / createReadUrl signes, sans credentials');

  const objects = new Map();
  const live = createR2Storage({
    env: validEnv(),
    client: createFakeClient({
      onSend: async (command) => {
        const name = command.constructor.name;
        const key = command.input && command.input.Key;
        if (name === 'HeadObjectCommand') {
          const object = objects.get(key);
          if (!object) {
            throw notFoundError();
          }
          return { ContentLength: object.byteSize, ContentType: object.contentType };
        }
        if (name === 'DeleteObjectCommand') {
          objects.delete(key);
          return {};
        }
        throw new Error(`unexpected send ${name}`);
      },
    }),
  });

  const missing = await live.head(TEST_KEY);
  assert(missing === null, 'absent -> null');

  objects.set(TEST_KEY, { byteSize: 2048, contentType: 'image/jpeg' });
  const found = await live.head(TEST_KEY);
  assert(found.byteSize === 2048, 'head byteSize');
  assert(found.contentType === 'image/jpeg', 'head contentType');

  await live.delete(TEST_KEY);
  assert(objects.has(TEST_KEY) === false, 'deleted');
  await live.delete(TEST_KEY);
  const after = await live.head(TEST_KEY);
  assert(after === null, 'delete idempotent');
  console.log('D OK head absent/present + delete idempotent');

  const broken = createR2Storage({
    env: validEnv(),
    client: createFakeClient({
      onSend: async () => {
        const err = new Error('ECONNRESET');
        err.name = 'TimeoutError';
        throw err;
      },
    }),
  });
  await expectStatus(async () => broken.head(TEST_KEY), 503, 'Storage is not configured');
  await expectStatus(async () => broken.delete(TEST_KEY), 503, 'Storage is not configured');

  const brokenSign = createR2Storage({
    env: validEnv(),
    client: createFakeClient({ onSend: async () => ({}) }),
    signUrl: async () => {
      throw new Error('signer failed');
    },
  });
  await expectStatus(
    async () =>
      brokenSign.createDirectUpload({
        storageKey: TEST_KEY,
        contentType: 'image/jpeg',
        byteSize: 1,
      }),
    503,
    'Storage is not configured'
  );
  console.log('E OK erreurs infrastructure -> Storage is not configured (sans secret)');

  const r2FromFactory = getStorage(undefined, { STORAGE_PROVIDER: 'r2' });
  assert(typeof r2FromFactory.createDirectUpload === 'function', 'r2 adapter');
  assert(typeof r2FromFactory.head === 'function', 'r2 head');
  assert(r2FromFactory !== mockStorage, 'r2 is not mock');
  console.log('F OK STORAGE_PROVIDER=r2 selectionne R2Storage');

  console.log('Storage R2 adapter check succeeded (sans bucket reel).');
}

main().catch((err) => {
  console.error('Storage R2 adapter check failed:', err.message);
  process.exitCode = 1;
});
