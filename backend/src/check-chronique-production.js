const fs = require('fs');
const path = require('path');
const { generateAccessToken } = require('./services/tokenService');
const errorHandler = require('./middleware/errorHandler');
const AppError = require('./errors/AppError');
const { CHRONIQUE_STATUS } = require('./validators/chroniqueFields');
const {
  getChroniqueById,
  updateChronique,
  deleteChronique,
  archiveChronique,
  createChronique,
  listChroniques,
} = require('./services/chroniqueService');
const {
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
  formatChroniqueJobLogs,
} = require('./services/chroniqueJobs');
const { createPublicationsMemory } = require('./check-chronique-memory');

const TEST_SECRET = 'chronique-production-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const OWNER_A = 11;
const OWNER_B = 22;
const BODY = 'Le texte de la chronique, d au moins vingt caracteres.';
const SQL_010 = path.join(__dirname, '..', 'sql', '010_add_publications_scheduled_index.sql');
const SQL_008 = path.join(__dirname, '..', 'sql', '008_create_publications.sql');

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

function stamp(value) {
  if (value == null) {
    return null;
  }
  return new Date(value).toISOString();
}

function sampleRow(overrides = {}) {
  const now = new Date('2026-09-25T10:00:00.000Z');
  return {
    id: 1,
    user_id: OWNER_A,
    theme_id: null,
    title: 'A',
    body: BODY,
    status: CHRONIQUE_STATUS.ACTIVE,
    scheduled_at: null,
    published_at: now,
    archived_at: null,
    expired_at: null,
    purge_after: null,
    deleted_at: null,
    is_time_limited: false,
    expires_at: null,
    is_public: false,
    audience: 'private',
    comments_enabled: false,
    media_total_bytes: 0,
    created_at: now,
    updated_at: now,
    ...overrides,
  };
}

function inspectScheduledIndexSql() {
  const sql010 = fs.readFileSync(SQL_010, 'utf8');
  const sql008 = fs.readFileSync(SQL_008, 'utf8');
  assert(/CREATE INDEX IF NOT EXISTS publications_user_id_scheduled_feed_idx/i.test(sql010), '010 index name');
  assert(/ON public\.publications/i.test(sql010), '010 must target public.publications');
  assert(/USING btree \(user_id, scheduled_at ASC, id ASC\)/i.test(sql010), '010 btree columns ASC');
  assert(/WHERE status = 'scheduled'/i.test(sql010), '010 partial scheduled');
  assert(/MANUELLEMENT/i.test(sql010), '010 must be manual');
  assert(!/DROP\s+INDEX/i.test(sql010), '010 must not drop indexes');
  assert(!/publications_user_id_active_feed_idx/.test(sql010), '010 must not touch active index');
  assert(!/publications_user_id_archived_feed_idx/.test(sql010), '010 must not touch archived index');
  assert(!/publications_user_id_expired_feed_idx/.test(sql010), '010 must not touch expired index');
  assert(!/publications_user_id_scheduled_feed_idx/.test(sql008), '008 must stay without scheduled index');
  console.log('A OK sql/010 scheduled index (fichier, non appliqué)');
}

