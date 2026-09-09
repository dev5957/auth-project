const express = require('express');
const { startRegister, verifyPhone, login, refresh } = require('../controllers/authController');

const router = express.Router();

router.post('/register/start', startRegister);
router.post('/register/verify-phone', verifyPhone);
router.post('/login', login);
router.post('/refresh', refresh);

module.exports = router;
