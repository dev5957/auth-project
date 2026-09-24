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
import 'package:mobile/features/chronique/models/chronique_date.dart';
import 'package:mobile/features/chronique/models/chronique_fields.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/presentation/screens/edit_chronique_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/upcoming_chroniques_screen.dart';
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
  int updateCalls = 0;
  int deleteCalls = 0;
  String? lastAccessToken;
  String? lastListStatus;
  String? lastBody;
  String? lastTitle;
  String? lastPublish;
  String? lastScheduledAt;
  bool? lastIsTimeLimited;
  String? lastExpiresAt;
  int? lastDeleteId;
  List<Chronique> scheduledItems = const [];
  ApiException? failListWith;
  ApiException? failUpdateWith;
  ApiException? failDeleteWith;

  static final sample = Chronique(
    id: 11,
    title: 'Plus tard',
    body: 'Texte programme d au moins vingt caracteres pour la carte.',
    status: 'scheduled',
    scheduledAt: DateTime.parse('2026-09-25T13:00:00.000Z'),
  );

  @override
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    lastListStatus = status;
    final error = failListWith;
    if (error != null) {
      throw error;
    }
    if (status == 'scheduled') {
      return ChroniquePage(items: scheduledItems);
    }
    return const ChroniquePage(items: []);
  }

  @override
  Future<Chronique> get({
    required String accessToken,
    required int id,
  }) async {
    for (final item in scheduledItems) {
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
      status: 'scheduled',
      scheduledAt: scheduledAt == null ? sample.scheduledAt : DateTime.tryParse(scheduledAt),
      isTimeLimited: isTimeLimited ?? false,
      expiresAt: expiresAt == null ? null : DateTime.tryParse(expiresAt),
    );
    scheduledItems = [
      for (final item in scheduledItems)
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
    scheduledItems = [
      for (final item in scheduledItems)
        if (item.id != id) item,
    ];
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

Future<void> _openUpcoming(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('🕒 À venir'));
  await tester.pumpAndSettle();
  expect(find.byType(UpcomingChroniquesScreen), findsOneWidget);
}

void main() {
  testWidgets('À venir navigates from avatar and calls GET status=scheduled', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openUpcoming(tester);

    expect(find.text('À venir'), findsWidgets);
    expect(api.listCalls, 1);
    expect(api.lastListStatus, 'scheduled');
    expect(api.lastAccessToken, 'access-test');
    expect(find.text('Aucune chronique programmée.'), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('À venir lists scheduled chroniques with date title and excerpt', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe()..scheduledItems = [_ChroniqueApiProbe.sample];
    await _pumpHome(tester, api: api);
    await _openUpcoming(tester);

    expect(find.byType(ChroniqueCard), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
    expect(
      find.text(ChroniqueFields.excerpt(_ChroniqueApiProbe.sample.body)),
      findsOneWidget,
    );
    expect(
      find.text(formatOptionalChroniqueDate(_ChroniqueApiProbe.sample.scheduledAt)!),
      findsOneWidget,
    );
    expect(find.text('Aucune chronique programmée.'), findsNothing);
  });

  testWidgets('scheduled card can be edited then PATCH includes schedule fields', (
    tester,
  ) async {
    final api = _ChroniqueApiProbe()..scheduledItems = [_ChroniqueApiProbe.sample];
    await _pumpHome(tester, api: api);
    await _openUpcoming(tester);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
    expect(find.text('Archiver'), findsNothing);

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.byType(EditChroniqueScreen), findsOneWidget);
    expect(find.text('Date de publication'), findsOneWidget);
    expect(find.text('Expiration'), findsOneWidget);

    const nextBody = 'Texte modifié d au moins vingt caracteres.';
    await tester.enterText(find.byType(TextField).at(0), 'Soir prévu');
    await tester.enterText(find.byType(TextField).at(1), nextBody);
    await tester.pump();
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 1);
    expect(api.lastTitle, 'Soir prévu');
    expect(api.lastBody, nextBody);
    expect(api.lastPublish, 'schedule');
    expect(api.lastScheduledAt, contains('Z'));
    expect(find.byType(UpcomingChroniquesScreen), findsOneWidget);
    expect(find.text('Soir prévu'), findsOneWidget);
  });

  testWidgets('scheduled card delete confirms then calls DELETE', (tester) async {
    final api = _ChroniqueApiProbe()..scheduledItems = [_ChroniqueApiProbe.sample];
    final container = await _pumpHome(tester, api: api);
    await _openUpcoming(tester);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette chronique programmée ?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(api.deleteCalls, 1);
    expect(api.lastDeleteId, 11);
    expect(find.text('Aucune chronique programmée.'), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('À venir API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..failListWith = const ApiException(message: 'Too many requests', statusCode: 429);
    final container = await _pumpHome(tester, api: api);
    await _openUpcoming(tester);

    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.byType(UpcomingChroniquesScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('scheduled edit API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..scheduledItems = [_ChroniqueApiProbe.sample]
      ..failUpdateWith = const ApiException(message: 'scheduled_at must be in the future', statusCode: 400);
    final container = await _pumpHome(tester, api: api);
    await _openUpcoming(tester);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(1),
      'Texte modifié d au moins vingt caracteres.',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(api.updateCalls, 1);
    expect(find.text('scheduled_at must be in the future'), findsOneWidget);
    expect(find.byType(EditChroniqueScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });
}
