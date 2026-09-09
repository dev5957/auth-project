function errorHandler(err, req, res, next) {
  if (res.headersSent) {
    next(err);
    return;
  }

  if (err.type === 'entity.too.large' || err.status === 413 || err.statusCode === 413) {
    res.status(413).json({ error: 'Payload too large' });
    return;
  }

  if (err instanceof SyntaxError && (err.status === 400 || err.statusCode === 400)) {
    res.status(400).json({ error: 'Invalid JSON' });
    return;
  }

  const statusCode = err.statusCode || 500;
  const message = err.statusCode ? err.message : 'Internal server error';

  if (!err.statusCode) {
    const name = err.name || 'Error';
    const code = err.code || '';
    console.error('Unhandled error:', name, code);
  }

  res.status(statusCode).json({ error: message });
}

module.exports = errorHandler;
