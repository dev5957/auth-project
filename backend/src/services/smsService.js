const AppError = require('../errors/AppError');

function readTrimmed(name) {
  const value = process.env[name];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function getTwilioConfig() {
  const accountSid = readTrimmed('TWILIO_ACCOUNT_SID');
  const authToken = readTrimmed('TWILIO_AUTH_TOKEN');
  const from = readTrimmed('TWILIO_PHONE_NUMBER');
  if (!accountSid || !authToken || !from) {
    return null;
  }
  return { accountSid, authToken, from };
}

function isTwilioConfigured() {
  return getTwilioConfig() != null;
}

function getSmsProvider() {
  const raw = readTrimmed('SMS_PROVIDER');
  if (raw == null) {
    return 'twilio';
  }
  return raw.toLowerCase();
}

function maskPhoneNumber(phoneNumber) {
  const value = String(phoneNumber || '');
  if (value.length < 6) {
    return '***';
  }
  return `${value.slice(0, 4)}***${value.slice(-2)}`;
}

function createTwilioClient(config) {
  const twilio = require('twilio');
  return twilio(config.accountSid, config.authToken);
}

async function sendSms(phoneNumber, message, options = {}) {
  if (typeof phoneNumber !== 'string' || phoneNumber.trim() === '') {
    throw new AppError(503, 'SMS could not be sent');
  }
  if (typeof message !== 'string' || message.trim() === '') {
    throw new AppError(503, 'SMS could not be sent');
  }

  const provider = getSmsProvider();
  if (provider === 'mock') {
    return { skipped: false, mocked: true };
  }
  if (provider !== 'twilio') {
    throw new AppError(503, 'SMS could not be sent');
  }

  const config = getTwilioConfig();
  const client = options.client;

  if (!client && !config) {
    return { skipped: true };
  }

  try {
    const twilioClient = client || createTwilioClient(config);
    const from = options.from || (config && config.from);
    if (!from) {
      throw new AppError(503, 'SMS could not be sent');
    }

    await twilioClient.messages.create({
      to: phoneNumber.trim(),
      from,
      body: message,
    });

    return { skipped: false };
  } catch (err) {
    if (err.statusCode) {
      throw err;
    }
    console.error('SMS send failed', err.code || err.name || 'ERROR');
    throw new AppError(503, 'SMS could not be sent');
  }
}

module.exports = {
  sendSms,
  isTwilioConfigured,
  getSmsProvider,
  maskPhoneNumber,
};
