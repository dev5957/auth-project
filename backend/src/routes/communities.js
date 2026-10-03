const express = require('express');
const {
  create,
  list,
  search,
  getOne,
  listMembers,
  patchMemberRole,
  remove,
  leave,
} = require('../controllers/communityController');
const {
  create: createInvitation,
  listSent: listSentInvitations,
} = require('../controllers/invitationController');
const {
  create: createJoinRequest,
  listForCommunity: listCommunityJoinRequests,
  accept: acceptJoinRequest,
  decline: declineJoinRequest,
} = require('../controllers/joinRequestController');
const { requireAuth } = require('../middleware/authMiddleware');
const { createRateLimiter } = require('../middleware/rateLimit');

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;

const communityRateLimit = {
  write: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 30 }),
  read: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 60 }),
};

const router = express.Router();

router.use(requireAuth);

router.post('/', communityRateLimit.write, create);
router.get('/', communityRateLimit.read, list);
router.get('/search', communityRateLimit.read, search);
router.get('/:id/members', communityRateLimit.read, listMembers);
router.patch('/:id/members/:userId', communityRateLimit.write, patchMemberRole);
router.delete('/:id/members/:userId', communityRateLimit.write, remove);
router.post('/:id/leave', communityRateLimit.write, leave);
router.get('/:id/invitations', communityRateLimit.read, listSentInvitations);
router.post('/:id/invitations', communityRateLimit.write, createInvitation);
router.get('/:id/join-requests', communityRateLimit.read, listCommunityJoinRequests);
router.post('/:id/join-requests', communityRateLimit.write, createJoinRequest);
router.post('/:id/join-requests/:requestId/accept', communityRateLimit.write, acceptJoinRequest);
router.post('/:id/join-requests/:requestId/decline', communityRateLimit.write, declineJoinRequest);
router.get('/:id', communityRateLimit.read, getOne);

module.exports = router;
