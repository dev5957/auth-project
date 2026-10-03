const { runCommunityPublicationJobs } = require('./communityPublicationJobs');

const DEFAULT_INTERVAL_MS = 60 * 1000;
const MIN_INTERVAL_MS = 1000;

function parseBooleanEnv(value) {
  if (value == null) {
    return false;
  }
  const normalized = String(value).trim().toLowerCase();
  return normalized === 'true' || normalized === '1' || normalized === 'yes';
}

function parseIntervalMs(value) {
  if (value == null || String(value).trim() === '') {
    return DEFAULT_INTERVAL_MS;
  }
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < MIN_INTERVAL_MS) {
    return DEFAULT_INTERVAL_MS;
  }
  return parsed;
}

function readConfig(env = process.env) {
  return {
    enabled: parseBooleanEnv(env.ENABLE_INTERNAL_CRON),
    intervalMs: parseIntervalMs(env.CRON_INTERVAL_MS),
  };
}

function startCommunityPublicationScheduler(options = {}) {
  const env = options.env || process.env;
  const config = readConfig(env);
  const log = options.log || console.log;
  const runJobs = options.runJobs || runCommunityPublicationJobs;
  const setIntervalFn = options.setIntervalFn || setInterval;
  const clearIntervalFn = options.clearIntervalFn || clearInterval;
  const runOnStart = options.runOnStart !== false;

  const handle = {
    enabled: config.enabled,
    intervalMs: config.intervalMs,
    stop() {},
  };

  if (!config.enabled) {
    return handle;
  }

  let stopped = false;
  let inFlight = null;

  async function tick() {
    if (stopped) {
      return;
    }
    if (inFlight) {
      log('[community-publication-scheduler] skip overlapping tick');
      return;
    }
    log('[community-publication-scheduler] running jobs');
    inFlight = Promise.resolve()
      .then(() => runJobs())
      .catch((err) => {
        const message = err && err.message ? err.message : String(err);
        log(`[community-publication-scheduler] jobs failed: ${message}`);
      })
      .finally(() => {
        inFlight = null;
      });
    await inFlight;
  }

  if (runOnStart) {
    Promise.resolve().then(tick);
  }
  const timer = setIntervalFn(tick, config.intervalMs);
  handle.stop = () => {
    stopped = true;
    clearIntervalFn(timer);
    log('[community-publication-scheduler] stopped');
  };
  log('[community-publication-scheduler] started');
  return handle;
}

module.exports = {
  startCommunityPublicationScheduler,
};
