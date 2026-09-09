const { startLocalRegistration } = require('../services/registerService');

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

module.exports = {
  startRegister,
};
