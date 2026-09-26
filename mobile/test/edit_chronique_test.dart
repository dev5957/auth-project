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
import 'package:mobile/features/chronique/presentation/screens/chronique_detail_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/edit_chronique_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/mon_fil_screen.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_card.dart';
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

  int listCalls = 0;
  int getCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int archiveCalls = 0;
  String? lastAccessToken;
  String? lastBody;
  String? lastTitle;
  String? lastPublish;
  String? lastScheduledAt;
  bool? lastIsTimeLimited;
  String? lastExpiresAt;
  String? lastListStatus;
  int? lastUpdateId;
  int? lastDeleteId;
  int? lastArchiveId;
  List<Chronique> items = const [];
  List<Chronique> archivedItems = const [];
  ApiException? failUpdateWith;
  ApiException? failDeleteWith;
  ApiException? failArchiveWith;

  static const sample = Chronique(
    id: 42,
    title: 'Premier soir',
    body: 'Le texte de la chronique, d au moins vingt caracteres.',
    status: 'active',
    publishedAt: '2026-09-22T10:00:00.000Z',
  );

  @override
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    lastListStatus = status;
    if (status == 'archived') {
      return ChroniquePage(items: archivedItems);
    }
    return ChroniquePage(items: items);
  }

  @override
  Future<Chronique> get({
    required String accessToken,
    required int id,
  }) async {
    getCalls += 1;
    lastAccessToken = accessToken;
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    throw const ApiException(message: 'Chronique not found', statusCode: 404);
  }

  @override
  Future<Chronique> update({
    required String accessToken,
    required int id,
    required String body,
    String? title,
    String? publish,
    String? scheduledAt,
    bool? isTimeLimited,
    String? expiresAt,
  }) async {
    updateCalls += 1;
    lastAccessToken = accessToken;
    lastUpdateId = id;
    lastBody = body;
    lastTitle = title;
    lastPublish = publish;
    lastScheduledAt = scheduledAt;
    lastIsTimeLimited = isTimeLimited;
    lastExpiresAt = expiresAt;
    final error = failUpdateWith;
    if (error != null) {
      throw error;
    }
    final updated = Chronique(
      id: id,
      title: title,
      body: body,
      status: 'active',
      publishedAt: '2026-09-22T10:00:00.000Z',
    );
    items = [
      for (final item in items)
        if (item.id == id) updated else item,
    ];
    return updated;
  }

  @override
  Future<void> delete({
    required String accessToken,
    required int id,
  }) async {
    deleteCalls += 1;
    lastAccessToken = accessToken;
    lastDeleteId = id;
    final error = failDeleteWith;
    if (error != null) {
      throw error;
    }
    items = [
      for (final item in items)
        if (item.id != id) item,
    ];
  }

  @override
  Future<Chronique> archive({
    required String accessToken,
    required int id,
  }) async {
    archiveCalls += 1;
    lastAccessToken = accessToken;
    lastArchiveId = id;
    final error = failArchiveWith;
    if (error != null) {
      throw error;
    }
    Chronique? source;
    for (final item in items) {
      if (item.id == id) {
        source = item;
        break;
      }
    }
    final archived = Chronique(
      id: id,
      title: source?.title,
      body: source?.body ?? '',
      status: 'archived',
      publishedAt: source?.publishedAt,
      archivedAt: '2026-09-23T15:40:00.000Z',
    );
    items = [
      for (final item in items)
        if (item.id != id) item,
    ];
    archivedItems = [...archivedItems, archived];
    return archived;
  }
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required _ChroniqueApiProbe api,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
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

Future<void> _openDetail(WidgetTester tester, {_ChroniqueApiProbe? api}) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.text('EXPLORE'));
  await tester.pumpAndSettle();
  expect(find.byType(MonFilScreen), findsOneWidget);
  await tester.tap(find.text('Premier soir').first);
  await tester.pumpAndSettle();
  expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
  if (api != null) {
    expect(api.getCalls, greaterThan(0));
  }
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Actions'));
  await tester.pumpAndSettle();
}

Finder _saveInk() {
  return find.descendant(
    of: find.ancestor(
      of: find.text('Enregistrer'),
      matching: find.byType(AppButton),
    ),
    matching: find.byType(InkWell),
  );
}

InkWell _saveInkWell(WidgetTester tester) {
  return tester.widget<InkWell>(_saveInk());
}

