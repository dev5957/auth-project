const express = require('express');
const { search } = require('../controllers/userSearchController');
const { requireAuth } = require('../middleware/authMiddleware');
const { userSearchRateLimit } = require('../middleware/rateLimit');

const router = express.Router();

router.use(requireAuth);
router.get('/search', userSearchRateLimit, search);

module.exports = router;
