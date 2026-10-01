const express = require('express');
const {
  create,
  list,
  search,
  getOne,
  listMembers,
  patchMemberRole,
} = require('../controllers/communityController');
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
router.get('/:id', communityRateLimit.read, getOne);

module.exports = router;
