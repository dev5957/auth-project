const crypto = require('crypto');
const AppError = require('../errors/AppError');
const { parseUploadInput, parseMediaId } = require('../validators/mediaFields');
const { parseCommunityId } = require('../validators/communityFields');
const {
  parseId,
  MAX_MEDIA,
  MAX_BYTES,
  STATUS,
} = require('../validators/communityPublicationFields');
const {
  withTransaction,
  requireActiveMembership,
  loadMediaRows,
  toPublicMedia,
  toPublicPublication,
} = require('./communityPublicationService');
const { getStorage } = require('./storageService');
const { thumbnailStorageKey } = require('./mediaStorageKeys');
const pool = require('../db');

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function makeStorageKey(communityId, publicationId) {
  return `communities/${communityId}/publications/${publicationId}/media/${crypto.randomUUID()}`;
}

function collectStorageKeys(mediaRow) {
  const keys = [];
  const storageKey = typeof mediaRow.storage_key === 'string' ? mediaRow.storage_key.trim() : '';
  if (storageKey) {
    keys.push(storageKey);
  }
  if (mediaRow.kind === 'video') {
    const thumb = thumbnailStorageKey(storageKey);
    if (thumb && !keys.includes(thumb)) {
      keys.push(thumb);
    }
  }
  return keys;
}

async function quotaUsage(client, publicationId) {
  const result = await client.query(
    `SELECT COUNT(*)::int AS media_count,
            COALESCE(SUM(byte_size), 0)::bigint AS media_bytes
     FROM community_publication_media
     WHERE community_publication_id = $1
       AND status IN ('pending_upload', 'ready')`,
    [publicationId]
  );
  const row = result.rows[0];
  return {
    count: Number(row.media_count) || 0,
    bytes: Number(row.media_bytes) || 0,
  };
}

async function setMediaTotalBytes(client, publicationId, bytes) {
  await client.query(
    `UPDATE community_publications
     SET media_total_bytes = $1,
         updated_at = NOW()
     WHERE id = $2`,
    [bytes, publicationId]
  );
}

async function intakeCounts(client, publicationId) {
  const result = await client.query(
    `SELECT COUNT(*) FILTER (WHERE status = 'pending_upload')::int AS pending_count,
            COUNT(*) FILTER (WHERE status = 'ready')::int AS ready_count,
            COUNT(*) FILTER (WHERE status = 'failed')::int AS failed_count
     FROM community_publication_media
     WHERE community_publication_id = $1`,
    [publicationId]
  );
  const row = result.rows[0] || {};
  return {
    pending: Number(row.pending_count) || 0,
    ready: Number(row.ready_count) || 0,
    failed: Number(row.failed_count) || 0,
  };
}

async function maybeCloseInitialMediaIntake(client, publicationId) {
  const found = await client.query(
    `SELECT initial_media_count, initial_media_open
     FROM community_publications
     WHERE id = $1
     LIMIT 1`,
    [publicationId]
  );
  const pub = found.rows[0];
  if (!pub || !pub.initial_media_open) {
    return;
  }
  const counts = await intakeCounts(client, publicationId);
  const slots = Number(pub.initial_media_count) || 0;
  if (counts.pending === 0 && counts.failed === 0 && counts.ready >= slots && slots > 0) {
    await client.query(
      `UPDATE community_publications
       SET initial_media_open = FALSE,
           updated_at = NOW()
       WHERE id = $1
         AND initial_media_open = TRUE`,
      [publicationId]
    );
  }
}

function assertInitialUploadAllowed(row, usage) {
  if (!row.initial_media_open) {
    throw new AppError(400, 'media cannot be added after creation');
  }
  const slots = Number(row.initial_media_count) || 0;
  if (slots < 1 || usage.count >= slots) {
    throw new AppError(400, 'media cannot be added after creation');
  }
}

async function loadOwnedWritable(client, communityId, publicationId, userId) {
  await requireActiveMembership(client, communityId, userId);
  const found = await client.query(
    `SELECT * FROM community_publications
     WHERE id = $1 AND community_id = $2
     FOR UPDATE`,
    [publicationId, communityId]
  );
  const row = found.rows[0];
  if (!row || row.status === STATUS.DELETED || row.status === STATUS.EXPIRED) {
    throw new AppError(404, 'Community publication not found');
  }
  if (Number(row.author_user_id) !== Number(userId)) {
    throw new AppError(403, 'Forbidden');
  }
  if (![STATUS.DRAFT, STATUS.SCHEDULED, STATUS.ACTIVE].includes(row.status)) {
    throw new AppError(400, 'publication cannot accept media in this status');
  }
  return row;
}

