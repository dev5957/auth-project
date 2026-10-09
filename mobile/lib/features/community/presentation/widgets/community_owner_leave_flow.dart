import 'package:flutter/material.dart';

import '../../models/community.dart';
import 'community_member_dialogs.dart';

Future<bool> runCommunityLeaveFlow({
  required BuildContext context,
  required CommunityRole myRole,
  required List<CommunityMember> members,
  required Future<bool> Function({required int userId, required String role}) updateMemberRole,
  required Future<bool> Function() leave,
  void Function(String message)? onError,
}) async {
  if (myRole != CommunityRole.owner) {
    if (!await confirmLeaveCommunity(context)) {
      return false;
    }
    final ok = await leave();
    if (!ok) {
      onError?.call('Impossible de quitter cette communauté');
    }
    return ok;
  }

  var successor = plannedSuccessor(members);
  if (successor == null) {
    final eligible = [
      for (final member in members)
        if (member.role == CommunityRole.member) member,
    ];
    if (eligible.isEmpty) {
      if (context.mounted) {
        await showOwnerCannotLeave(context, hasMembers: false);
      }
      return false;
    }
    if (!context.mounted) {
      return false;
    }
    final chosen = await selectEligibleMemberForAdmin(context, members: eligible);
    if (chosen == null || !context.mounted) {
      return false;
    }
    final promoteConfirmed = await confirmPromoteMember(context, login: chosen.login);
    if (!promoteConfirmed || !context.mounted) {
      return false;
    }
    final promoted = await updateMemberRole(userId: chosen.userId, role: 'admin');
    if (!promoted) {
      onError?.call('Impossible de modifier ce rôle');
      return false;
    }
    successor = CommunityMember(
      userId: chosen.userId,
      login: chosen.login,
      role: CommunityRole.admin,
    );
  }

  if (!context.mounted) {
    return false;
  }
  final transferConfirmed = await confirmOwnerTransfer(
    context,
    successorLogin: successor.login,
  );
  if (!transferConfirmed) {
    return false;
  }
  final ok = await leave();
  if (!ok) {
    onError?.call('Impossible de quitter cette communauté');
  }
  return ok;
}
