import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community_publication.dart';
import '../../providers/community_providers.dart';

sealed class MyCommunityPublicationsState {
  const MyCommunityPublicationsState();
}

final class MyCommunityPublicationsLoading extends MyCommunityPublicationsState {
  const MyCommunityPublicationsLoading();
}

final class MyCommunityPublicationsReady extends MyCommunityPublicationsState {
  const MyCommunityPublicationsReady(this.items);
  final List<CommunityPublication> items;
}

final class MyCommunityPublicationsError extends MyCommunityPublicationsState {
  const MyCommunityPublicationsError(this.message);
  final String message;
}

class MyCommunityPublicationsController
    extends AutoDisposeFamilyNotifier<MyCommunityPublicationsState, String> {
  late String _scope;

  @override
  MyCommunityPublicationsState build(String scope) {
    _scope = scope;
    Future<void>.microtask(load);
    return const MyCommunityPublicationsLoading();
  }

  Future<void> load() async {
    final scope = _scope;
    state = const MyCommunityPublicationsLoading();
    try {
      final page = await ref.read(communityRepositoryProvider).listMyPublications(scope);
      state = MyCommunityPublicationsReady(page.items);
    } on ApiException catch (error) {
      state = MyCommunityPublicationsError(error.message);
    } catch (_) {
      state = const MyCommunityPublicationsError('Impossible de charger vos publications');
    }
  }
}

final myCommunityPublicationsControllerProvider = AutoDisposeNotifierProvider.family<
    MyCommunityPublicationsController, MyCommunityPublicationsState, String>(
  MyCommunityPublicationsController.new,
);
