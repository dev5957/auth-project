const crypto = require('crypto');
const AppError = require('../errors/AppError');
const { parseChroniqueId } = require('../validators/chroniqueFields');
const { parseMediaId, parseUploadInput, parseMediaOrder } = require('../validators/mediaFields');
const { toPublicChronique, toPublicMedia, withOwnedPublication } = require('./chroniqueService');
const { getStorage } = require('./storageService');

const MAX_MEDIA = 20;
const MAX_BYTES = 209715200;
const MEDIA_WRITABLE_STATUSES = ['draft', 'scheduled', 'active'];

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function assertAcceptsMedia(row) {
  if (!MEDIA_WRITABLE_STATUSES.includes(row.status)) {
    throw new AppError(400, 'Chronique cannot accept media in this status');
  }
}

function makeStorageKey(publicationId) {
  return `publications/${publicationId}/media/${crypto.randomUUID()}`;
}

async function loadMediaRows(client, publicationId) {
  const result = await client.query(
    `SELECT *
     FROM publication_media
     WHERE publication_id = $1
     ORDER BY sort_order ASC, id ASC`,
    [publicationId]
  );
  return result.rows;
}

async function quotaUsage(client, publicationId) {
  const result = await client.query(
    `SELECT COUNT(*)::int AS media_count,
            COALESCE(SUM(byte_size), 0)::bigint AS media_bytes
     FROM publication_media
     WHERE publication_id = $1
       AND status IN ('pending_upload', 'ready')`,
    [publicationId]
  );
  const row = result.rows[0];
  return {
    count: Number(row.media_count) || 0,
    bytes: Number(row.media_bytes) || 0,
  };
}

async function setMediaTotalBytes(client, publicationId, userId, bytes) {
  await client.query(
    `UPDATE publications
     SET media_total_bytes = $1,
         updated_at = NOW()
     WHERE id = $2
       AND user_id = $3`,
    [bytes, publicationId, userId]
  );
}

async function publicChroniqueWithMedia(client, publication) {
  const mediaRows = await loadMediaRows(client, publication.id);
  const chronique = toPublicChronique(publication);
  chronique.media = mediaRows.map(toPublicMedia);
  chronique.media_total_bytes = Number(publication.media_total_bytes) || 0;
  return chronique;
}

async function createMediaUpload(userId, rawId, body, deps = {}) {
  const input = parseUploadInput(body);
  requireDatabase();
  const storage = getStorage(deps.storage);

  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    assertAcceptsMedia(row);
    const usage = await quotaUsage(client, row.id);
    if (usage.count >= MAX_MEDIA) {
      throw new AppError(400, 'Too many media');
    }
    if (usage.bytes + input.byteSize > MAX_BYTES) {
      throw new AppError(400, 'Media quota exceeded');
    }

    const storageKey = makeStorageKey(row.id);
    const inserted = await client.query(
      `INSERT INTO publication_media (
         publication_id,
         kind,
         source_type,
         storage_key,
         content_type,
         byte_size,
         original_filename,
         sort_order,
         status
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7, 0, 'pending_upload')
       RETURNING *`,
      [
        row.id,
        input.kind,
        input.sourceType,
        storageKey,
        input.contentType,
        input.byteSize,
        input.originalFilename,
      ]
    );
    const mediaRow = inserted.rows[0];
    const nextBytes = usage.bytes + input.byteSize;
    await setMediaTotalBytes(client, row.id, row.user_id, nextBytes);
    row.media_total_bytes = nextBytes;

    const upload = await storage.createDirectUpload({
      storageKey,
      contentType: input.contentType,
      byteSize: input.byteSize,
    });

    return {
      media: toPublicMedia(mediaRow),
      upload,
    };
  });
}

