const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const {
  readChroniqueSchedulerConfig,
  startChroniqueScheduler,
  DEFAULT_INTERVAL_MS,
} = require('./services/chroniqueScheduler');

const TEST_SECRET = 'chronique-scheduler-test-secret-not-for-production';
const TEST_ISSUER = 'auth-project';
const TEST_AUDIENCE = 'auth-project-app';
const TEST_PORT = 30453;

async function waitUntil(predicate, timeoutMs, label) {
  const started = Date.now();
  while (!predicate()) {
    if (Date.now() - started > timeoutMs) {
      throw new Error(label || 'timeout');
    }
    await new Promise((resolve) => setImmediate(resolve));
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function startTestServer(port, extraEnv = {}) {
  const logs = [];
  const env = {
    ...process.env,
    PORT: String(port),
    JWT_SECRET: TEST_SECRET,
    JWT_ISSUER: TEST_ISSUER,
    JWT_AUDIENCE: TEST_AUDIENCE,
    JWT_EXPIRES_IN: '15m',
    REFRESH_TOKEN_EXPIRES_DAYS: '90',
    DEV_LOG_SMS_CODE: 'false',
    DATABASE_URL: '',
    ENABLE_INTERNAL_CRON: 'false',
    ...extraEnv,
  };

  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: path.join(__dirname, '..'),
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const onData = (chunk) => logs.push(chunk.toString('utf8'));
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

function httpGet(port, urlPath) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { hostname: '127.0.0.1', port, path: urlPath, method: 'GET' },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          resolve({ status: res.statusCode, raw: Buffer.concat(chunks).toString('utf8') });
        });
      }
    );
    req.on('error', reject);
    req.end();
  });
}

async function main() {
  const unset = readChroniqueSchedulerConfig({});
  assert(unset.enabled === false, 'default enabled must be false');
  assert(unset.intervalMs === DEFAULT_INTERVAL_MS, 'default interval 60000');

  const falsey = readChroniqueSchedulerConfig({ ENABLE_INTERNAL_CRON: 'false', CRON_INTERVAL_MS: '60000' });
  assert(falsey.enabled === false, 'false string');
  assert(falsey.intervalMs === 60000, 'interval 60000');

  const enabled = readChroniqueSchedulerConfig({ ENABLE_INTERNAL_CRON: 'true', CRON_INTERVAL_MS: '15000' });
  assert(enabled.enabled === true, 'true enables');
  assert(enabled.intervalMs === 15000, 'custom interval');
  console.log('A OK scheduler désactivé par défaut');

  const idleLogs = [];
  let idleRuns = 0;
  const idle = startChroniqueScheduler({
    env: { ENABLE_INTERNAL_CRON: 'false' },
    runJobs: async () => {
      idleRuns += 1;
    },
    log: (line) => idleLogs.push(String(line)),
    installSignals: false,
  });
  assert(idle.enabled === false, 'handle disabled');
  idle.stop();
  assert(idleRuns === 0, 'disabled must not run jobs');
  assert(!idleLogs.some((line) => line.includes('[chronique-scheduler] started')), 'no start log');
  console.log('B OK scheduler inactif ne lance pas les jobs');

  const logs = [];
  let runs = 0;
  const timers = [];
  const handle = startChroniqueScheduler({
    env: { ENABLE_INTERNAL_CRON: 'true', CRON_INTERVAL_MS: '1000' },
    runJobs: async () => {
      runs += 1;
    },
    log: (line) => logs.push(String(line)),
    installSignals: false,
    runOnStart: true,
    setIntervalFn: (fn, ms) => {
      timers.push({ fn, ms });
      return { id: 1 };
    },
    clearIntervalFn: () => {
      timers.push({ cleared: true });
    },
  });
  await waitUntil(() => runs === 1, 1000, 'runOnStart jobs');
  assert(handle.enabled === true, 'enabled handle');
  assert(handle.intervalMs === 1000, 'interval ms');
  assert(logs.includes('[chronique-scheduler] started'), 'started log');
  assert(logs.includes('[chronique-scheduler] running jobs'), 'running log');
  assert(timers[0] && timers[0].ms === 1000, 'interval registered');

  timers[0].fn();
  await waitUntil(() => runs === 2, 1000, 'interval tick runs jobs');

  handle.stop();
  assert(logs.includes('[chronique-scheduler] stopped'), 'stopped log');
  assert(timers.some((item) => item.cleared), 'interval cleared');
  console.log('C OK scheduler activé appelle les jobs existants');

  let overlapping = 0;
  let release;
  const overlapLogs = [];
  const blocked = startChroniqueScheduler({
    env: { ENABLE_INTERNAL_CRON: 'true', CRON_INTERVAL_MS: '1000' },
    runJobs: () =>
      new Promise((resolve) => {
        overlapping += 1;
        release = resolve;
      }),
    log: (line) => overlapLogs.push(String(line)),
    installSignals: false,
    runOnStart: true,
    setIntervalFn: () => ({ id: 2 }),
    clearIntervalFn: () => {},
  });
  await waitUntil(() => overlapping === 1, 1000, 'first tick in flight');
  await blocked.tick();
  assert(overlapping === 1, 'overlap skipped');
  assert(overlapLogs.includes('[chronique-scheduler] skip overlapping tick'), 'overlap log');
  release();
  await Promise.resolve();
  blocked.stop();
  console.log('D OK ticks chevauchants ignorés');

  const { child, logs: serverLogs } = startTestServer(TEST_PORT);
  try {
    await waitForLog(serverLogs, 'Server listening', 8000);
    const health = await httpGet(TEST_PORT, '/health');
    assert(health.status === 200, `health ${health.status}`);
    const joined = serverLogs.join('');
    assert(!joined.includes('[chronique-scheduler] started'), 'process default: no scheduler');
    console.log('E OK process Node sans ENABLE_INTERNAL_CRON ne démarre pas le scheduler');
  } finally {
    await stopServer(child);
  }

  console.log('Chronique scheduler check succeeded.');
}

main().catch((err) => {
  console.error('Chronique scheduler check failed:', err.message);
  process.exitCode = 1;
});
