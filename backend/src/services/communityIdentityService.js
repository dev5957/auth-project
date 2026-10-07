const crypto = require('crypto');
const pool = require('../db');
const AppError = require('../errors/AppError');
const { parseCommunityId } = require('../validators/communityFields');
const {
  parseIdentitySlot,
  parseIdentityUploadInput,
  parseIdentityCompleteInput,
  columnForSlot,
  SESSION_TTL_MS,
} = require('../validators/communityIdentityFields');
const { getStorage } = require('./storageService');
const { toPublicCommunityWithIdentity } = require('./communityService');

const NOT_FOUND = 'Community not found';
const FORBIDDEN = 'Forbidden';
const INCOMPLETE = 'Upload is incomplete';

function requireDatabase() {
  if (!process.env.DATABASE_URL) {
    throw new AppError(503, 'Database is not configured');
  }
}

function requireSecret() {
  const secret = process.env.JWT_SECRET;
  if (typeof secret !== 'string' || secret.trim() === '') {
    throw new AppError(503, 'Database is not configured');
  }
  return secret.trim();
}

function sealSession(payload, secret) {
  const key = crypto.createHash('sha256').update(secret).digest();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(JSON.stringify(payload), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]).toString('base64url');
}

function openSession(token, secret) {
  try {
    const raw = Buffer.from(token, 'base64url');
    if (raw.length < 29) {
      throw new AppError(400, 'upload_id is invalid');
    }
    const iv = raw.subarray(0, 12);
    const tag = raw.subarray(12, 28);
    const enc = raw.subarray(28);
    const key = crypto.createHash('sha256').update(secret).digest();
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    const json = Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
    return JSON.parse(json);
  } catch (err) {
    if (err instanceof AppError) {
      throw err;
    }
    throw new AppError(400, 'upload_id is invalid');
  }
}

function makeStorageKey(communityId, slot) {
  return `communities/${communityId}/${slot}/${crypto.randomUUID()}`;
}

async function loadMembership(client, communityId, userId) {
  const membership = await client.query(
    `SELECT role
     FROM community_members
     WHERE community_id = $1
       AND user_id = $2
     LIMIT 1`,
    [communityId, userId]
  );
  return membership.rows[0] || null;
}

async function requireOwner(client, communityId, userId) {
  const membership = await loadMembership(client, communityId, userId);
  if (!membership) {
    throw new AppError(404, NOT_FOUND);
  }
  if (membership.role !== 'owner') {
    throw new AppError(403, FORBIDDEN);
  }
  return membership;
}

async function withTransaction(db, fn) {
  const client = await db.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    committed = true;
    return result;
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // ignore rollback errors
      }
    }
    throw err;
  } finally {
    client.release();
  }
}

async function createIdentityUpload(userId, rawCommunityId, rawSlot, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const slot = parseIdentitySlot(rawSlot);
  const input = parseIdentityUploadInput(body);
  requireDatabase();
  const secret = requireSecret();
  const storage = getStorage(deps.storage);
  const db = deps.db || pool;

  return withTransaction(db, async (client) => {
    const locked = await client.query(
      `SELECT id
       FROM communities
       WHERE id = $1
       FOR UPDATE`,
      [communityId]
    );
    if (!locked.rows[0]) {
      throw new AppError(404, NOT_FOUND);
    }
    await requireOwner(client, communityId, userId);
    const storageKey = makeStorageKey(communityId, slot);
    const upload = await storage.createDirectUpload({
      storageKey,
      contentType: input.contentType,
      byteSize: input.byteSize,
    });
    const uploadId = sealSession(
      {
        communityId,
        slot,
        userId,
        storageKey,
        contentType: input.contentType,
        byteSize: input.byteSize,
        exp: Date.now() + SESSION_TTL_MS,
      },
      secret
    );
    return {
      slot,
      upload_id: uploadId,
      upload,
    };
  });
}

function logStorageDeleteFailure(communityId, slot, err) {
  const message = err && typeof err.message === 'string' ? err.message : 'storage delete failed';
  console.error(
    '[community-identity] storage delete failed',
    `community_id=${communityId} slot=${slot} message=${message}`
  );
}

async function completeIdentityUpload(userId, rawCommunityId, rawSlot, body, deps = {}) {
  const communityId = parseCommunityId(rawCommunityId);
  const slot = parseIdentitySlot(rawSlot);
  const { uploadId } = parseIdentityCompleteInput(body);
  requireDatabase();
  const secret = requireSecret();
  const session = openSession(uploadId, secret);
  if (
    Number(session.communityId) !== Number(communityId) ||
    session.slot !== slot ||
    Number(session.userId) !== Number(userId)
  ) {
    throw new AppError(400, 'upload_id is invalid');
  }
  if (typeof session.exp !== 'number' || session.exp < Date.now()) {
    throw new AppError(400, 'upload_id is invalid');
  }
  if (typeof session.storageKey !== 'string' || session.storageKey.trim() === '') {
    throw new AppError(400, 'upload_id is invalid');
  }
  const storage = getStorage(deps.storage);
  const db = deps.db || pool;
  const column = columnForSlot(slot);

  const completed = await withTransaction(db, async (client) => {
    const locked = await client.query(
      `SELECT id, avatar_storage_key, banner_storage_key
       FROM communities
       WHERE id = $1
       FOR UPDATE`,
      [communityId]
    );
    const row = locked.rows[0];
    if (!row) {
      throw new AppError(404, NOT_FOUND);
    }
    await requireOwner(client, communityId, userId);
    const head = await storage.head(session.storageKey);
    const expected = Number(session.byteSize);
    if (!head || Number(head.byteSize) !== expected) {
      throw new AppError(400, INCOMPLETE);
    }
    const previousKey = row[column];
    await client.query(
      `UPDATE communities
       SET ${column} = $1,
           updated_at = NOW()
       WHERE id = $2`,
      [session.storageKey, communityId]
    );
    const refreshed = await client.query(
      `SELECT c.id,
              c.name,
              c.description,
              c.visibility,
              c.created_at,
              c.updated_at,
              c.avatar_storage_key,
              c.banner_storage_key,
              m.role AS my_role,
              (
                SELECT COUNT(*)::int
                FROM community_members cm
                WHERE cm.community_id = c.id
              ) AS member_count
       FROM communities c
       INNER JOIN community_members m
         ON m.community_id = c.id
        AND m.user_id = $1
       WHERE c.id = $2
       LIMIT 1`,
      [userId, communityId]
    );
    return {
      row: refreshed.rows[0],
      previousKey:
        typeof previousKey === 'string' && previousKey.trim() !== '' && previousKey !== session.storageKey
          ? previousKey
          : null,
    };
  });

  if (completed.previousKey) {
    try {
      await storage.delete(completed.previousKey);
    } catch (err) {
      logStorageDeleteFailure(communityId, slot, err);
    }
  }

  return {
    community: await toPublicCommunityWithIdentity(completed.row, {
      storage: deps.storage,
      includeBanner: true,
    }),
  };
}

module.exports = {
  createIdentityUpload,
  completeIdentityUpload,
};
