const express = require('express');
const { startRegister, verifyPhone, login, refresh } = require('../controllers/authController');
const { authRateLimit } = require('../middleware/rateLimit');

const router = express.Router();

router.post('/register/start', authRateLimit.registerStart, startRegister);
router.post('/register/verify-phone', authRateLimit.verifyPhone, verifyPhone);
router.post('/login', authRateLimit.login, login);
router.post('/refresh', authRateLimit.refresh, refresh);

module.exports = router;
