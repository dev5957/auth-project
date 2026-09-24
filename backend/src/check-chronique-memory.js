function sqlKey(sql) {
  return String(sql).replace(/\s+/g, ' ').trim().toUpperCase();
}

function cloneRow(row) {
  return { ...row };
}

function createPublicationsMemory(initialRows = []) {
  let nextId = initialRows.reduce((max, row) => Math.max(max, Number(row.id) || 0), 0) + 1;
  const state = {
    rows: initialRows.map(cloneRow),
  };

  async function query(sql, params = []) {
    const key = sqlKey(sql);

    if (key === 'BEGIN' || key === 'COMMIT' || key === 'ROLLBACK') {
      return { rows: [], rowCount: 0 };
    }

    if (key.startsWith('INSERT INTO PUBLICATIONS')) {
      const now = new Date();
      const row = {
        id: nextId,
        user_id: params[0],
        theme_id: null,
        title: params[1],
        body: params[2],
        status: params[3],
        scheduled_at: params[4],
        published_at: params[5],
        archived_at: null,
        expired_at: null,
        purge_after: null,
        deleted_at: null,
        is_time_limited: params[6],
        expires_at: params[7],
        is_public: false,
        audience: 'private',
        comments_enabled: false,
        media_total_bytes: 0,
        created_at: now,
        updated_at: now,
      };
      nextId += 1;
      state.rows.push(row);
      return { rows: [cloneRow(row)], rowCount: 1 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes("STATUS <> 'DELETED'") && key.includes('LIMIT 1')) {
      const row = state.rows.find(
        (item) =>
          Number(item.id) === Number(params[0]) &&
          Number(item.user_id) === Number(params[1]) &&
          item.status !== 'deleted'
      );
      return { rows: row ? [cloneRow(row)] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes('FOR UPDATE')) {
      const row = state.rows.find(
        (item) => Number(item.id) === Number(params[0]) && Number(item.user_id) === Number(params[1])
      );
      return { rows: row ? [cloneRow(row)] : [], rowCount: row ? 1 : 0 };
    }

    if (key.includes('FROM PUBLICATION_MEDIA')) {
      return { rows: [], rowCount: 0 };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes('WHERE USER_ID = $1') && key.includes('AND STATUS = $2')) {
      const userId = params[0];
      const status = params[1];
      const limit = Number(params[params.length - 1]);
      let rows = state.rows.filter(
        (item) => Number(item.user_id) === Number(userId) && item.status === status
      );
      const sortColumn =
        status === 'active'
          ? 'published_at'
          : status === 'archived'
            ? 'archived_at'
            : status === 'expired'
              ? 'expired_at'
              : status === 'scheduled'
                ? 'scheduled_at'
                : 'updated_at';
      rows.sort((a, b) => {
        const av = a[sortColumn] ? new Date(a[sortColumn]).getTime() : 0;
        const bv = b[sortColumn] ? new Date(b[sortColumn]).getTime() : 0;
        if (status === 'scheduled') {
          return av - bv || Number(a.id) - Number(b.id);
        }
        return bv - av || Number(b.id) - Number(a.id);
      });
      return { rows: rows.slice(0, limit).map(cloneRow), rowCount: Math.min(rows.length, limit) };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes("STATUS = 'SCHEDULED'")) {
      const now = params[0];
      const limit = Number(params[1]);
      const rows = state.rows
        .filter(
          (item) =>
            item.status === 'scheduled' &&
            item.scheduled_at &&
            new Date(item.scheduled_at).getTime() <= new Date(now).getTime()
        )
        .sort((a, b) => new Date(a.scheduled_at) - new Date(b.scheduled_at) || Number(a.id) - Number(b.id))
        .slice(0, limit)
        .map(cloneRow);
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes("STATUS = 'ACTIVE'") && key.includes('IS_TIME_LIMITED')) {
      const now = params[0];
      const limit = Number(params[1]);
      const rows = state.rows
        .filter(
          (item) =>
            item.status === 'active' &&
            item.is_time_limited === true &&
            item.expires_at &&
            new Date(item.expires_at).getTime() <= new Date(now).getTime()
        )
        .sort((a, b) => new Date(a.expires_at) - new Date(b.expires_at) || Number(a.id) - Number(b.id))
        .slice(0, limit)
        .map(cloneRow);
      return { rows, rowCount: rows.length };
    }

    if (key.includes('FROM PUBLICATIONS') && key.includes("STATUS = 'EXPIRED'")) {
      const now = params[0];
      const limit = Number(params[1]);
      const nowMs = new Date(now).getTime();
      const rows = state.rows
        .filter((item) => {
          if (item.status !== 'expired') {
            return false;
          }
          if (item.purge_after) {
            return new Date(item.purge_after).getTime() <= nowMs;
          }
          if (!item.expired_at) {
            return false;
          }
          return new Date(item.expired_at).getTime() <= nowMs - 30 * 24 * 60 * 60 * 1000;
        })
        .slice(0, limit)
        .map(cloneRow);
      return { rows, rowCount: rows.length };
    }

    if (key.startsWith('UPDATE PUBLICATIONS') && key.includes('SET STATUS = $1') && key.includes('PUBLISHED_AT')) {
      const row = state.rows.find((item) => Number(item.id) === Number(params[3]) && item.status === 'scheduled');
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = params[0];
      row.published_at = params[1];
      row.updated_at = params[2];
      return { rows: [cloneRow(row)], rowCount: 1 };
    }

    if (
      key.startsWith('UPDATE PUBLICATIONS') &&
      key.includes('SET STATUS = $1') &&
      key.includes('EXPIRED_AT') &&
      key.includes('PURGE_AFTER')
    ) {
      const row = state.rows.find((item) => Number(item.id) === Number(params[4]) && item.status === 'active');
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = params[0];
      row.expired_at = params[1];
      row.purge_after = params[2];
      row.updated_at = params[3];
      return { rows: [cloneRow(row)], rowCount: 1 };
    }

    if (
      key.startsWith('UPDATE PUBLICATIONS') &&
      key.includes('SET STATUS = $1') &&
      key.includes('DELETED_AT = $2')
    ) {
      const row = state.rows.find((item) => Number(item.id) === Number(params[3]) && item.status === 'expired');
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      row.status = params[0];
      row.deleted_at = params[1];
      row.updated_at = params[2];
      return { rows: [cloneRow(row)], rowCount: 1 };
    }

    if (key.startsWith('UPDATE PUBLICATIONS')) {
      const id = params[params.length - 2];
      const userId = params[params.length - 1];
      const row = state.rows.find(
        (item) => Number(item.id) === Number(id) && Number(item.user_id) === Number(userId)
      );
      if (!row) {
        return { rows: [], rowCount: 0 };
      }
      Object.assign(row, {
        title: params[0],
        body: params[1],
        status: params[2],
        scheduled_at: params[3],
        published_at: params[4],
        archived_at: params[5],
        expired_at: params[6],
        purge_after: params[7],
        deleted_at: params[8],
        is_time_limited: params[9],
        expires_at: params[10],
        theme_id: null,
        is_public: false,
        audience: 'private',
        comments_enabled: false,
        updated_at: new Date(),
      });
      return { rows: [cloneRow(row)], rowCount: 1 };
    }

    throw new Error(`unexpected SQL: ${sql}`);
  }

  return {
    state,
    query,
    async connect() {
      return {
        query,
        release() {},
      };
    },
  };
}

module.exports = {
  createPublicationsMemory,
};
