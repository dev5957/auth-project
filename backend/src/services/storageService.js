const AppError = require('../errors/AppError');
const mockStorageService = require('./mockStorageService');

function isStorage(candidate) {
  return (
    candidate != null &&
    typeof candidate.createDirectUpload === 'function' &&
    typeof candidate.head === 'function' &&
    typeof candidate.delete === 'function' &&
    typeof candidate.createReadUrl === 'function'
  );
}

function getStorage(impl) {
  const storage = impl === undefined ? mockStorageService : impl;
  if (!isStorage(storage)) {
    throw new AppError(503, 'Storage is not configured');
  }
  return storage;
}

module.exports = {
  getStorage,
  createDirectUpload: (...args) => getStorage().createDirectUpload(...args),
  head: (...args) => getStorage().head(...args),
  delete: (...args) => getStorage().delete(...args),
  createReadUrl: (...args) => getStorage().createReadUrl(...args),
};
