function parseCorsOrigins(raw = process.env.CORS_ORIGINS) {
  if (typeof raw !== 'string') {
    return [];
  }

  return raw
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value !== '' && value !== '*');
}

function isAllowedOrigin(origin, allowed = parseCorsOrigins()) {
  return typeof origin === 'string' && origin !== '*' && allowed.includes(origin);
}

function corsMiddleware(req, res, next) {
  const origin = req.headers.origin;
  const allowed = isAllowedOrigin(origin);

  res.setHeader('Vary', 'Origin');

  if (allowed) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  }

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  next();
}

module.exports = {
  parseCorsOrigins,
  isAllowedOrigin,
  corsMiddleware,
};