function mockResponse() {
  return {
    headersSent: false,
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

async function main() {
  const previous = {
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_ISSUER: process.env.JWT_ISSUER,
    JWT_AUDIENCE: process.env.JWT_AUDIENCE,
    DATABASE_URL: process.env.DATABASE_URL,
  };
  process.env.JWT_SECRET = TEST_SECRET;
  process.env.JWT_ISSUER = TEST_ISSUER;
  process.env.JWT_AUDIENCE = TEST_AUDIENCE;
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://chronique-production-test/local';

  inspectScheduledIndexSql();

  const unexpected = mockResponse();
  errorHandler(new Error('secret stack should not leak'), {}, unexpected, () => {});
  assert(unexpected.statusCode === 500, 'unexpected HTTP');
  assert(JSON.stringify(unexpected.body) === '{"error":"Internal server error"}', 'unexpected body');
  assert(!JSON.stringify(unexpected.body).includes('stack'), 'no stack');

  const appErr = mockResponse();
  errorHandler(new AppError(404, 'Chronique not found'), {}, appErr, () => {});
  assert(appErr.statusCode === 404, 'app error status');
  assert(appErr.body.error === 'Chronique not found', 'app error message');
  assert(Object.keys(appErr.body).join(',') === 'error', 'only error key');
  console.log('B OK erreurs { error } sans stack');

  const db = createPublicationsMemory([
    sampleRow({ id: 1, user_id: OWNER_A, title: 'Privee A' }),
    sampleRow({
      id: 2,
      user_id: OWNER_B,
      title: 'Privee B',
      published_at: new Date('2026-09-25T11:00:00.000Z'),
    }),
  ]);

  await expectStatus(
    () => getChroniqueById(OWNER_A, 2, { db }),
    404,
    'Chronique not found'
  );
  await expectStatus(
    () => updateChronique(OWNER_A, 2, { title: 'Hack' }, { db }),
    404,
    'Chronique not found'
  );
  await expectStatus(
    () => deleteChronique(OWNER_A, 2, { db }),
    404,
    'Chronique not found'
  );
  await expectStatus(
    () => archiveChronique(OWNER_A, 2, { db }),
    404,
    'Chronique not found'
  );
  const stillB = db.state.rows.find((row) => row.id === 2);
  assert(stillB.status === CHRONIQUE_STATUS.ACTIVE, 'B unchanged');
  assert(stillB.title === 'Privee B', 'B title unchanged');
  console.log('C OK ownership GET/PATCH/DELETE/archive -> 404');

  const tokenA = generateAccessToken({
    id: OWNER_A,
    login: 'owner_a',
    auth_provider: 'local',
  });
  assert(typeof tokenA === 'string' && tokenA.length > 10, 'jwt usable');

  const t1 = new Date(Date.now() + 60 * 60 * 1000);
  const t2 = new Date(Date.now() + 2 * 60 * 60 * 1000);
  const t3 = new Date(Date.now() + 3 * 60 * 60 * 1000);
  await createChronique(
    OWNER_A,
    { body: BODY, publish: 'schedule', scheduled_at: t2.toISOString(), title: 'Midi' },
    { db }
  );
  await createChronique(
    OWNER_A,
    { body: BODY, publish: 'schedule', scheduled_at: t3.toISOString(), title: 'Soir' },
    { db }
  );
  await createChronique(
    OWNER_A,
    { body: BODY, publish: 'schedule', scheduled_at: t1.toISOString(), title: 'Matin' },
    { db }
  );
  await createChronique(
    OWNER_B,
    { body: BODY, publish: 'schedule', scheduled_at: t1.toISOString(), title: 'Autre user' },
    { db }
  );

  const listedA = await listChroniques(OWNER_A, { status: CHRONIQUE_STATUS.SCHEDULED }, { db });
  assert(listedA.items.length === 3, `scheduled A count ${listedA.items.length}`);
  assert(
    listedA.items.map((item) => item.title).join(',') === 'Matin,Midi,Soir',
    `scheduled order ${listedA.items.map((item) => item.title).join(',')}`
  );
  const times = listedA.items.map((item) => new Date(item.scheduled_at).getTime());
  assert(times[0] <= times[1] && times[1] <= times[2], 'scheduled_at ASC');
  assert(
    listedA.items.every((item) => item.status === CHRONIQUE_STATUS.SCHEDULED),
    'only scheduled'
  );

  const listedB = await listChroniques(OWNER_B, { status: CHRONIQUE_STATUS.SCHEDULED }, { db });
  assert(listedB.items.length === 1, 'scheduled B count');
  assert(listedB.items[0].title === 'Autre user', 'scheduled B isolation');
  assert(
    !listedA.items.some((item) => item.title === 'Autre user'),
    'A does not see B scheduled'
  );
  console.log('D OK GET scheduled ASC + isolation utilisateur');

  const jobNow = new Date('2026-09-27T12:00:00.000Z');
  const jobDb = createPublicationsMemory([
    sampleRow({
      id: 10,
      status: CHRONIQUE_STATUS.SCHEDULED,
      scheduled_at: new Date('2026-09-27T10:00:00.000Z'),
      published_at: null,
    }),
    sampleRow({
      id: 11,
      status: CHRONIQUE_STATUS.ACTIVE,
      is_time_limited: true,
      expires_at: new Date('2026-09-27T11:00:00.000Z'),
      published_at: new Date('2026-09-26T10:00:00.000Z'),
    }),
    sampleRow({
      id: 12,
      status: CHRONIQUE_STATUS.EXPIRED,
      expired_at: new Date('2026-08-01T10:00:00.000Z'),
      purge_after: new Date('2026-08-31T10:00:00.000Z'),
    }),
  ]);
  const q = jobDb.query.bind(jobDb);

  const published1 = await runPublishScheduledJob({ db: jobDb, query: q, now: jobNow });
  const expired1 = await runExpireActiveJob({ db: jobDb, query: q, now: jobNow });
  const purged1 = await runPurgeExpiredJob({ db: jobDb, query: q, now: jobNow });
  assert(published1.length === 1, 'publish first');
  assert(expired1.length === 1, 'expire first');
  assert(purged1.length === 1, 'purge first');

  const afterFirst = {
    publishedAt: stamp(jobDb.state.rows.find((row) => row.id === 10).published_at),
    expiredAt: stamp(jobDb.state.rows.find((row) => row.id === 11).expired_at),
    purgeAfter: stamp(jobDb.state.rows.find((row) => row.id === 11).purge_after),
    deletedAt: stamp(jobDb.state.rows.find((row) => row.id === 12).deleted_at),
    status10: jobDb.state.rows.find((row) => row.id === 10).status,
    status11: jobDb.state.rows.find((row) => row.id === 11).status,
    status12: jobDb.state.rows.find((row) => row.id === 12).status,
  };

  const published2 = await runPublishScheduledJob({ db: jobDb, query: q, now: jobNow });
  const expired2 = await runExpireActiveJob({ db: jobDb, query: q, now: jobNow });
  const purged2 = await runPurgeExpiredJob({ db: jobDb, query: q, now: jobNow });
  assert(published2.length === 0, 'publish idempotent');
  assert(expired2.length === 0, 'expire idempotent');
  assert(purged2.length === 0, 'purge idempotent');
  assert(
    stamp(jobDb.state.rows.find((row) => row.id === 10).published_at) === afterFirst.publishedAt,
    'published_at unchanged'
  );
  assert(
    stamp(jobDb.state.rows.find((row) => row.id === 11).expired_at) === afterFirst.expiredAt,
    'expired_at unchanged'
  );
  assert(
    stamp(jobDb.state.rows.find((row) => row.id === 11).purge_after) === afterFirst.purgeAfter,
    'purge_after unchanged'
  );
  assert(
    stamp(jobDb.state.rows.find((row) => row.id === 12).deleted_at) === afterFirst.deletedAt,
    'deleted_at unchanged'
  );
  assert(jobDb.state.rows.find((row) => row.id === 10).status === afterFirst.status10, 'status 10');
  assert(jobDb.state.rows.find((row) => row.id === 11).status === afterFirst.status11, 'status 11');
  assert(jobDb.state.rows.find((row) => row.id === 12).status === afterFirst.status12, 'status 12');
  console.log('E OK jobs publish/expire/purge idempotents');

  const logs = formatChroniqueJobLogs({ published: 3, expired: 2, deleted: 0 }, 'all');
  assert(logs.includes('[chronique-job]'), 'log prefix');
  assert(logs.includes('3 publications activated'), 'publish log');
  assert(logs.includes('2 publications expired'), 'expire log');
  assert(logs.includes('0 publications deleted'), 'purge log');
  console.log('F OK logs jobs [chronique-job]');

  if (previous.DATABASE_URL) {
    const pool = require('./db');
    try {
      const plan = await pool.query(
        `EXPLAIN
         SELECT *
         FROM publications
         WHERE user_id = $1
           AND status = 'scheduled'
         ORDER BY scheduled_at ASC, id ASC
         LIMIT 21`,
        [OWNER_A]
      );
      const text = plan.rows.map((row) => Object.values(row).join(' ')).join('\n');
      if (/publications_user_id_scheduled_feed_idx/i.test(text)) {
        console.log('G OK EXPLAIN utilise publications_user_id_scheduled_feed_idx');
      } else {
        console.log('G SKIP EXPLAIN index scheduled (migration 010 non appliquée ou plan différent)');
        console.log(text);
      }
    } catch (err) {
      console.log(`G SKIP EXPLAIN live: ${err.message}`);
    }
  } else {
    console.log('G SKIP EXPLAIN live (DATABASE_URL absent) — index vérifié dans sql/010');
  }

  process.env.JWT_SECRET = previous.JWT_SECRET;
  process.env.JWT_ISSUER = previous.JWT_ISSUER;
  process.env.JWT_AUDIENCE = previous.JWT_AUDIENCE;
  if (!previous.DATABASE_URL) {
    delete process.env.DATABASE_URL;
  } else {
    process.env.DATABASE_URL = previous.DATABASE_URL;
  }

  console.log('Chronique production readiness check succeeded.');
}

main().catch((err) => {
  console.error('Chronique production check failed:', err.message);
  process.exitCode = 1;
});
