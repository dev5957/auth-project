const express = require('express');
const { startRegister, verifyPhone, login, refresh, me } = require('../controllers/authController');
const { authRateLimit } = require('../middleware/rateLimit');
const { requireAuth } = require('../middleware/authMiddleware');

const router = express.Router();

router.post('/register/start', authRateLimit.registerStart, startRegister);
router.post('/register/verify-phone', authRateLimit.verifyPhone, verifyPhone);
router.post('/login', authRateLimit.login, login);
router.post('/refresh', authRateLimit.refresh, refresh);
router.get('/me', requireAuth, me);

module.exports = router;
