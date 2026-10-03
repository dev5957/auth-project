require('dotenv').config();

const pool = require('./db');
const {
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
  runPendingUploadCleanupJob,
  runCommunityPublicationJobs,
} = require('./services/communityPublicationJobs');

const JOBS = {
  publish: runPublishScheduledJob,
  expire: runExpireActiveJob,
  purge: runPurgeExpiredJob,
  pending: runPendingUploadCleanupJob,
  all: runCommunityPublicationJobs,
};

async function main() {
  const confirm = process.argv.includes('--confirm');
  const jobArg = process.argv.find((arg) => arg.startsWith('--job='));
  const jobName = jobArg ? jobArg.slice('--job='.length) : 'all';

  if (!confirm) {
    console.error(
      'Refusing to run community publication jobs. Re-run with --confirm. ' +
        'Jobs: publish, expire, purge, pending, all.'
    );
    process.exitCode = 1;
    return;
  }

  if (!JOBS[jobName]) {
    console.error(`Unknown job "${jobName}".`);
    process.exitCode = 1;
    return;
  }

  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL is not set; community publication jobs cannot run.');
    process.exitCode = 1;
    return;
  }

  const result = await JOBS[jobName]();
  if (jobName === 'all') {
    console.log(
      `[community-publication-job] publish: ${result.published} expire: ${result.expired} purge: ${result.deleted}`
    );
    return;
  }
  console.log(`[community-publication-job] ${jobName}: ${Array.isArray(result) ? result.length : 0}`);
}

main()
  .catch((err) => {
    console.error('Community publication jobs failed:', err.code || err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
