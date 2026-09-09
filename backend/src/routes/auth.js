const express = require('express');
const { startRegister } = require('../controllers/authController');

const router = express.Router();

router.post('/register/start', startRegister);

module.exports = router;
