import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_session.dart';
import 'package:mobile/features/auth/models/password_reset_result.dart';
import 'package:mobile/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/services/auth_api_service.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class InMemoryAuthTokenStorage implements AuthTokenStorage {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<bool> hasRefreshToken() async {
    return _refreshToken != null && _refreshToken!.isNotEmpty;
  }
}

class _ForgotApi extends AuthApiService {
  _ForgotApi() : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int forgotCalls = 0;
  int resetCalls = 0;
  int loginCalls = 0;
  String? lastPhoneNumber;
  String? lastCode;
  String? lastPassword;
  bool failCode = false;

  @override
  Future<PasswordResetResult> requestPasswordReset({required String phoneNumber}) async {
    forgotCalls += 1;
    lastPhoneNumber = phoneNumber;
    return const PasswordResetResult(
      message: 'If an account exists for this phone number, a reset code has been sent.',
    );
  }

  @override
  Future<PasswordResetResult> confirmPasswordReset({
    required String phoneNumber,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    resetCalls += 1;
    lastPhoneNumber = phoneNumber;
    lastCode = code;
    lastPassword = password;
    if (failCode || code != '123456') {
      throw const ApiException(message: 'Invalid or expired reset code', statusCode: 400);
    }
    return const PasswordResetResult(message: 'Password has been reset. You can sign in.');
  }

  @override
  Future<AuthSession> login({
    required String login,
    required String password,
  }) async {
    loginCalls += 1;
    throw StateError('login should not run during forgot password');
  }
}

Finder get _carousel => find.text('Discover');

Future<ProviderContainer> _openForgot(WidgetTester tester, _ForgotApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(InMemoryAuthTokenStorage()),
        authApiServiceProvider.overrideWithValue(api),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
  await tester.tap(find.text('Forgot password?'));
  await tester.pumpAndSettle();
  expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

void main() {
  testWidgets('Login opens Forgot password without leaving Sign in copy behind', (tester) async {
    await _openForgot(tester, _ForgotApi());
    expect(find.text('Forgot password'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Send reset code'), findsOneWidget);
    expect(_carousel, findsNothing);
  });

  testWidgets('forgot password completes and returns to Login without Home', (tester) async {
    final api = _ForgotApi();
    final container = await _openForgot(tester, api);

    await tester.enterText(find.byType(TextField), '+33 6 12-34-56-78');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();

    expect(api.forgotCalls, 1);
    expect(api.lastPhoneNumber, '+33612345678');
    expect(
      find.text('If an account exists for this phone number, a reset code has been sent.'),
      findsOneWidget,
    );
    expect(find.text('Enter the code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final passwords = find.byType(TextField);
    await tester.enterText(passwords.at(0), 'newpass12');
    await tester.enterText(passwords.at(1), 'newpass12');
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();

    expect(api.resetCalls, 1);
    expect(api.lastCode, '123456');
    expect(api.lastPassword, 'newpass12');
    expect(api.lastPhoneNumber, '+33612345678');
    expect(api.loginCalls, 0);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('local invalid code stays on the code step', (tester) async {
    final api = _ForgotApi();
    await _openForgot(tester, api);

    await tester.enterText(find.byType(TextField), '+33612345678');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the 6-digit code'), findsOneWidget);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(api.resetCalls, 0);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('wrong reset code stays in Forgot password without carousel', (tester) async {
    final api = _ForgotApi()..failCode = true;
    final container = await _openForgot(tester, api);

    await tester.enterText(find.byType(TextField), '+33612345678');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final passwords = find.byType(TextField);
    await tester.enterText(passwords.at(0), 'newpass12');
    await tester.enterText(passwords.at(1), 'newpass12');
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();

    expect(api.resetCalls, 1);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('Invalid or expired reset code'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(_carousel, findsNothing);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });
}
