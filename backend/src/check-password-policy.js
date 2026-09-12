const {
  PASSWORD_MIN_LENGTH,
  PASSWORD_MAX_LENGTH,
  validatePasswordForRegistration,
  preparePasswordForLogin,
} = require('./validators/passwordValidator');
const { startLocalRegistration } = require('./services/registerService');
const { loginLocalUser } = require('./services/loginService');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function expectStatus(fn, statusCode, message) {
  try {
    await fn();
    throw new Error(`expected ${statusCode} ${message}`);
  } catch (err) {
    assert(err.statusCode === statusCode, `expected ${statusCode}, got ${err.statusCode}: ${err.message}`);
    if (message) {
      assert(err.message === message, `unexpected message: ${err.message}`);
    }
  }
}

async function main() {
  const valid = 'abcdefgh';
  assert(validatePasswordForRegistration(valid) === valid, 'A: 8-char password should pass');
  assert(validatePasswordForRegistration('a'.repeat(72)).length === 72, 'A: 72-char password should pass');
  console.log('A OK mot de passe 8–72 caractères accepté');

  await expectStatus(
    () => validatePasswordForRegistration('abcdefg'),
    400,
    'Password must be between 8 and 72 characters'
  );
  console.log('B OK mot de passe < 8 -> 400');

  await expectStatus(
    () => validatePasswordForRegistration('a'.repeat(73)),
    400,
    'Password must be between 8 and 72 characters'
  );
  await expectStatus(() => validatePasswordForRegistration('        '), 400, 'password is required');
  console.log('C OK mot de passe > 72 ou espaces -> 400');

  await expectStatus(
    () => preparePasswordForLogin('a'.repeat(73)),
    401,
    'Invalid credentials'
  );
  assert(preparePasswordForLogin('wrong-password') === 'wrong-password', 'E: login still accepts a normal wrong password');
  console.log('E OK login trop long -> 401 générique ; mauvais mot de passe non rejeté trop tôt');

  const registerBody = {
    email: 'Alex@Example.com',
    birth_date: '1990-01-15',
    login: '  alex  ',
    password: valid,
    password_confirmation: valid,
    phone_number: '  +33600000000  ',
  };

  try {
    await startLocalRegistration(registerBody);
  } catch (err) {
    assert(err.statusCode === 503, `A HTTP-equivalent service: expected 503 after validation, got ${err.statusCode} ${err.message}`);
  }
  console.log('A OK register valide passe la politique (503 seulement si pas de DATABASE_URL)');

  try {
    await loginLocalUser({ login: 'alex', password: valid });
  } catch (err) {
    assert(
      err.statusCode === 503,
      `D: expected 503 after login validation, got ${err.statusCode} ${err.message}`
    );
  }
  console.log('D OK login payload valide passe la politique');

  assert(PASSWORD_MIN_LENGTH === 8 && PASSWORD_MAX_LENGTH === 72, 'limits');
  console.log('Password policy checks succeeded.');
}

main().catch((err) => {
  console.error('Password policy checks failed:', err.message);
  process.exitCode = 1;
});
