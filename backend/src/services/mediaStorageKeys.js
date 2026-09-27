const THUMBNAIL_SUFFIX = '.thumb.jpg';

function thumbnailStorageKey(storageKey) {
  if (typeof storageKey !== 'string') {
    return null;
  }
  const key = storageKey.trim();
  if (key === '') {
    return null;
  }
  if (key.endsWith(THUMBNAIL_SUFFIX)) {
    return key;
  }
  return `${key}${THUMBNAIL_SUFFIX}`;
}

module.exports = {
  THUMBNAIL_SUFFIX,
  thumbnailStorageKey,
};
