const express = require('express');
const { startRegister, verifyPhone, login } = require('../controllers/authController');

const router = express.Router();

router.post('/register/start', startRegister);
router.post('/register/verify-phone', verifyPhone);
router.post('/login', login);

module.exports = router;