async function createMediaUpload(userId, rawCommunityId, rawId, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawId, 'id is invalid');
  const input = parseUploadInput(body);
  requireDatabase();
  const storage = getStorage(deps.storage);
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const row = await loadOwnedWritable(client, communityId, publicationId, userId);
    const usage = await quotaUsage(client, row.id);
    assertInitialUploadAllowed(row, usage);
    if (usage.count >= MAX_MEDIA) {
      throw new AppError(400, 'Too many media');
    }
    if (usage.bytes + input.byteSize > MAX_BYTES) {
      throw new AppError(400, 'Media quota exceeded');
    }
    const storageKey = makeStorageKey(communityId, row.id);
    const inserted = await client.query(
      `INSERT INTO community_publication_media (
         community_publication_id,
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
    await setMediaTotalBytes(client, row.id, nextBytes);
    const upload = await storage.createDirectUpload({
      storageKey,
      contentType: input.contentType,
      byteSize: input.byteSize,
    });
    const result = { media: toPublicMedia(mediaRow), upload };
    if (input.kind === 'video') {
      const thumbKey = thumbnailStorageKey(storageKey);
      if (thumbKey) {
        try {
          result.thumbnail_upload = await storage.createDirectUpload({
            storageKey: thumbKey,
            contentType: 'image/jpeg',
          });
        } catch (err) {
          const message = err && typeof err.message === 'string' ? err.message : 'thumbnail upload url failed';
          console.error('[community-media-thumbnail] upload url failed', message);
        }
      }
    }
    return result;
  });
}

async function completeMedia(userId, rawCommunityId, rawId, rawMediaId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawId, 'id is invalid');
  const mediaId = parseMediaId(rawMediaId);
  requireDatabase();
  const storage = getStorage(deps.storage);
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const row = await loadOwnedWritable(client, communityId, publicationId, userId);
    const found = await client.query(
      `SELECT * FROM community_publication_media
       WHERE id = $1 AND community_publication_id = $2
       FOR UPDATE`,
      [mediaId, publicationId]
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
        `UPDATE community_publication_media SET status = 'failed' WHERE id = $1`,
        [media.id]
      );
      throw new AppError(400, 'Upload is incomplete');
    }
    const maxOrder = await client.query(
      `SELECT COALESCE(MAX(sort_order), -1)::int AS max_order
       FROM community_publication_media
       WHERE community_publication_id = $1 AND status = 'ready'`,
      [publicationId]
    );
    const sortOrder = Number(maxOrder.rows[0].max_order) + 1;
    await client.query(
      `UPDATE community_publication_media
       SET status = 'ready', sort_order = $1
       WHERE id = $2`,
      [sortOrder, media.id]
    );
    const usage = await quotaUsage(client, publicationId);
    await setMediaTotalBytes(client, publicationId, usage.bytes);
    await maybeCloseInitialMediaIntake(client, publicationId);
    const mediaRows = await loadMediaRows(client, publicationId);
    const refreshed = await client.query(`SELECT * FROM community_publications WHERE id = $1`, [publicationId]);
    return {
      publication: toPublicPublication(refreshed.rows[0], {
        media: mediaRows.map(toPublicMedia),
      }),
    };
  });
}

async function deleteMedia(userId, rawCommunityId, rawId, rawMediaId, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const publicationId = parseId(rawId, 'id is invalid');
  const mediaId = parseMediaId(rawMediaId);
  requireDatabase();
  const storage = getStorage(deps.storage);
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    await loadOwnedWritable(client, communityId, publicationId, userId);
    const found = await client.query(
      `SELECT * FROM community_publication_media
       WHERE id = $1 AND community_publication_id = $2
       FOR UPDATE`,
      [mediaId, publicationId]
    );
    const media = found.rows[0];
    if (!media) {
      throw new AppError(404, 'Media not found');
    }
    for (const key of collectStorageKeys(media)) {
      try {
        await storage.delete(key);
      } catch (_) {
        // continue cleanup
      }
    }
    await client.query(`DELETE FROM community_publication_media WHERE id = $1`, [media.id]);
    const usage = await quotaUsage(client, publicationId);
    await setMediaTotalBytes(client, publicationId, usage.bytes);
    await maybeCloseInitialMediaIntake(client, publicationId);
    return { deleted: true };
  });
}

async function abandonDraftsAndPendingUploads(client, communityId, userId, deps = {}) {
  const storage = getStorage(deps.storage);
  const drafts = await client.query(
    `SELECT * FROM community_publications
     WHERE community_id = $1
       AND author_user_id = $2
       AND status = 'draft'
     FOR UPDATE`,
    [communityId, userId]
  );
  const pending = await client.query(
    `SELECT m.*
     FROM community_publication_media m
     INNER JOIN community_publications p ON p.id = m.community_publication_id
     WHERE p.community_id = $1
       AND p.author_user_id = $2
       AND m.status = 'pending_upload'`,
    [communityId, userId]
  );

  for (const media of pending.rows) {
    for (const key of collectStorageKeys(media)) {
      try {
        await storage.delete(key);
      } catch (_) {
        // best-effort
      }
    }
    await client.query(`DELETE FROM community_publication_media WHERE id = $1`, [media.id]);
  }

  for (const draft of drafts.rows) {
    const mediaRows = await loadMediaRows(client, draft.id);
    for (const media of mediaRows) {
      for (const key of collectStorageKeys(media)) {
        try {
          await storage.delete(key);
        } catch (_) {
          // best-effort
        }
      }
    }
    await client.query(`DELETE FROM community_publication_media WHERE community_publication_id = $1`, [
      draft.id,
    ]);
    await client.query(`DELETE FROM community_publications WHERE id = $1 AND status = 'draft'`, [draft.id]);
  }

  for (const media of pending.rows) {
    const usage = await quotaUsage(client, media.community_publication_id);
    await setMediaTotalBytes(client, media.community_publication_id, usage.bytes);
  }
}

module.exports = {
  createMediaUpload,
  completeMedia,
  deleteMedia,
  abandonDraftsAndPendingUploads,
  collectStorageKeys,
  MAX_MEDIA,
  MAX_BYTES,
};
