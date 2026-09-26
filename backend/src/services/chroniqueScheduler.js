const { runChroniqueLifecycleJobs } = require('./chroniqueJobs');

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

function readChroniqueSchedulerConfig(env = process.env) {
  return {
    enabled: parseBooleanEnv(env.ENABLE_INTERNAL_CRON),
    intervalMs: parseIntervalMs(env.CRON_INTERVAL_MS),
  };
}

/**
 * Internal periodic trigger for Chronique lifecycle jobs.
 * External cron (Cloud Cron, k8s CronJob, EventBridge) should keep calling
 * `npm run jobs:chronique -- --confirm --job=all` instead of this loop.
 * Business rules stay in chroniqueJobs.js.
 */
function startChroniqueScheduler(options = {}) {
  const env = options.env || process.env;
  const config = readChroniqueSchedulerConfig(env);
  const log = options.log || console.log;
  const runJobs = options.runJobs || runChroniqueLifecycleJobs;
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
  const logs = {
    started: '[chronique-scheduler] started',
    running: '[chronique-scheduler] running jobs',
    skipped: '[chronique-scheduler] skip overlapping tick',
    stopped: '[chronique-scheduler] stopped',
  };

  async function tick() {
    if (stopped) {
      return;
    }
    if (inFlight) {
      log(logs.skipped);
      return;
    }
    log(logs.running);
    inFlight = Promise.resolve()
      .then(() => runJobs())
      .catch((err) => {
        const message = err && err.message ? err.message : String(err);
        log(`[chronique-scheduler] jobs failed: ${message}`);
      })
      .finally(() => {
        inFlight = null;
      });
    await inFlight;
  }

  log(logs.started);
  const timer = setIntervalFn(() => {
    tick();
  }, config.intervalMs);

  if (runOnStart) {
    tick();
  }

  handle.stop = function stop() {
    if (stopped) {
      return;
    }
    stopped = true;
    clearIntervalFn(timer);
    log(logs.stopped);
  };

  if (options.installSignals) {
    const onSignal = () => {
      handle.stop();
    };
    process.once('SIGTERM', onSignal);
    process.once('SIGINT', onSignal);
  }

  handle.tick = tick;
  return handle;
}

module.exports = {
  DEFAULT_INTERVAL_MS,
  MIN_INTERVAL_MS,
  readChroniqueSchedulerConfig,
  startChroniqueScheduler,
};
