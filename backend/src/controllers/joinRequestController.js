const {
  createJoinRequest,
  listCommunityJoinRequests,
  listMyJoinRequests,
  acceptJoinRequest,
  declineJoinRequest,
} = require('../services/joinRequestService');

async function create(req, res, next) {
  try {
    const joinRequest = await createJoinRequest(
      req.user.userId,
      req.params.id,
      req.body
    );
    res.status(201).json({
      message: 'Join request created',
      join_request: joinRequest,
    });
  } catch (err) {
    next(err);
  }
}

async function listForCommunity(req, res, next) {
  try {
    const result = await listCommunityJoinRequests(req.user.userId, req.params.id);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function listMine(req, res, next) {
  try {
    const result = await listMyJoinRequests(req.user.userId);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function accept(req, res, next) {
  try {
    const result = await acceptJoinRequest(
      req.user.userId,
      req.params.id,
      req.params.requestId
    );
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function decline(req, res, next) {
  try {
    const joinRequest = await declineJoinRequest(
      req.user.userId,
      req.params.id,
      req.params.requestId
    );
    res.status(200).json({ join_request: joinRequest });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  create,
  listForCommunity,
  listMine,
  accept,
  decline,
};
