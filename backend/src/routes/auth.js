const express = require('express');
const { startRegister, verifyPhone } = require('../controllers/authController');

const router = express.Router();

router.post('/register/start', startRegister);
router.post('/register/verify-phone', verifyPhone);

module.exports = router;
