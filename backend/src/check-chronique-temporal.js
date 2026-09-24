const { parseCreateInput } = require('./validators/chroniqueFields');
const AppError = require('./errors/AppError');
const { createPublicationsMemory } = require('./check-chronique-memory');
const { updateChronique } = require('./services/chroniqueService');
const {
  PURGE_DELAY_DAYS,
  applyScheduledActivation,
  applyExpiration,
  applyLogicalPurge,
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
} = require('./services/chroniqueJobs');

const BODY = 'Le texte de la chronique, d au moins vingt caracteres.';

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function expectAppError(fn, statusCode, message) {
  try {
    fn();
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err.message}`);
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    assert(err.message === message, `unexpected message: ${err.message}`);
  }
}

function sampleRow(overrides = {}) {
  const now = new Date('2026-09-25T10:00:00.000Z');
  return {
    id: 1,
    user_id: 42,
    theme_id: null,
    title: 'Plus tard',
    body: BODY,
    status: 'scheduled',
    scheduled_at: new Date('2026-09-25T14:00:00.000Z'),
    published_at: null,
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

async function main() {
  const previousDb = process.env.DATABASE_URL;
  process.env.DATABASE_URL = previousDb || 'postgres://chronique-temporal-test/local';

  parseCreateInput({
    body: BODY,
    publish: 'now',
    is_time_limited: true,
    expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
  });
  console.log('A OK expiration immediate valide');

  const scheduledAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
  parseCreateInput({
    body: BODY,
    publish: 'schedule',
    scheduled_at: scheduledAt.toISOString(),
    is_time_limited: true,
    expires_at: new Date(scheduledAt.getTime() + 60 * 60 * 1000).toISOString(),
  });
  console.log('B OK expiration programmee valide');

  const tooEarlySchedule = new Date(Date.now() + 4 * 60 * 60 * 1000);
  expectAppError(
    () =>
      parseCreateInput({
        body: BODY,
        publish: 'schedule',
        scheduled_at: tooEarlySchedule.toISOString(),
        is_time_limited: true,
        expires_at: new Date(tooEarlySchedule.getTime() - 2 * 60 * 60 * 1000).toISOString(),
      }),
    400,
    'expires_at must be after activation time'
  );
  console.log('C OK expiration avant publication refusee');

  const equalAt = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
  expectAppError(
    () =>
      parseCreateInput({
        body: BODY,
        publish: 'schedule',
        scheduled_at: equalAt,
        is_time_limited: true,
        expires_at: equalAt,
      }),
    400,
    'expires_at must be after activation time'
  );
  const equalDb = createPublicationsMemory([
    sampleRow({
      id: 8,
      status: 'scheduled',
      scheduled_at: new Date(equalAt),
    }),
  ]);
  try {
    await updateChronique(
      42,
      8,
      { is_time_limited: true, expires_at: equalAt },
      { db: equalDb }
    );
    throw new Error('expected equal expiration to fail');
  } catch (err) {
    assert(err instanceof AppError, `expected AppError: ${err.message}`);
    assert(err.statusCode === 400, `expected 400, got ${err.statusCode}`);
    assert(err.message === 'expires_at must be after activation time', err.message);
  }
  console.log('D OK expiration egale publication refusee');

  const activation = new Date('2026-09-25T14:00:00.000Z');
  const due = applyScheduledActivation(sampleRow(), activation);
  assert(due && due.status === 'active', 'scheduled due -> active');
  assert(due.published_at.getTime() === activation.getTime(), 'published_at at job time');
  const notDue = applyScheduledActivation(
    sampleRow(),
    new Date('2026-09-25T13:59:59.000Z')
  );
  assert(notDue == null, 'scheduled future stays');
  console.log('E OK job scheduled -> active');

  const expireNow = new Date('2026-09-25T16:00:00.000Z');
  const expired = applyExpiration(
    sampleRow({
      status: 'active',
      scheduled_at: null,
      published_at: new Date('2026-09-25T14:00:00.000Z'),
      is_time_limited: true,
      expires_at: new Date('2026-09-25T15:00:00.000Z'),
    }),
    expireNow
  );
  assert(expired && expired.status === 'expired', 'active ephemeral -> expired');
  assert(expired.expired_at.getTime() === expireNow.getTime(), 'expired_at');
  assert(
    expired.purge_after.getTime() === expireNow.getTime() + PURGE_DELAY_DAYS * 24 * 60 * 60 * 1000,
    'purge_after +30d'
  );
  const archivedIgnored = applyExpiration(
    sampleRow({
      status: 'archived',
      is_time_limited: true,
      expires_at: new Date('2026-09-25T12:00:00.000Z'),
    }),
    expireNow
  );
  assert(archivedIgnored == null, 'archived never expires');
  const durableIgnored = applyExpiration(
    sampleRow({
      status: 'active',
      is_time_limited: false,
      expires_at: new Date('2026-09-25T12:00:00.000Z'),
    }),
    expireNow
  );
  assert(durableIgnored == null, 'non time-limited stays active');
  console.log('F OK job expiration active only');

  const purged = applyLogicalPurge(
    sampleRow({
      status: 'expired',
      expired_at: new Date('2026-08-20T10:00:00.000Z'),
      purge_after: new Date('2026-09-19T10:00:00.000Z'),
    }),
    new Date('2026-09-25T10:00:00.000Z')
  );
  assert(purged && purged.status === 'deleted', 'expired +30d -> deleted');
  assert(purged.deleted_at != null, 'deleted_at set');
  const notPurged = applyLogicalPurge(
    sampleRow({
      status: 'expired',
      expired_at: new Date('2026-09-24T10:00:00.000Z'),
      purge_after: new Date('2026-10-24T10:00:00.000Z'),
    }),
    new Date('2026-09-25T10:00:00.000Z')
  );
  assert(notPurged == null, 'expired within 30d stays');
  console.log('G OK job purge logique expired -> deleted');

  const db = createPublicationsMemory([
    sampleRow({
      id: 1,
      status: 'scheduled',
      scheduled_at: new Date('2026-09-25T14:00:00.000Z'),
    }),
    sampleRow({
      id: 2,
      status: 'active',
      scheduled_at: null,
      published_at: new Date('2026-09-25T10:00:00.000Z'),
      is_time_limited: true,
      expires_at: new Date('2026-09-25T11:00:00.000Z'),
    }),
    sampleRow({
      id: 3,
      status: 'archived',
      archived_at: new Date('2026-09-25T10:30:00.000Z'),
      is_time_limited: false,
      expires_at: null,
    }),
    sampleRow({
      id: 4,
      status: 'expired',
      expired_at: new Date('2026-08-01T10:00:00.000Z'),
      purge_after: new Date('2026-08-31T10:00:00.000Z'),
    }),
  ]);

  const now = new Date('2026-09-25T16:00:00.000Z');
  const published = await runPublishScheduledJob({ db, now, query: db.query.bind(db) });
  assert(published.length === 1, 'publish job count');
  assert(published[0].status === 'active', 'publish job status');

  const expiredRows = await runExpireActiveJob({ db, now, query: db.query.bind(db) });
  assert(expiredRows.length === 1, 'expire job count');
  assert(expiredRows[0].id === 2, 'expire job id');
  assert(db.state.rows.find((row) => row.id === 3).status === 'archived', 'archive untouched');

  const deletedRows = await runPurgeExpiredJob({ db, now, query: db.query.bind(db) });
  assert(deletedRows.length === 1, 'purge job count');
  assert(deletedRows[0].status === 'deleted', 'purge job status');
  assert(db.state.rows.find((row) => row.id === 4).status === 'deleted', 'row deleted logically');
  assert(db.state.rows.find((row) => row.id === 4).deleted_at != null, 'no hard delete');
  console.log('H OK jobs SQL memoire publish/expire/purge');

  if (!previousDb) {
    delete process.env.DATABASE_URL;
  } else {
    process.env.DATABASE_URL = previousDb;
  }

  console.log('Chronique temporal check succeeded.');
}

main().catch((err) => {
  console.error('Chronique temporal check failed:', err.message);
  process.exitCode = 1;
});
