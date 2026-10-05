const express = require('express');
const { listMyCommentTracesAction } = require('../controllers/communityPublicationController');
const { requireAuth } = require('../middleware/authMiddleware');
const { createRateLimiter } = require('../middleware/rateLimit');

const readLimit = createRateLimiter({ windowMs: 15 * 60 * 1000, max: 60 });
const router = express.Router();
router.use(requireAuth);
router.get('/', readLimit, listMyCommentTracesAction);
module.exports = router;
