import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/models/media_draft.dart';
import 'package:mobile/features/chronique/presentation/screens/create_chronique_screen.dart';
import 'package:mobile/features/chronique/presentation/state/create_chronique_controller.dart';
import 'package:mobile/features/chronique/presentation/widgets/media_draft_list.dart';
import 'package:mobile/features/chronique/presentation/screens/mon_fil_screen.dart';
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
  int listCalls = 0;
  String? lastAccessToken;
  String? lastBody;
  String? lastTitle;
  ApiException? failWith;
  List<Chronique> listItems = const [];

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

  @override
  Future<ChroniquePage> list({required String accessToken}) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    return ChroniquePage(items: listItems);
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

Finder _publishInk() {
  return find.descendant(
    of: find.ancestor(
      of: find.text('Publier'),
      matching: find.byType(AppButton),
    ),
    matching: find.byType(InkWell),
  );
}

InkWell _publishInkWell(WidgetTester tester) {
  return tester.widget<InkWell>(_publishInk());
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
    expect(find.text('0 / 5000'), findsOneWidget);
    expect(find.text('+ Ajouter un média'), findsOneWidget);
    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(_publishInkWell(tester).onTap, isNull);
    expect(find.byType(CloseButton), findsOneWidget);
    expect(find.text('Chapitre'), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(api.createCalls, 0);
  });

  testWidgets('empty body shows a local error and does not call the API', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(find.byType(TextField).at(1), 'x');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.pump();

    expect(find.text('Le texte est obligatoire'), findsOneWidget);
    expect(_publishInkWell(tester).onTap, isNull);
    expect(api.createCalls, 0);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
  });

  testWidgets('body shorter than 20 characters does not call the API', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(find.byType(TextField).at(1), 'trop court');
    await tester.pump();

    expect(find.text('Le texte doit contenir au moins 20 caractères'), findsOneWidget);
    expect(find.text('10 / 5000'), findsOneWidget);
    expect(_publishInkWell(tester).onTap, isNull);
    await tester.tap(find.text('Publier'));
    await tester.pump();
    expect(api.createCalls, 0);
  });

  testWidgets('body longer than 5000 characters does not call the API', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    final tooLong = 'a' * 5001;
    await tester.enterText(find.byType(TextField).at(1), tooLong);
    await tester.pump();

    expect(find.text('Le texte est trop long'), findsOneWidget);
    expect(find.text('5001 / 5000'), findsOneWidget);
    expect(_publishInkWell(tester).onTap, isNull);
    expect(api.createCalls, 0);
  });

  testWidgets('character counter updates and Publier becomes enabled', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    expect(find.text('0 / 5000'), findsOneWidget);
    expect(_publishInkWell(tester).onTap, isNull);

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();

    expect(find.text('${body.trim().runes.length} / 5000'), findsOneWidget);
    expect(_publishInkWell(tester).onTap, isNotNull);
    expect(api.createCalls, 0);
  });

  testWidgets('publish opens Mon Fil then back returns to Home without logout', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(0), 'Premier soir');
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastAccessToken, 'access-test');
    expect(api.lastTitle, 'Premier soir');
    expect(api.lastBody, body);
    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(find.text('Mon Fil'), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(api.listCalls, 1);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.byType(MonFilScreen), findsNothing);
    expect(find.byType(CreateChroniqueScreen), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..failWith = const ApiException(message: 'body is too short', statusCode: 400);
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.enterText(
      find.byType(TextField).at(1),
      'Le texte de la chronique, d au moins vingt caracteres.',
    );
    await tester.pump();
    await tester.tap(find.text('Publier'));
    await tester.pump();

    expect(api.createCalls, 1);
    expect(find.text('body is too short'), findsOneWidget);
    expect(find.byType(CreateChroniqueScreen), findsOneWidget);
    expect(find.byType(MonFilScreen), findsNothing);
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

  testWidgets('local media can be added and removed without API calls', (tester) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();

    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Vidéo'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);

    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();

    expect(find.text('Fonction disponible prochainement'), findsOneWidget);
    expect(find.text('Aucun média ajouté'), findsNothing);
    expect(find.byType(MediaDraftList), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Sans nom'), findsOneWidget);
    expect(container.read(createChroniqueControllerProvider).medias, hasLength(1));
    expect(
      container.read(createChroniqueControllerProvider).medias.single.kind,
      MediaDraftKind.image,
    );
    expect(api.createCalls, 0);

    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pump();

    expect(find.text('Aucun média ajouté'), findsOneWidget);
    expect(find.byType(MediaDraftList), findsNothing);
    expect(container.read(createChroniqueControllerProvider).medias, isEmpty);
    expect(api.createCalls, 0);
  });

  testWidgets('publish still sends text only after a local media draft', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await _openCreate(tester);

    await tester.ensureVisible(find.text('+ Ajouter un média'));
    await tester.tap(find.text('+ Ajouter un média'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();

    const body = 'Le texte de la chronique, d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(1), body);
    await tester.pump();
    await tester.ensureVisible(find.text('Publier'));
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastBody, body);
    expect(api.lastTitle, isNull);
    expect(find.byType(MonFilScreen), findsOneWidget);
  });
}
