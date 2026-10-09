import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../models/community.dart';
import '../../models/community_fields.dart';
import '../../providers/community_providers.dart';

sealed class CreateCommunityState {
  const CreateCommunityState();
}

final class CreateCommunityIdle extends CreateCommunityState {
  const CreateCommunityIdle({this.nameError, this.descriptionError});

  final String? nameError;
  final String? descriptionError;
}

final class CreateCommunitySubmitting extends CreateCommunityState {
  const CreateCommunitySubmitting();
}

final class CreateCommunitySuccess extends CreateCommunityState {
  const CreateCommunitySuccess(this.community);

  final Community community;
}

final class CreateCommunityError extends CreateCommunityState {
  const CreateCommunityError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class CreateCommunityController extends AutoDisposeNotifier<CreateCommunityState> {
  @override
  CreateCommunityState build() => const CreateCommunityIdle();

  Future<void> submit({required String name, required String description}) async {
    final nameError = CommunityFields.nameError(name);
    final descriptionError = CommunityFields.descriptionError(description);
    if (nameError != null || descriptionError != null) {
      state = CreateCommunityIdle(nameError: nameError, descriptionError: descriptionError);
      return;
    }
    state = const CreateCommunitySubmitting();
    try {
      final community = await ref.read(communityRepositoryProvider).create(
            name: CommunityFields.trimmedName(name),
            description: CommunityFields.trimmedDescription(description),
          );
      state = CreateCommunitySuccess(community);
    } on ApiException catch (error) {
      debugPrint(
        '[community] POST /communities failed status=${error.statusCode} message=${error.message}',
      );
      state = CreateCommunityError(
        error.message.trim().isEmpty ? 'Unexpected error' : error.message,
        statusCode: error.statusCode,
      );
    } on FormatException {
      state = const CreateCommunityError('Unexpected error');
    }
  }
}

final createCommunityControllerProvider =
    AutoDisposeNotifierProvider<CreateCommunityController, CreateCommunityState>(
  CreateCommunityController.new,
);
