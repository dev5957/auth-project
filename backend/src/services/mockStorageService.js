const SIGNED_TTL_MS = 15 * 60 * 1000;
const objects = new Map();

function nowMs() {
  return Date.now();
}

function toIso(value) {
  return new Date(value).toISOString();
}

function createDirectUpload({ storageKey, contentType }) {
  const expiresAt = new Date(nowMs() + SIGNED_TTL_MS);
  return {
    method: 'PUT',
    url: `https://mock-storage.local/upload/${encodeURIComponent(storageKey)}`,
    headers: {
      'Content-Type': contentType,
    },
    expires_at: toIso(expiresAt),
  };
}

function put(storageKey, { byteSize, contentType } = {}) {
  objects.set(storageKey, {
    byteSize: Number(byteSize),
    contentType: contentType || 'application/octet-stream',
  });
}

async function head(storageKey) {
  const object = objects.get(storageKey);
  if (!object) {
    return null;
  }
  return {
    byteSize: object.byteSize,
    contentType: object.contentType,
  };
}

async function deleteObject(storageKey) {
  objects.delete(storageKey);
}

async function createReadUrl(storageKey) {
  const expiresAt = new Date(nowMs() + SIGNED_TTL_MS);
  return {
    method: 'GET',
    url: `https://mock-storage.local/read/${encodeURIComponent(storageKey)}`,
    expires_at: toIso(expiresAt),
  };
}

function reset() {
  objects.clear();
}

function getObject(storageKey) {
  return objects.get(storageKey) || null;
}

module.exports = {
  createDirectUpload,
  put,
  head,
  delete: deleteObject,
  createReadUrl,
  reset,
  getObject,
};
