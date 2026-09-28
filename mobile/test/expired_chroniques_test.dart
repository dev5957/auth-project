import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/widgets/app_loading.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/chronique/models/chronique.dart';
import 'package:mobile/features/chronique/models/chronique_date.dart';
import 'package:mobile/features/chronique/models/chronique_page.dart';
import 'package:mobile/features/chronique/presentation/screens/archives_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/chronique_detail_screen.dart';
import 'package:mobile/features/chronique/presentation/screens/expired_chroniques_screen.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_card.dart';
import 'package:mobile/features/chronique/presentation/widgets/chronique_media_viewer.dart';
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
  String? lastAccessToken;
  String? lastListStatus;
  List<Chronique> archivedItems = const [];
  List<Chronique> expiredItems = const [];
  List<Chronique> activeItems = const [];
  final Map<int, Chronique> byId = {};
  ApiException? failWith;
  ApiException? failGetWith;

  @override
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    lastListStatus = status;
    final error = failWith;
    if (error != null) {
      throw error;
    }
    if (status == 'archived') {
      return ChroniquePage(items: archivedItems);
    }
    if (status == 'expired') {
      return ChroniquePage(items: expiredItems);
    }
    if (status == 'active' || status == null) {
      return ChroniquePage(items: activeItems);
    }
    return const ChroniquePage(items: []);
  }

  @override
  Future<Chronique> get({
    required String accessToken,
    required int id,
  }) async {
    getCalls += 1;
    lastAccessToken = accessToken;
    final error = failGetWith;
    if (error != null) {
      throw error;
    }
    final found = byId[id];
    if (found != null) {
      return found;
    }
    throw const ApiException(message: 'Chronique not found', statusCode: 404);
  }
}

class _DelayedExpiredApi extends _ChroniqueApiProbe {
  final Completer<ChroniquePage> _list = Completer<ChroniquePage>();

  @override
  Future<ChroniquePage> list({
    required String accessToken,
    String? status,
  }) {
    listCalls += 1;
    lastAccessToken = accessToken;
    lastListStatus = status;
    return _list.future;
  }

  void completeEmpty() {
    _list.complete(const ChroniquePage(items: []));
  }
}

