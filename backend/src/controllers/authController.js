const {
  startLocalRegistration,
  verifyPhoneAndCreateUser,
} = require('../services/registerService');
const { loginLocalUser } = require('../services/loginService');

async function startRegister(req, res, next) {
  try {
    const { verification_token } = await startLocalRegistration(req.body);
    res.status(201).json({
      message: 'Verification code generated',
      verification_token,
    });
  } catch (err) {
    next(err);
  }
}

async function verifyPhone(req, res, next) {
  try {
    const user = await verifyPhoneAndCreateUser(req.body);
    res.status(201).json({
      message: 'Account created',
      user,
    });
  } catch (err) {
    next(err);
  }
}

async function login(req, res, next) {
  try {
    const user = await loginLocalUser(req.body);
    res.status(200).json({
      message: 'Login successful',
      user,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  startRegister,
  verifyPhone,
  login,
};
