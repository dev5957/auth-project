const express = require('express');
const {
  startRegister,
  verifyPhone,
  login,
  refresh,
  me,
  getProfile,
  logout,
  startGoogle,
  startOAuthPhone,
  verifyOAuthPhone,
} = require('../controllers/authController');
const { authRateLimit } = require('../middleware/rateLimit');
const { requireAuth } = require('../middleware/authMiddleware');

const router = express.Router();

router.post('/register/start', authRateLimit.registerStart, startRegister);
router.post('/register/verify-phone', authRateLimit.verifyPhone, verifyPhone);
router.post('/login', authRateLimit.login, login);
router.post('/refresh', authRateLimit.refresh, refresh);
router.get('/me', requireAuth, me);
router.get('/profile', requireAuth, getProfile);
router.post('/logout', requireAuth, logout);
router.post('/google/start', authRateLimit.googleStart, startGoogle);
router.post('/oauth/start-phone', authRateLimit.oauthStartPhone, startOAuthPhone);
router.post('/oauth/verify-phone', authRateLimit.oauthVerifyPhone, verifyOAuthPhone);

module.exports = router;
