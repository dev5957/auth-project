function errorHandler(err, req, res, next) {
  if (res.headersSent) {
    next(err);
    return;
  }

  const statusCode = err.statusCode || 500;
  const message = err.statusCode ? err.message : 'Internal server error';

  if (!err.statusCode) {
    console.error('Unhandled error:', err.code || err.name || 'ERROR');
  }

  res.status(statusCode).json({ error: message });
}

module.exports = errorHandler;
