const express = require('express');
const { listMineAction, getMineAction } = require('../controllers/communityPublicationController');
const { requireAuth } = require('../middleware/authMiddleware');
const { createRateLimiter } = require('../middleware/rateLimit');

const readLimit = createRateLimiter({ windowMs: 15 * 60 * 1000, max: 60 });
const router = express.Router();
router.use(requireAuth);
router.get('/', readLimit, listMineAction);
router.get('/:publicationId', readLimit, getMineAction);
module.exports = router;
