import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/models/register_start_result.dart';
import 'package:mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:mobile/features/auth/presentation/state/register_flow_controller.dart';
import 'package:mobile/features/auth/presentation/state/register_form_data.dart';
import 'package:mobile/features/auth/presentation/state/register_phone.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/state/auth_state.dart';

class _StartRegisterProbe {
  int calls = 0;
  Object? error;
  Duration delay = Duration.zero;
  RegisterStartResult result = const RegisterStartResult(
    message: 'Verification code generated',
    verificationToken: 'verify-token-1',
  );
  String? email;
  String? login;
  String? phoneNumber;
  String? birthDate;
  String? password;
  String? passwordConfirmation;
  String? firstName;
  String? lastName;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this.probe);

  final _StartRegisterProbe probe;

  @override
  AuthState build() => const AuthUnauthenticated();

  @override
  Future<RegisterStartResult> startRegister({
    required String email,
    required String login,
    required String phoneNumber,
    required String birthDate,
    required String password,
    required String passwordConfirmation,
    String? firstName,
    String? lastName,
  }) async {
    probe.calls += 1;
    probe.email = email;
    probe.login = login;
    probe.phoneNumber = phoneNumber;
    probe.birthDate = birthDate;
    probe.password = password;
    probe.passwordConfirmation = passwordConfirmation;
    probe.firstName = firstName;
    probe.lastName = lastName;
    if (probe.delay > Duration.zero) {
      await Future<void>.delayed(probe.delay);
    }
    final error = probe.error;
    if (error != null) {
      throw error;
    }
    return probe.result;
  }
}

class _SeededPhoneFlow extends RegisterFlowController {
  @override
  RegisterFlowState build() {
    return RegisterFlowState(
      step: RegisterStep.phone,
      data: RegisterFormData(
        firstName: 'Ada',
        lastName: 'Lovelace',
        birthDate: DateTime(2000, 1, 15),
        login: 'ada',
        email: 'ada@example.com',
        confirmEmail: 'ada@example.com',
        password: 'password1',
        confirmPassword: 'password1',
        phoneNumber: '+1 (555) 010-1234',
      ),
    );
  }
}

InkWell _sendCodeButton(WidgetTester tester) {
  return tester.widget<InkWell>(
    find.ancestor(
      of: find.text('Send code'),
      matching: find.byType(InkWell),
    ),
  );
}

void main() {
  test('normalizes phone like the backend contract', () {
    expect(normalizeRegisterPhoneNumber('  +1 (555) 010-1234  '), '+15550101234');
    expect(validateRegisterPhoneNumber(''), 'Phone number is required');
    expect(validateRegisterPhoneNumber('   -()  '), 'Phone number is required');
    expect(
      validateRegisterPhoneNumber('1' * 33),
      'phone_number is invalid',
    );
    expect(validateRegisterPhoneNumber('+15550101234'), isNull);
  });

  test('phone data and verification token survive back to Account', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final flow = container.read(registerFlowProvider.notifier);

    flow.savePersonal(
      firstName: 'Ada',
      lastName: 'Lovelace',
      birthDate: DateTime(2000, 1, 15),
    );
    flow.goToNextStep();
    flow.saveAccount(
      login: 'ada',
      email: 'ada@example.com',
      confirmEmail: 'ada@example.com',
      password: 'password1',
      confirmPassword: 'password1',
    );
    flow.goToNextStep();
    flow.savePhone(phoneNumber: '+15550101234');
    flow.saveVerificationToken('verify-token-1');

    flow.goToPreviousStep();
    final afterBack = container.read(registerFlowProvider);
    expect(afterBack.step, RegisterStep.account);
    expect(afterBack.data.login, 'ada');
    expect(afterBack.data.phoneNumber, '+15550101234');
    expect(afterBack.data.verificationToken, 'verify-token-1');

    flow.goToNextStep();
    expect(container.read(registerFlowProvider).step, RegisterStep.phone);
    expect(container.read(registerFlowProvider).data.phoneNumber, '+15550101234');
  });

  testWidgets('Personal + Account Continue opens Phone', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RegisterScreen(),
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'First name'), 'Ada');
    await tester.tap(find.byTooltip('Choose date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Choose a login'), 'ada');
    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, '8–72 characters'), 'password1');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your password'), 'password1');
    await tester.pump();
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 · Phone'), findsOneWidget);
    expect(find.text('Verify your phone'), findsOneWidget);
    expect(find.text('Phone number *'), findsOneWidget);
    expect(_sendCodeButton(tester).onTap, isNull);

    await tester.enterText(find.widgetWithText(TextField, '+15551234567'), '+1 (555) 010-1234');
    await tester.pump();
    expect(_sendCodeButton(tester).onTap, isNotNull);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 · Account'), findsOneWidget);
    expect(find.text('ada'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4 · Phone'), findsOneWidget);
    expect(find.text('+1 (555) 010-1234'), findsOneWidget);
  });

  testWidgets('Send code stores verificationToken and does not authenticate', (tester) async {
    final probe = _StartRegisterProbe();
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededPhoneFlow.new),
        authControllerProvider.overrideWith(() => _FakeAuthController(probe)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RegisterScreen(),
        ),
      ),
    );

    expect(find.text('Step 3 of 4 · Phone'), findsOneWidget);
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(probe.calls, 1);
    expect(probe.phoneNumber, '+15550101234');
    expect(probe.email, 'ada@example.com');
    expect(probe.login, 'ada');
    expect(probe.birthDate, '2000-01-15');
    expect(probe.password, 'password1');
    expect(probe.passwordConfirmation, 'password1');
    expect(probe.firstName, 'Ada');
    expect(probe.lastName, 'Lovelace');

    expect(find.text('Step 4 of 4 · Verify'), findsOneWidget);
    expect(container.read(registerFlowProvider).data.verificationToken, 'verify-token-1');
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('startRegister 409 stays on Phone and keeps the number', (tester) async {
    final probe = _StartRegisterProbe()
      ..error = const ApiException(
        message: 'Phone number is already in use',
        statusCode: 409,
      );
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededPhoneFlow.new),
        authControllerProvider.overrideWith(() => _FakeAuthController(probe)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RegisterScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 · Phone'), findsOneWidget);
    expect(find.text('Phone number is already in use'), findsOneWidget);
    expect(find.text('+1 (555) 010-1234'), findsOneWidget);
    expect(container.read(registerFlowProvider).data.verificationToken, isNull);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('startRegister 400 and 429 show backend errors on Phone', (tester) async {
    final probe = _StartRegisterProbe()
      ..error = const ApiException(message: 'login is invalid', statusCode: 400);
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededPhoneFlow.new),
        authControllerProvider.overrideWith(() => _FakeAuthController(probe)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RegisterScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('login is invalid'), findsOneWidget);
    expect(find.text('Step 3 of 4 · Phone'), findsOneWidget);

    probe.error = const ApiException(message: 'Too many requests', statusCode: 429);
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.text('Step 3 of 4 · Phone'), findsOneWidget);
  });
}
