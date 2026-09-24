const AppError = require('../errors/AppError');
const mockStorageService = require('./mockStorageService');
const r2StorageService = require('./r2StorageService');

function isStorage(candidate) {
  return (
    candidate != null &&
    typeof candidate.createDirectUpload === 'function' &&
    typeof candidate.head === 'function' &&
    typeof candidate.delete === 'function' &&
    typeof candidate.createReadUrl === 'function'
  );
}

function resolveProvider(env = process.env) {
  const raw = env.STORAGE_PROVIDER;
  if (raw == null || String(raw).trim() === '') {
    return 'mock';
  }
  return String(raw).trim().toLowerCase();
}

function getStorage(impl, env = process.env) {
  if (impl !== undefined) {
    if (!isStorage(impl)) {
      throw new AppError(503, 'Storage is not configured');
    }
    return impl;
  }

  const provider = resolveProvider(env);
  if (provider === 'mock') {
    return mockStorageService;
  }
  if (provider === 'r2') {
    if (!isStorage(r2StorageService)) {
      throw new AppError(503, 'Storage is not configured');
    }
    return r2StorageService;
  }
  throw new AppError(503, 'Storage is not configured');
}

module.exports = {
  getStorage,
  createDirectUpload: (...args) => getStorage().createDirectUpload(...args),
  head: (...args) => getStorage().head(...args),
  delete: (...args) => getStorage().delete(...args),
  createReadUrl: (...args) => getStorage().createReadUrl(...args),
};
