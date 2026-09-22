const express = require('express');
const { create, list, getOne } = require('../controllers/chroniqueController');
const { requireAuth } = require('../middleware/authMiddleware');
const { createRateLimiter } = require('../middleware/rateLimit');

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;

const chroniqueRateLimit = {
  write: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 30 }),
  read: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 60 }),
};

const router = express.Router();

router.use(requireAuth);

router.post('/', chroniqueRateLimit.write, create);
router.get('/', chroniqueRateLimit.read, list);
router.get('/:id', chroniqueRateLimit.read, getOne);

module.exports = router;
