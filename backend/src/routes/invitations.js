const express = require('express');
const {
  listReceived,
  accept,
  decline,
  cancel,
} = require('../controllers/invitationController');
const { requireAuth } = require('../middleware/authMiddleware');
const { createRateLimiter } = require('../middleware/rateLimit');

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;

const invitationRateLimit = {
  write: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 30 }),
  read: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 60 }),
};

const router = express.Router();

router.use(requireAuth);

router.get('/', invitationRateLimit.read, listReceived);
router.post('/:id/accept', invitationRateLimit.write, accept);
router.post('/:id/decline', invitationRateLimit.write, decline);
router.post('/:id/cancel', invitationRateLimit.write, cancel);

module.exports = router;
