const smsService = require('./services/smsService');
const { startLocalRegistration } = require('./services/registerService');
const pool = require('./db');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function captureLogs(fn) {
  const logs = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args) => {
    logs.push(args.map(String).join(' '));
  };
  console.error = (...args) => {
    logs.push(args.map(String).join(' '));
  };
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      console.log = originalLog;
      console.error = originalError;
    })
    .then((result) => ({ result, logs: logs.join('\n') }));
}

function assertLogsSafe(logs, extraForbidden = []) {
  const combined = String(logs);
  const forbidden = [
    'TWILIO_AUTH_TOKEN',
    'test-twilio-auth-token',
    'SK_should_never_appear',
    ...extraForbidden,
  ];
  for (const secret of forbidden) {
    assert(!combined.includes(secret), `logs leaked secret: ${secret}`);
  }
}

async function main() {
  const previous = {
    TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID,
    TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN,
    TWILIO_PHONE_NUMBER: process.env.TWILIO_PHONE_NUMBER,
    DEV_LOG_SMS_CODE: process.env.DEV_LOG_SMS_CODE,
    SMS_PROVIDER: process.env.SMS_PROVIDER,
    DATABASE_URL: process.env.DATABASE_URL,
  };

  delete process.env.TWILIO_ACCOUNT_SID;
  delete process.env.TWILIO_AUTH_TOKEN;
  delete process.env.TWILIO_PHONE_NUMBER;
  delete process.env.SMS_PROVIDER;
  process.env.DEV_LOG_SMS_CODE = 'false';

  assert(smsService.isTwilioConfigured() === false, 'Twilio should be off without env');

  const skipped = await captureLogs(() => smsService.sendSms('+33612345678', 'Your verification code is 123456'));
  assert(skipped.result && skipped.result.skipped === true, 'without Twilio config, SMS should be skipped');
  assertLogsSafe(skipped.logs, ['+33612345678', '123456']);
  console.log('OK sans Twilio: envoi ignoré, pas de SMS réel');

  process.env.SMS_PROVIDER = 'mock';
  process.env.TWILIO_ACCOUNT_SID = 'ACtestaccountsidnotreal0000000000';
  process.env.TWILIO_AUTH_TOKEN = 'SK_should_never_appear';
  process.env.TWILIO_PHONE_NUMBER = '+15550000000';

  const mockProviderCalls = [];
  const mockProviderClient = {
    messages: {
      create: async (payload) => {
        mockProviderCalls.push(payload);
        return { sid: 'SM_should_not_be_used' };
      },
    },
  };
  const mocked = await captureLogs(() =>
    smsService.sendSms('+33612345678', 'Your verification code is 999111', {
      client: mockProviderClient,
    })
  );
  assert(smsService.getSmsProvider() === 'mock', 'SMS_PROVIDER=mock');
  assert(mocked.result && mocked.result.mocked === true, 'mock provider should simulate success');
  assert(mocked.result.skipped === false, 'mock provider is a successful send, not a skip');
  assert(mockProviderCalls.length === 0, 'mock provider must not call Twilio');
  assertLogsSafe(mocked.logs, [
    '+33612345678',
    '999111',
    'SK_should_never_appear',
    'ACtestaccountsidnotreal0000000000',
  ]);
  console.log('OK SMS_PROVIDER=mock: succes simule, aucun appel Twilio');

  process.env.SMS_PROVIDER = 'twilio';
  process.env.TWILIO_ACCOUNT_SID = 'ACtestaccountsidnotreal0000000000';
  process.env.TWILIO_AUTH_TOKEN = 'SK_should_never_appear';
  process.env.TWILIO_PHONE_NUMBER = '+15550000000';
  assert(smsService.isTwilioConfigured() === true, 'Twilio should be on with env');

  const calls = [];
  const mockClient = {
    messages: {
      create: async (payload) => {
        calls.push(payload);
        return { sid: 'SM_mock' };
      },
    },
  };

  const sent = await captureLogs(() =>
    smsService.sendSms('+33612345678', 'Your verification code is 654321', { client: mockClient })
  );
  assert(sent.result && sent.result.skipped === false, 'mocked send should not skip');
  assert(sent.result.mocked !== true, 'twilio provider must not report mocked');
  assert(smsService.getSmsProvider() === 'twilio', 'SMS_PROVIDER=twilio');
  assert(calls.length === 1, 'mock client should be called once');
  assert(calls[0].to === '+33612345678', 'mock to');
  assert(calls[0].from === '+15550000000', 'mock from');
  assert(calls[0].body.includes('654321'), 'mock body has code');
  assertLogsSafe(sent.logs, ['+33612345678', '654321', 'ACtestaccountsidnotreal0000000000']);
  assert(smsService.maskPhoneNumber('+33612345678') !== '+33612345678', 'mask must hide the full number');
  console.log('OK SMS_PROVIDER=twilio: client Twilio mocke, aucun SMS reel');

  const failing = {
    messages: {
      create: async () => {
        const err = new Error('Twilio exploded with +33612345678 and SK_should_never_appear');
        err.code = 21211;
        throw err;
      },
    },
  };
  const failed = await captureLogs(async () => {
    try {
      await smsService.sendSms('+33612345678', 'Your verification code is 000000', { client: failing });
      throw new Error('expected SMS failure');
    } catch (err) {
      assert(err.statusCode === 503, `expected 503, got ${err.statusCode}`);
      assert(err.message === 'SMS could not be sent', `unexpected client message: ${err.message}`);
    }
  });
  assertLogsSafe(failed.logs, ['+33612345678', '000000']);
  assert(!failed.logs.includes('Twilio exploded'), 'Twilio error body must not be logged');
  console.log('OK erreur Twilio: 503 générique, pas de secret ni numéro complet dans les logs');

  const originalSend = smsService.sendSms;
  let registerCalledSms = false;
  smsService.sendSms = async () => {
    registerCalledSms = true;
    return { skipped: true };
  };

  const originalQuery = pool.query;
  process.env.DATABASE_URL = previous.DATABASE_URL || 'postgres://sms-service-test/local';
  delete process.env.TWILIO_ACCOUNT_SID;
  delete process.env.TWILIO_AUTH_TOKEN;
  delete process.env.TWILIO_PHONE_NUMBER;

  try {
    pool.query = async (sql) => {
      const key = String(sql).replace(/\s+/g, ' ').toUpperCase();
      if (key.includes('EXISTS') && key.includes('FROM USERS')) {
        return { rows: [{ email_taken: false, login_taken: false, phone_taken: false }], rowCount: 1 };
      }
      if (key.includes('INSERT INTO PHONE_VERIFICATIONS')) {
        return { rows: [], rowCount: 1 };
      }
      throw new Error(`unexpected query: ${sql}`);
    };

    await startLocalRegistration({
      email: 'sms@example.com',
      birth_date: '1990-01-15',
      login: 'sms_user',
      password: 'abcdefgh',
      password_confirmation: 'abcdefgh',
      phone_number: '+33600000000',
    });
    assert(registerCalledSms, 'register/start should call smsService.sendSms after insert');
    console.log('OK register/start appelle sendSms après stockage du hash');
  } finally {
    smsService.sendSms = originalSend;
    pool.query = originalQuery;
  }

  Object.entries(previous).forEach(([key, value]) => {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  });

  console.log('SMS service checks succeeded.');
}

main().catch((err) => {
  console.error('SMS service checks failed:', err.message);
  process.exitCode = 1;
});
