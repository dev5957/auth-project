import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/router/app_routes.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/models/register_verify_result.dart';
import 'package:mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:mobile/features/auth/presentation/state/register_flow_controller.dart';
import 'package:mobile/features/auth/presentation/state/register_form_data.dart';
import 'package:mobile/features/auth/presentation/state/register_phone.dart';
import 'package:mobile/features/auth/presentation/widgets/register_verify_phone_step.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/state/auth_state.dart';

class _VerifyProbe {
  int calls = 0;
  Object? error;
  Duration delay = Duration.zero;
  String? token;
  String? code;
  RegisterVerifyResult result = const RegisterVerifyResult(
    message: 'Account created',
    user: AuthAccount(
      id: 1,
      login: 'ada',
      authProvider: 'local',
      email: 'ada@example.com',
      phoneVerified: true,
    ),
  );
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this.probe);

  final _VerifyProbe probe;

  @override
  AuthState build() => const AuthUnauthenticated();

  @override
  Future<RegisterVerifyResult> verifyRegisterPhone({
    required String verificationToken,
    required String code,
  }) async {
    probe.calls += 1;
    probe.token = verificationToken;
    probe.code = code;
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

class _SeededVerifyFlow extends RegisterFlowController {
  @override
  RegisterFlowState build() {
    return RegisterFlowState(
      step: RegisterStep.verifyPhone,
      data: RegisterFormData(
        firstName: 'Ada',
        lastName: 'Lovelace',
        birthDate: DateTime(2000, 1, 15),
        login: 'ada',
        email: 'ada@example.com',
        confirmEmail: 'ada@example.com',
        password: 'password1',
        confirmPassword: 'password1',
        phoneNumber: '+15550101234',
        verificationToken: 'verify-token-1',
      ),
    );
  }
}

Finder _otpCell(int index) => find.byKey(ValueKey('otp-cell-$index'));

GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.register,
    routes: [
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('Sign In')),
      ),
    ],
  );
}

Future<void> _pumpRegister(
  WidgetTester tester,
  ProviderContainer container, {
  GoRouter? router,
}) async {
  final goRouter = router;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: goRouter == null
          ? MaterialApp(
              theme: AppTheme.light,
              home: const RegisterScreen(),
            )
          : MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: goRouter,
            ),
    ),
  );
}

Future<void> _enterOtp(WidgetTester tester, String code) async {
  await tester.enterText(_otpCell(0), code);
  await tester.pump();
}

void main() {
  test('masks phone for Verify step', () {
    expect(maskRegisterPhoneNumber('+15550101234'), '+•••••••1234');
  });

  testWidgets('incomplete code is blocked without Auth call', (tester) async {
    final probe = _VerifyProbe();
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededVerifyFlow.new),
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

    await tester.tap(find.text('Verify'));
    await tester.pump();

    expect(find.text('Enter the 6-digit code'), findsOneWidget);
    expect(probe.calls, 0);
    expect(find.text('Step 4 of 4 · Verify'), findsOneWidget);
  });

  testWidgets('valid code calls AuthController.verifyRegisterPhone', (tester) async {
    final probe = _VerifyProbe();
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededVerifyFlow.new),
        authControllerProvider.overrideWith(() => _FakeAuthController(probe)),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRegister(tester, container, router: router);

    await _enterOtp(tester, '123456');
    await tester.tap(find.text('Verify'));
    await tester.pump();

    expect(probe.calls, 1);
    expect(probe.token, 'verify-token-1');
    expect(probe.code, '123456');
    await tester.pump(registerVerifySuccessPause);
    await tester.pumpAndSettle();
  });

  testWidgets('loading prevents double submission', (tester) async {
    final probe = _VerifyProbe()..delay = const Duration(milliseconds: 400);
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededVerifyFlow.new),
        authControllerProvider.overrideWith(() => _FakeAuthController(probe)),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRegister(tester, container, router: router);

    await _enterOtp(tester, '123456');
    final verifyButton = find.descendant(
      of: find.byType(AppButton),
      matching: find.byType(InkWell),
    );
    await tester.tap(verifyButton);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(verifyButton);
    await tester.pump(const Duration(milliseconds: 50));
    expect(probe.calls, 1);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(registerVerifySuccessPause);
    await tester.pumpAndSettle();
  });

  testWidgets('backend error stays on Step 4 and shows the message', (tester) async {
    final probe = _VerifyProbe()
      ..error = const ApiException(
        message: 'Invalid verification code',
        statusCode: 400,
      );
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededVerifyFlow.new),
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

    await _enterOtp(tester, '000000');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4 · Verify'), findsOneWidget);
    expect(find.text('Invalid verification code'), findsOneWidget);
    expect(find.text('Phone verified'), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('success shows confirmation then goes to Sign In', (tester) async {
    final probe = _VerifyProbe();
    final router = GoRouter(
      initialLocation: AppRoutes.register,
      routes: [
        GoRoute(
          path: AppRoutes.register,
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const Scaffold(body: Text('Sign In')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededVerifyFlow.new),
        authControllerProvider.overrideWith(() => _FakeAuthController(probe)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );

    await _enterOtp(tester, '123456');
    await tester.tap(find.text('Verify'));
    await tester.pump();
    expect(find.text('Phone verified'), findsOneWidget);
    expect(find.text('Your phone number has been confirmed.'), findsOneWidget);
    expect(find.text('Your account is ready.'), findsOneWidget);
    expect(find.text('You can now sign in.'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
    expect(find.text('Verify'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Phone verified'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Sign In'), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('back to Phone keeps Personal, Account and Phone data', (tester) async {
    final probe = _VerifyProbe();
    final container = ProviderContainer(
      overrides: [
        registerFlowProvider.overrideWith(_SeededVerifyFlow.new),
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

    expect(find.text('Step 4 of 4 · Verify'), findsOneWidget);
    await tester.tap(find.text('Change phone number'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 · Phone'), findsOneWidget);
    final data = container.read(registerFlowProvider).data;
    expect(data.firstName, 'Ada');
    expect(data.login, 'ada');
    expect(data.phoneNumber, '+15550101234');
    expect(data.verificationToken, 'verify-token-1');
  });
}