async function completeMedia(userId, rawId, rawMediaId, deps = {}) {
  parseChroniqueId(rawId);
  const mediaId = parseMediaId(rawMediaId);
  requireDatabase();
  const storage = getStorage(deps.storage);

  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    assertAcceptsMedia(row);
    const found = await client.query(
      `SELECT *
       FROM publication_media
       WHERE id = $1
         AND publication_id = $2
       FOR UPDATE`,
      [mediaId, row.id]
    );
    const media = found.rows[0];
    if (!media) {
      throw new AppError(404, 'Media not found');
    }
    if (media.status !== 'pending_upload') {
      throw new AppError(400, 'Media is not pending');
    }

    const head = await storage.head(media.storage_key);
    const expected = Number(media.byte_size);
    if (!head || Number(head.byteSize) !== expected) {
      await client.query(
        `UPDATE publication_media
         SET status = 'failed'
         WHERE id = $1
           AND publication_id = $2`,
        [media.id, row.id]
      );
      const usage = await quotaUsage(client, row.id);
      await setMediaTotalBytes(client, row.id, row.user_id, usage.bytes);
      row.media_total_bytes = usage.bytes;
      throw new AppError(400, 'Upload is incomplete');
    }

    const usage = await quotaUsage(client, row.id);
    if (usage.count > MAX_MEDIA || usage.bytes > MAX_BYTES) {
      await client.query(
        `UPDATE publication_media
         SET status = 'failed'
         WHERE id = $1
           AND publication_id = $2`,
        [media.id, row.id]
      );
      const next = await quotaUsage(client, row.id);
      await setMediaTotalBytes(client, row.id, row.user_id, next.bytes);
      throw new AppError(400, usage.count > MAX_MEDIA ? 'Too many media' : 'Media quota exceeded');
    }

    const maxOrder = await client.query(
      `SELECT COALESCE(MAX(sort_order), -1)::int AS max_order
       FROM publication_media
       WHERE publication_id = $1
         AND status = 'ready'`,
      [row.id]
    );
    const sortOrder = Number(maxOrder.rows[0].max_order) + 1;

    await client.query(
      `UPDATE publication_media
       SET status = 'ready',
           sort_order = $1
       WHERE id = $2
         AND publication_id = $3`,
      [sortOrder, media.id, row.id]
    );
    await setMediaTotalBytes(client, row.id, row.user_id, usage.bytes);
    row.media_total_bytes = usage.bytes;
    const publication = { ...row };
    return publicChroniqueWithMedia(client, publication);
  });
}

async function deleteMedia(userId, rawId, rawMediaId, deps = {}) {
  const mediaId = parseMediaId(rawMediaId);
  requireDatabase();
  const storage = getStorage(deps.storage);

  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    assertAcceptsMedia(row);
    const found = await client.query(
      `SELECT *
       FROM publication_media
       WHERE id = $1
         AND publication_id = $2
       FOR UPDATE`,
      [mediaId, row.id]
    );
    const media = found.rows[0];
    if (!media) {
      throw new AppError(404, 'Media not found');
    }

    await storage.delete(media.storage_key);
    await client.query(`DELETE FROM publication_media WHERE id = $1 AND publication_id = $2`, [
      media.id,
      row.id,
    ]);
    const usage = await quotaUsage(client, row.id);
    await setMediaTotalBytes(client, row.id, row.user_id, usage.bytes);
    row.media_total_bytes = usage.bytes;
    return publicChroniqueWithMedia(client, row);
  });
}

async function reorderMedia(userId, rawId, body, deps = {}) {
  const mediaIds = parseMediaOrder(body);
  requireDatabase();

  return withOwnedPublication(userId, rawId, deps, async (client, row) => {
    assertAcceptsMedia(row);
    const ready = await client.query(
      `SELECT id
       FROM publication_media
       WHERE publication_id = $1
         AND status = 'ready'
       ORDER BY sort_order ASC, id ASC
       FOR UPDATE`,
      [row.id]
    );
    const readyIds = ready.rows.map((item) => Number(item.id));
    if (readyIds.length !== mediaIds.length) {
      throw new AppError(400, 'media_ids is invalid');
    }
    const expected = new Set(readyIds);
    for (const id of mediaIds) {
      if (!expected.has(id)) {
        throw new AppError(400, 'media_ids is invalid');
      }
      expected.delete(id);
    }
    if (expected.size !== 0) {
      throw new AppError(400, 'media_ids is invalid');
    }

    await client.query(
      `UPDATE publication_media
       SET sort_order = sort_order + 100000
       WHERE publication_id = $1
         AND status = 'ready'`,
      [row.id]
    );
    for (let index = 0; index < mediaIds.length; index += 1) {
      await client.query(
        `UPDATE publication_media
         SET sort_order = $1
         WHERE id = $2
           AND publication_id = $3
           AND status = 'ready'`,
        [index, mediaIds[index], row.id]
      );
    }

    return publicChroniqueWithMedia(client, row);
  });
}

module.exports = {
  MAX_MEDIA,
  MAX_BYTES,
  createMediaUpload,
  completeMedia,
  deleteMedia,
  reorderMedia,
  toPublicMedia,
};
