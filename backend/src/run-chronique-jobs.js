require('dotenv').config();

const pool = require('./db');
const {
  runPublishScheduledJob,
  runExpireActiveJob,
  runPurgeExpiredJob,
  runChroniqueLifecycleJobs,
} = require('./services/chroniqueJobs');

const JOBS = {
  publish: runPublishScheduledJob,
  expire: runExpireActiveJob,
  purge: runPurgeExpiredJob,
  all: runChroniqueLifecycleJobs,
};

async function main() {
  const confirm = process.argv.includes('--confirm');
  const jobArg = process.argv.find((arg) => arg.startsWith('--job='));
  const jobName = jobArg ? jobArg.slice('--job='.length) : 'all';

  if (!confirm) {
    console.error(
      'Refusing to run Chronique jobs. Re-run with --confirm. ' +
        'Jobs: publish (scheduled→active), expire (active→expired), ' +
        'purge (expired→deleted logique). No hard delete.'
    );
    process.exitCode = 1;
    return;
  }

  if (!JOBS[jobName]) {
    console.error(`Unknown job "${jobName}". Use publish, expire, purge, or all.`);
    process.exitCode = 1;
    return;
  }

  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL is not set; Chronique jobs cannot run.');
    process.exitCode = 1;
    return;
  }

  const result = await JOBS[jobName]();
  if (jobName === 'all') {
    console.log(
      `Chronique jobs: published=${result.published} expired=${result.expired} deleted=${result.deleted}`
    );
    return;
  }
  console.log(`Chronique job ${jobName}: ${result.length} row(s).`);
}

main()
  .catch((err) => {
    console.error('Chronique jobs failed:', err.code || err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
