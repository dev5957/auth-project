const express = require('express');
const { listMine } = require('../controllers/joinRequestController');
const { requireAuth } = require('../middleware/authMiddleware');
const { createRateLimiter } = require('../middleware/rateLimit');

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;
const joinRequestRateLimit = createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 60 });

const router = express.Router();

router.use(requireAuth);
router.get('/mine', joinRequestRateLimit, listMine);

module.exports = router;
