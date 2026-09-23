import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/presentation/screens/create_chronique_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/explore_placeholder_screen.dart';
import 'package:mobile/features/chronique/providers/chronique_providers.dart';
import 'package:mobile/features/chronique/services/chronique_api_service.dart';
import 'package:mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

class InMemoryAuthTokenStorage implements AuthTokenStorage {
  InMemoryAuthTokenStorage({
    String? accessToken,
    String? refreshToken,
  })  : _accessToken = accessToken,
        _refreshToken = refreshToken;

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

class _SeededHomeAuthController extends AuthController {
  @override
  AuthState build() {
    return const AuthAuthenticated(
      user: AuthAccount(
        id: 1,
        login: 'tgjjk',
        authProvider: 'local',
        email: 'ada@example.com',
        phoneVerified: true,
      ),
    );
  }
}

class _ChroniqueApiProbe extends ChroniqueApiService {
  _ChroniqueApiProbe()
      : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  int createCalls = 0;
  String? lastAccessToken;
  String? lastBody;
  String? lastTitle;
  ApiException? failWith;

  @override
  Future<Chronique> create({
    required String accessToken,
    required String body,
    String? title,
  }) async {
    createCalls += 1;
    lastAccessToken = accessToken;
    lastBody = body;
    lastTitle = title;
    final error = failWith;
    if (error != null) {
      throw error;
    }
    return Chronique(
      id: 42,
      title: title,
      body: body,
      status: 'active',
      publishedAt: '2026-09-23T12:00:00.000Z',
    );
  }
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required _ChroniqueApiProbe api,
  AuthTokenStorage? storage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          storage ??
              InMemoryAuthTokenStorage(
                accessToken: 'access-test',
                refreshToken: 'refresh-test',
              ),
        ),
        authControllerProvider.overrideWith(() => _SeededHomeAuthController()),
        chroniqueApiServiceProvider.overrideWithValue(api),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(LuminaApp)));
}

Future<void> _openCreate(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.text('CREATE'));
  await tester.pumpAndSettle();
  expect(find.byType(CreateChroniqueScreen), findsOneWidget);
}

void main() {
  test('chronique JSON maps public fields without user_id', () {
    final chronique = Chronique.fromJson({
      'id': '42',
      'theme_id': null,
      'title': 'Premier soir',
      'body': 'Le texte de la chronique, d au moins vingt caracteres.',
      'status': 'active',
      'published_at': '2026-09-22T10:00:00.000Z',
      'created_at': '2026-09-22T09:50:00.000Z',
      'updated_at': '2026-09-22T10:00:00.000Z',
    });
    expect(chronique.id, 42);
    expect(chronique.title, 'Premier soir');
    expect(chronique.status, 'active');
  });

  testWidgets('authenticated user opens CREATE as a full-screen create assistant', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    expect(find.text('Créer une chronique'), findsOneWidget);
    expect(find.text('Nouvelle chronique'), findsOneWidget);
    expect(find.text('Titre (optionnel)'), findsOneWidget);
    expect(find.text('Texte *'), findsOneWidget);
    expect(find.text('Publier'), findsOneWidget);
    expect(find.byType(CloseButton), findsOneWidget);
    expect(find.text('Chapitre'), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(api.createCalls, 0);
  });

  testWidgets('empty body shows a local error and does not call the API', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.tap(find.text('Publier'));
    await tester.pump();

    expect(find.text('Le texte est obligatoire'), findsOneWidget);
    expect(api.createCalls, 0);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
  });

  testWidgets('publish calls the Chronique service then opens /explore', (tester) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(0), 'Premier soir');
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastAccessToken, 'access-test');
    expect(api.lastTitle, 'Premier soir');
    expect(api.lastBody, body);
    expect(find.byType(ExplorePlaceholderScreen), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..failWith = const ApiException(message: 'body is too short', statusCode: 400);
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(
      find.byType(TextField).at(1),
      'trop court',
    );
    await tester.tap(find.text('Publier'));
    await tester.pump();

    expect(api.createCalls, 1);
    expect(find.text('body is too short'), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
    expect(find.byType(ExplorePlaceholderScreen), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('close returns to Home V1 without publishing', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(find.text('Logout'), findsOneWidget);
    expect(api.createCalls, 0);
  });
}
