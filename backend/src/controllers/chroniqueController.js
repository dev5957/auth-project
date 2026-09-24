const {
  createChronique,
  listChroniques,
  getChroniqueById,
  updateChronique,
  archiveChronique,
  restoreChronique,
  deleteChronique,
} = require('../services/chroniqueService');
const {
  createMediaUpload,
  completeMedia,
  deleteMedia,
  reorderMedia,
} = require('../services/chroniqueMediaService');

async function create(req, res, next) {
  try {
    const chronique = await createChronique(req.user.userId, req.body);
    res.status(201).json({
      message: 'Chronique created',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

async function list(req, res, next) {
  try {
    const result = await listChroniques(req.user.userId, req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function getOne(req, res, next) {
  try {
    const chronique = await getChroniqueById(req.user.userId, req.params.id);
    res.status(200).json({ chronique });
  } catch (err) {
    next(err);
  }
}

async function update(req, res, next) {
  try {
    const chronique = await updateChronique(req.user.userId, req.params.id, req.body);
    res.status(200).json({
      message: 'Chronique updated',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

async function archive(req, res, next) {
  try {
    const chronique = await archiveChronique(req.user.userId, req.params.id);
    res.status(200).json({
      message: 'Chronique archived',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

async function restore(req, res, next) {
  try {
    const chronique = await restoreChronique(req.user.userId, req.params.id, req.body);
    res.status(200).json({
      message: 'Chronique restored',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

async function remove(req, res, next) {
  try {
    await deleteChronique(req.user.userId, req.params.id);
    res.status(200).json({
      message: 'Chronique deleted',
    });
  } catch (err) {
    next(err);
  }
}

async function createUpload(req, res, next) {
  try {
    const result = await createMediaUpload(req.user.userId, req.params.id, req.body);
    res.status(201).json({
      message: 'Upload created',
      media: result.media,
      upload: result.upload,
    });
  } catch (err) {
    next(err);
  }
}

async function completeUpload(req, res, next) {
  try {
    const chronique = await completeMedia(
      req.user.userId,
      req.params.id,
      req.params.mediaId
    );
    res.status(200).json({
      message: 'Media ready',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

async function removeMedia(req, res, next) {
  try {
    const chronique = await deleteMedia(
      req.user.userId,
      req.params.id,
      req.params.mediaId
    );
    res.status(200).json({
      message: 'Media deleted',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

async function reorder(req, res, next) {
  try {
    const chronique = await reorderMedia(req.user.userId, req.params.id, req.body);
    res.status(200).json({
      message: 'Media order updated',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  create,
  list,
  getOne,
  update,
  archive,
  restore,
  remove,
  createUpload,
  completeUpload,
  removeMedia,
  reorder,
};
