const CLEANUP_INTERVAL_MS = 60 * 1000;

function clientIp(req) {
  return req.ip || req.socket?.remoteAddress || 'unknown';
}

function createRateLimiter({ windowMs, max }) {
  const hits = new Map();

  function cleanup() {
    const now = Date.now();
    for (const [key, entry] of hits) {
      if (entry.resetAt <= now) {
        hits.delete(key);
      }
    }
  }

  const timer = setInterval(cleanup, CLEANUP_INTERVAL_MS);
  if (typeof timer.unref === 'function') {
    timer.unref();
  }

  return function rateLimiter(req, res, next) {
    const now = Date.now();
    const ip = clientIp(req);
    let entry = hits.get(ip);

    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      hits.set(ip, entry);
    }

    entry.count += 1;

    if (entry.count > max) {
      const retryAfter = Math.max(1, Math.ceil((entry.resetAt - now) / 1000));
      res.set('Retry-After', String(retryAfter));
      return res.status(429).json({ error: 'Too many requests' });
    }

    next();
  };
}

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;

const authRateLimit = {
  registerStart: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 5 }),
  verifyPhone: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 10 }),
  login: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 10 }),
  refresh: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 30 }),
};

module.exports = {
  createRateLimiter,
  authRateLimit,
};
