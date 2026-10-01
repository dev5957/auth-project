import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/router/app_routes.dart';
import 'package:mobile/features/auth/data/storage/auth_token_storage.dart';
import 'package:mobile/features/auth/models/auth_account.dart';
import 'package:mobile/features/auth/providers/auth_controller.dart';
import 'package:mobile/features/auth/providers/auth_providers.dart';
import 'package:mobile/features/auth/state/auth_state.dart';
import 'package:mobile/features/community/models/community.dart';
import 'package:mobile/features/community/models/community_fields.dart';
import 'package:mobile/features/community/presentation/screens/community_detail_screen.dart';
import 'package:mobile/features/community/presentation/screens/community_list_screen.dart';
import 'package:mobile/features/community/presentation/screens/create_community_screen.dart';
import 'package:mobile/features/community/providers/community_providers.dart';
import 'package:mobile/features/community/services/community_api_service.dart';
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

class _SeededAuthController extends AuthController {
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

class _FakeCommunityApi extends CommunityApiService {
  _FakeCommunityApi()
      : super(ApiClient(config: const AppConfig(apiBaseUrl: 'http://test.invalid')));

  ApiException? failList;
  ApiException? failGet;
  ApiException? failCreate;
  final List<Community> items = [
    const Community(
      id: 3,
      name: 'Jardin secret',
      visibility: 'private',
      myRole: CommunityRole.owner,
      memberCount: 1,
      description: 'Un cercle privé',
    ),
  ];

  @override
  Future<Community> create({
    required String accessToken,
    required String name,
    String? description,
  }) async {
    if (failCreate != null) {
      throw failCreate!;
    }
    final community = Community(
      id: 8,
      name: name,
      description: description,
      visibility: 'private',
      myRole: CommunityRole.owner,
      memberCount: 1,
    );
    items.add(community);
    return community;
  }

  @override
  Future<List<Community>> list({required String accessToken}) async {
    if (failList != null) {
      throw failList!;
    }
    return List<Community>.from(items);
  }

  @override
  Future<Community> get({
    required String accessToken,
    required int id,
  }) async {
    if (failGet != null) {
      throw failGet!;
    }
    return items.firstWhere(
      (item) => item.id == id,
      orElse: () => throw const ApiException(message: 'Community not found', statusCode: 404),
    );
  }

  @override
  Future<List<CommunityMember>> listMembers({
    required String accessToken,
    required int id,
  }) async {
    if (failGet != null) {
      throw failGet!;
    }
    return const [
      CommunityMember(userId: 1, login: 'tgjjk', role: CommunityRole.owner),
    ];
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _FakeCommunityApi api,
  AuthTokenStorage? tokens,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authTokenStorageProvider.overrideWithValue(
          tokens ??
              InMemoryAuthTokenStorage(
                accessToken: 'access-test',
                refreshToken: 'refresh-test',
              ),
        ),
        authControllerProvider.overrideWith(() => _SeededAuthController()),
        communityApiServiceProvider.overrideWithValue(api),
      ],
      child: const LuminaApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('community name validation uses trim and rune length', () {
    expect(CommunityFields.nameError('short'), isNotNull);
    expect(CommunityFields.nameError('abcdefghij'), isNull);
    expect(CommunityFields.nameError('  Jardin secret  '), isNull);
    expect(CommunityFields.nameError('a' * 101), isNotNull);
    expect(CommunityFields.descriptionError('x' * 501), isNotNull);
    expect(CommunityFields.descriptionError('ok'), isNull);
  });

  test('search preview rejects private leaks', () {
    expect(
      () => CommunitySearchPreview.fromJson({
        'id': 1,
        'name': 'Jardin secret',
        'member_count': 2,
        'my_role': 'owner',
      }),
      throwsA(isA<FormatException>()),
    );
    final preview = CommunitySearchPreview.fromJson({
      'id': 1,
      'name': 'Jardin secret',
      'description': 'Hello',
      'member_count': 2,
    });
    expect(preview.name, 'Jardin secret');
    expect(preview.memberCount, 2);
  });

  testWidgets('COMMUNITIES opens the membership list', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.text('Jardin secret'), findsOneWidget);
    expect(find.text('Propriétaire'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Avatar')), findsWidgets);
  });

  testWidgets('create community from list after field validation', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-create-open')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateCommunityScreen), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('community-name-field')), 'short');
    await tester.tap(find.byKey(const ValueKey('community-create-submit')));
    await tester.pump();
    expect(find.text('Le nom doit contenir au moins 10 caractères'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('community-name-field')), 'Atelier lumineux');
    await tester.tap(find.byKey(const ValueKey('community-create-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityListScreen), findsOneWidget);
    expect(find.text('Atelier lumineux'), findsOneWidget);
  });

  testWidgets('member can open community detail with placeholders', (tester) async {
    final api = _FakeCommunityApi();
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-detail-role')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Bannière')), findsOneWidget);
    expect(find.byKey(const ValueKey('community-placeholder-Avatar')), findsOneWidget);
  });

  testWidgets('detail 404 shows introuvable', (tester) async {
    final api = _FakeCommunityApi()
      ..failGet = const ApiException(message: 'Community not found', statusCode: 404);
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-list-item-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-detail-error')), findsOneWidget);
    expect(find.text('Communauté introuvable'), findsOneWidget);
  });

  testWidgets('list 401 shows session error', (tester) async {
    final api = _FakeCommunityApi()
      ..failList = const ApiException(message: 'Unauthorized', statusCode: 401);
    await _pumpApp(tester, api: api);
    await tester.tap(find.text('COMMUNITIES'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('community-list-error')), findsOneWidget);
    expect(find.text('Session expirée'), findsOneWidget);
  });

  test('authenticated whitelist includes community routes', () {
    expect(AppRoutes.isAuthenticatedLocation('/communities'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/create'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/12'), isTrue);
    expect(AppRoutes.isAuthenticatedLocation('/communities/nope'), isFalse);
  });
}