void main() {
  testWidgets('edit screen opens prefilled from the published chronique', (tester) async {
    final api = _ChroniqueApiProbe()..items = const [_ChroniqueApiProbe.sample];
    final container = await _pumpHome(tester, api: api);
    await _openDetail(tester, api: api);

    await _openMenu(tester);
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Archiver'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    expect(find.byType(EditChroniqueScreen), findsOneWidget);
    expect(find.text('Modifier la chronique'), findsOneWidget);
    expect(find.text('+ Ajouter un média'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      'Premier soir',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      'Le texte de la chronique, d au moins vingt caracteres.',
    );
    expect(find.text('${_ChroniqueApiProbe.sample.body.trim().runes.length} / 1000'), findsOneWidget);
    expect(_saveInkWell(tester).onTap, isNull);
    expect(api.updateCalls, 0);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('edit validation matches CREATE and does not call PATCH', (tester) async {
    final api = _ChroniqueApiProbe()..items = const [_ChroniqueApiProbe.sample];
    await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.pump();
    expect(find.text('Le texte est obligatoire'), findsOneWidget);
    expect(_saveInkWell(tester).onTap, isNull);

    await tester.enterText(find.byType(TextField).at(1), 'trop court');
    await tester.pump();
    expect(find.text('Le texte doit contenir au moins 10 caractères'), findsOneWidget);
    expect(_saveInkWell(tester).onTap, isNull);

    await tester.enterText(find.byType(TextField).at(1), 'abcdefghij');
    await tester.pump();
    expect(find.text('Le texte doit contenir au moins 10 caractères'), findsNothing);
    expect(find.text('10 / 1000'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'a' * 1001);
    await tester.pump();
    expect(find.text('Le texte est trop long'), findsOneWidget);
    expect(_saveInkWell(tester).onTap, isNull);
    expect(api.updateCalls, 0);
  });

  testWidgets('saving calls PATCH then returns the updated detail', (tester) async {
    final api = _ChroniqueApiProbe()..items = const [_ChroniqueApiProbe.sample];
    final container = await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    const nextBody = 'Texte modifié d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(0), 'Soir deux');
    await tester.enterText(find.byType(TextField).at(1), nextBody);
    await tester.pump();
    expect(_saveInkWell(tester).onTap, isNotNull);

    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 1);
    expect(api.lastAccessToken, 'access-test');
    expect(api.lastUpdateId, 42);
    expect(api.lastTitle, 'Soir deux');
    expect(api.lastBody, nextBody);
    expect(find.byType(EditChroniqueScreen), findsNothing);
    expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
    expect(find.text('Soir deux'), findsWidgets);
    expect(find.text(nextBody), findsWidgets);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(find.text('Soir deux'), findsOneWidget);
    expect(find.text(nextBody), findsOneWidget);
  });

  testWidgets('PATCH error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..items = const [_ChroniqueApiProbe.sample]
      ..failUpdateWith = const ApiException(message: 'body is too short', statusCode: 400);
    final container = await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).at(1),
      'Texte modifié d au moins vingt caracteres.',
    );
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(api.updateCalls, 1);
    expect(find.text('body is too short'), findsOneWidget);
    expect(find.byType(EditChroniqueScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('delete confirms then returns to Mon Fil', (tester) async {
    final api = _ChroniqueApiProbe()..items = const [_ChroniqueApiProbe.sample];
    final container = await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(find.text('Supprimer cette chronique ?'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(api.deleteCalls, 1);
    expect(api.lastDeleteId, 42);
    expect(api.lastAccessToken, 'access-test');
    expect(find.byType(ChroniqueDetailScreen), findsNothing);
    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(find.byType(ChroniqueCard), findsNothing);
    expect(find.text('Aucune chronique pour le moment.'), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('delete cancellation does not call DELETE', (tester) async {
    final api = _ChroniqueApiProbe()..items = const [_ChroniqueApiProbe.sample];
    await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(api.deleteCalls, 0);
    expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
  });

  testWidgets('DELETE error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..items = const [_ChroniqueApiProbe.sample]
      ..failDeleteWith = const ApiException(message: 'Too many requests', statusCode: 429);
    final container = await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pump();

    expect(api.deleteCalls, 1);
    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('archive confirms then returns to Mon Fil without the item', (tester) async {
    final api = _ChroniqueApiProbe()..items = const [_ChroniqueApiProbe.sample];
    final container = await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();

    expect(find.text('Archiver cette chronique ?'), findsOneWidget);
    expect(
      find.text('Elle sera retirée de Mon Fil\nmais conservée dans vos archives.'),
      findsOneWidget,
    );
    expect(find.text('Annuler'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Archiver'));
    await tester.pumpAndSettle();

    expect(api.archiveCalls, 1);
    expect(api.lastArchiveId, 42);
    expect(api.lastAccessToken, 'access-test');
    expect(find.byType(ChroniqueDetailScreen), findsNothing);
    expect(find.byType(MonFilScreen), findsOneWidget);
    expect(find.byType(ChroniqueCard), findsNothing);
    expect(find.text('Aucune chronique pour le moment.'), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('archive API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..items = const [_ChroniqueApiProbe.sample]
      ..failArchiveWith = const ApiException(
        message: 'Chronique cannot be archived in this status',
        statusCode: 400,
      );
    final container = await _pumpHome(tester, api: api);
    await _openDetail(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Archiver'));
    await tester.pump();

    expect(api.archiveCalls, 1);
    expect(find.text('Chronique cannot be archived in this status'), findsOneWidget);
    expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });
}
