const {
  createPublication,
  listFeed,
  getPublication,
  patchPublication,
  deletePublication,
  restorePublication,
  listMine,
  getMine,
} = require('../services/communityPublicationService');
const {
  createMediaUpload,
  completeMedia,
  deleteMedia,
} = require('../services/communityPublicationMediaService');
const {
  likePublication,
  unlikePublication,
} = require('../services/communityPublicationLikeService');
const {
  listComments,
  createComment,
  updateComment,
  deleteComment,
  restoreComment,
  listMyCommentTraces,
} = require('../services/communityPublicationCommentService');

async function create(req, res, next) {
  try {
    const publication = await createPublication(req.user.userId, req.params.id, req.body);
    res.status(201).json({ message: 'Community publication created', publication });
  } catch (err) {
    next(err);
  }
}

async function list(req, res, next) {
  try {
    const result = await listFeed(req.user.userId, req.params.id, req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function getOne(req, res, next) {
  try {
    const publication = await getPublication(
      req.user.userId,
      req.params.id,
      req.params.publicationId
    );
    res.status(200).json({ publication });
  } catch (err) {
    next(err);
  }
}

async function update(req, res, next) {
  try {
    const publication = await patchPublication(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.body
    );
    res.status(200).json({ message: 'Community publication updated', publication });
  } catch (err) {
    next(err);
  }
}

async function remove(req, res, next) {
  try {
    const result = await deletePublication(
      req.user.userId,
      req.params.id,
      req.params.publicationId
    );
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function restore(req, res, next) {
  try {
    const publication = await restorePublication(
      req.user.userId,
      req.params.id,
      req.params.publicationId
    );
    res.status(200).json({ message: 'Community publication restored', publication });
  } catch (err) {
    next(err);
  }
}

async function createUpload(req, res, next) {
  try {
    const result = await createMediaUpload(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.body
    );
    res.status(201).json(result);
  } catch (err) {
    next(err);
  }
}

async function completeUpload(req, res, next) {
  try {
    const result = await completeMedia(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.params.mediaId
    );
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function removeMedia(req, res, next) {
  try {
    const result = await deleteMedia(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.params.mediaId
    );
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function listMineAction(req, res, next) {
  try {
    const result = await listMine(req.user.userId, req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function getMineAction(req, res, next) {
  try {
    const publication = await getMine(req.user.userId, req.params.publicationId);
    res.status(200).json({ publication });
  } catch (err) {
    next(err);
  }
}

async function like(req, res, next) {
  try {
    const result = await likePublication(req.user.userId, req.params.id, req.params.publicationId);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function unlike(req, res, next) {
  try {
    const result = await unlikePublication(req.user.userId, req.params.id, req.params.publicationId);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function listPublicationComments(req, res, next) {
  try {
    const result = await listComments(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.query
    );
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function createPublicationComment(req, res, next) {
  try {
    const comment = await createComment(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.body
    );
    res.status(201).json({ message: 'Comment created', comment });
  } catch (err) {
    next(err);
  }
}

async function updatePublicationComment(req, res, next) {
  try {
    const comment = await updateComment(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.params.commentId,
      req.body
    );
    res.status(200).json({ message: 'Comment updated', comment });
  } catch (err) {
    next(err);
  }
}

async function removePublicationComment(req, res, next) {
  try {
    const result = await deleteComment(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.params.commentId
    );
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function restorePublicationComment(req, res, next) {
  try {
    const comment = await restoreComment(
      req.user.userId,
      req.params.id,
      req.params.publicationId,
      req.params.commentId
    );
    res.status(200).json({ message: 'Comment restored', comment });
  } catch (err) {
    next(err);
  }
}

async function listMyCommentTracesAction(req, res, next) {
  try {
    const result = await listMyCommentTraces(req.user.userId, req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

module.exports = {
  create,
  list,
  getOne,
  update,
  remove,
  restore,
  createUpload,
  completeUpload,
  removeMedia,
  listMineAction,
  getMineAction,
  like,
  unlike,
  listPublicationComments,
  createPublicationComment,
  updatePublicationComment,
  removePublicationComment,
  restorePublicationComment,
  listMyCommentTracesAction,
};