Chronique _expired({
  int id = 11,
  DateTime? expiredAt,
  DateTime? purgeAfter,
  List<ChroniqueMedia> media = const [],
}) {
  final expired = expiredAt ?? DateTime.now().subtract(const Duration(days: 3));
  return Chronique(
    id: id,
    title: 'Soir éphémère',
    body: 'Texte de la chronique expiree pour les tests.',
    status: 'expired',
    publishedAt: '2026-09-20T08:00:00.000Z',
    isTimeLimited: true,
    expiredAt: expired,
    purgeAfter: purgeAfter ?? DateTime.now().add(const Duration(days: 12, hours: 3)),
    media: media,
  );
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

Future<void> _openExpired(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
  await tester.pumpAndSettle();
  expect(find.text('Archives'), findsOneWidget);
  expect(find.text('Chroniques expirées'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('home-expired-chroniques')));
  await tester.pumpAndSettle();
  expect(find.byType(ExpiredChroniquesScreen), findsOneWidget);
}

Future<void> _openArchives(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Archives'));
  await tester.pumpAndSettle();
  expect(find.byType(ArchivesScreen), findsOneWidget);
}

void main() {
  testWidgets('menu exposes Chroniques expirées separately from Archives', (tester) async {
    final api = _ChroniqueApiProbe();
    await _pumpHome(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();

    expect(find.text('Archives'), findsOneWidget);
    expect(find.text('Chroniques expirées'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-expired-chroniques')), findsOneWidget);
    expect(find.byType(ExpiredChroniquesScreen), findsNothing);
    expect(find.byType(ArchivesScreen), findsNothing);
  });

  testWidgets('Chroniques expirées navigates and calls GET status=expired', (tester) async {
    final api = _ChroniqueApiProbe();
    final container = await _pumpHome(tester, api: api);
    await _openExpired(tester);

    expect(find.text('Chroniques expirées'), findsWidgets);
    expect(api.listCalls, 1);
    expect(api.lastListStatus, 'expired');
    expect(api.lastAccessToken, 'access-test');
    expect(find.text('Aucune chronique expirée.'), findsOneWidget);
    expect(find.text('Aucune chronique archivée.'), findsNothing);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('expired list shows remaining deletion delay', (tester) async {
    final item = _expired();
    final remaining = chroniqueDefinitiveDeletionLabel(item)!;
    final api = _ChroniqueApiProbe()..expiredItems = [item];
    await _pumpHome(tester, api: api);
    await _openExpired(tester);

    expect(find.byType(ChroniqueCard), findsOneWidget);
    expect(find.text('Soir éphémère'), findsOneWidget);
    expect(find.text('Texte de la chronique expiree pour les tests.'), findsOneWidget);
    expect(find.text('Expirée'), findsOneWidget);
    expect(find.text(remaining), findsOneWidget);
    expect(remaining, startsWith('Suppression définitive dans'));
    expect(find.text('Restaurer'), findsNothing);
    expect(find.byTooltip('Actions'), findsNothing);
    expect(find.byKey(const ValueKey('chronique-share')), findsNothing);
  });

  testWidgets('expired list shows loading then empty state', (tester) async {
    final api = _DelayedExpiredApi();
    await _pumpHome(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('home-user-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-expired-chroniques')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ExpiredChroniquesScreen), findsOneWidget);
    expect(find.byType(AppLoading), findsOneWidget);

    api.completeEmpty();
    await tester.pumpAndSettle();
    expect(find.text('Aucune chronique expirée.'), findsOneWidget);
  });

  testWidgets('expired list API error is shown without logout', (tester) async {
    final api = _ChroniqueApiProbe()
      ..failWith = const ApiException(message: 'Too many requests', statusCode: 429);
    final container = await _pumpHome(tester, api: api);
    await _openExpired(tester);

    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.byType(ExpiredChroniquesScreen), findsOneWidget);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('opening an expired card shows detail without restore', (tester) async {
    final item = _expired();
    final api = _ChroniqueApiProbe()
      ..expiredItems = [item]
      ..byId[item.id] = item;
    await _pumpHome(tester, api: api);
    await _openExpired(tester);

    await tester.tap(find.text('Soir éphémère'));
    await tester.pumpAndSettle();

    expect(find.byType(ChroniqueDetailScreen), findsOneWidget);
    expect(find.text(chroniqueDefinitiveDeletionLabel(item)!), findsWidgets);
    expect(find.text('Restaurer'), findsNothing);
    expect(find.text('Archiver'), findsNothing);
    expect(find.byTooltip('Actions'), findsNothing);
    expect(api.getCalls, greaterThan(0));
  });

  testWidgets('expired media opens the existing viewer', (tester) async {
    const image = ChroniqueMedia(
      id: 21,
      kind: 'image',
      status: 'ready',
      contentType: 'image/jpeg',
      sortOrder: 0,
      readUrl: 'https://example.test/expired.jpg',
    );
    final item = _expired(media: const [image]);
    final api = _ChroniqueApiProbe()
      ..expiredItems = [item]
      ..byId[item.id] = item;
    await _pumpHome(tester, api: api);
    await _openExpired(tester);

    await tester.tap(find.byKey(const ValueKey('chronique-feed-media-21')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ChroniqueMediaViewerPage), findsOneWidget);
    expect(find.byType(ChroniqueDetailScreen), findsNothing);
    expect(find.text('Restaurer'), findsNothing);
  });

  testWidgets('Archives still lists archived only and stays distinct', (tester) async {
    const archived = Chronique(
      id: 7,
      title: 'Mon souvenir',
      body: 'Texte de la chronique archivee pour les tests.',
      status: 'archived',
      publishedAt: '2026-09-01T08:00:00.000Z',
      archivedAt: '2026-09-23T15:40:00.000Z',
    );
    final expired = _expired();
    final api = _ChroniqueApiProbe()
      ..archivedItems = const [archived]
      ..expiredItems = [expired];
    await _pumpHome(tester, api: api);
    await _openArchives(tester);

    expect(api.lastListStatus, 'archived');
    expect(find.text('Mon souvenir'), findsOneWidget);
    expect(find.text('Soir éphémère'), findsNothing);
    expect(find.text('Aucune chronique expirée.'), findsNothing);
    expect(find.byType(ExpiredChroniquesScreen), findsNothing);
  });
}
