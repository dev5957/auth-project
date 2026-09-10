const {
  startLocalRegistration,
  verifyPhoneAndCreateUser,
} = require('../services/registerService');
const { loginLocalUser } = require('../services/loginService');
const { refreshAuthTokens } = require('../services/refreshTokenService');
const { findUserProfileById } = require('../services/userService');

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
    const { access_token, refresh_token, user } = await loginLocalUser(req.body);
    res.status(200).json({
      message: 'Login successful',
      access_token,
      refresh_token,
      user,
    });
  } catch (err) {
    next(err);
  }
}

async function refresh(req, res, next) {
  try {
    const { access_token, refresh_token, user } = await refreshAuthTokens(req.body);
    res.status(200).json({
      message: 'Token refreshed',
      access_token,
      refresh_token,
      user,
    });
  } catch (err) {
    next(err);
  }
}

function me(req, res) {
  res.status(200).json({
    user: {
      userId: req.user.userId,
      login: req.user.login,
      auth_provider: req.user.auth_provider,
    },
  });
}

async function getProfile(req, res, next) {
  try {
    const user = await findUserProfileById(req.user.userId);
    res.status(200).json({ user });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  startRegister,
  verifyPhone,
  login,
  refresh,
  me,
  getProfile,
};
