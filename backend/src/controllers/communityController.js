const {
  createCommunity,
  listMyCommunities,
  getCommunityById,
  searchCommunities,
  listCommunityMembers,
  updateMemberRole,
  removeMember,
  leaveCommunity,
} = require('../services/communityService');
const {
  createIdentityUpload,
  completeIdentityUpload,
} = require('../services/communityIdentityService');

async function create(req, res, next) {
  try {
    const community = await createCommunity(req.user.userId, req.body);
    res.status(201).json({
      message: 'Community created',
      community,
    });
  } catch (err) {
    next(err);
  }
}

async function list(req, res, next) {
  try {
    const result = await listMyCommunities(req.user.userId, req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function search(req, res, next) {
  try {
    const result = await searchCommunities(req.user.userId, req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function getOne(req, res, next) {
  try {
    const community = await getCommunityById(req.user.userId, req.params.id);
    res.status(200).json({ community });
  } catch (err) {
    next(err);
  }
}

async function listMembers(req, res, next) {
  try {
    const result = await listCommunityMembers(req.user.userId, req.params.id);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function patchMemberRole(req, res, next) {
  try {
    const member = await updateMemberRole(
      req.user.userId,
      req.params.id,
      req.params.userId,
      req.body
    );
    res.status(200).json({ member });
  } catch (err) {
    next(err);
  }
}

async function remove(req, res, next) {
  try {
    const result = await removeMember(
      req.user.userId,
      req.params.id,
      req.params.userId
    );
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function leave(req, res, next) {
  try {
    const result = await leaveCommunity(req.user.userId, req.params.id);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function createAvatarUpload(req, res, next) {
  try {
    const result = await createIdentityUpload(req.user.userId, req.params.id, 'avatar', req.body);
    res.status(201).json(result);
  } catch (err) {
    next(err);
  }
}

async function completeAvatarUpload(req, res, next) {
  try {
    const result = await completeIdentityUpload(req.user.userId, req.params.id, 'avatar', req.body);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function createBannerUpload(req, res, next) {
  try {
    const result = await createIdentityUpload(req.user.userId, req.params.id, 'banner', req.body);
    res.status(201).json(result);
  } catch (err) {
    next(err);
  }
}

async function completeBannerUpload(req, res, next) {
  try {
    const result = await completeIdentityUpload(req.user.userId, req.params.id, 'banner', req.body);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

module.exports = {
  create,
  list,
  search,
  getOne,
  listMembers,
  patchMemberRole,
  remove,
  leave,
  createAvatarUpload,
  completeAvatarUpload,
  createBannerUpload,
  completeBannerUpload,
};
