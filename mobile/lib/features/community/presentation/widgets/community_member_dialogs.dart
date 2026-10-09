import 'package:flutter/material.dart';

import '../../models/community.dart';

Future<bool> confirmPromoteMember(BuildContext context, {required String login}) async {
  return _confirm(
    context,
    title: 'Nommer administrateur ?',
    body: '$login pourra inviter des membres. Vous resterez propriétaire.',
    confirmLabel: 'Nommer',
    key: 'community-promote-confirm',
  );
}

Future<bool> confirmDemoteAdmin(BuildContext context, {required String login}) async {
  return _confirm(
    context,
    title: 'Retirer le rôle admin ?',
    body: '$login redeviendra membre et ne pourra plus inviter.',
    confirmLabel: 'Rétrograder',
    key: 'community-demote-confirm',
  );
}

Future<bool> confirmRemoveMember(BuildContext context, {required String login}) async {
  return _confirm(
    context,
    title: 'Retirer ce membre ?',
    body: '$login n’aura plus accès à cette communauté privée. Ses contenus restent conservés.',
    confirmLabel: 'Retirer',
    key: 'community-remove-confirm',
  );
}

Future<bool> confirmLeaveCommunity(BuildContext context) async {
  return _confirm(
    context,
    title: 'Quitter la communauté ?',
    body: 'Vous n’aurez plus accès à cet espace privé. Vos contenus restent conservés.',
    confirmLabel: 'Quitter',
    key: 'community-leave-confirm',
  );
}

Future<bool> confirmOwnerTransfer(
  BuildContext context, {
  required String successorLogin,
}) async {
  return _confirm(
    context,
    title: 'Transférer et quitter ?',
    body:
        'La propriété sera transférée à $successorLogin. Vous quitterez la communauté et n’en serez plus membre.',
    confirmLabel: 'Transférer',
    key: 'community-transfer-confirm',
  );
}

Future<void> showOwnerCannotLeave(BuildContext context, {required bool hasMembers}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        key: const ValueKey('community-owner-cannot-leave'),
        title: const Text('Départ impossible'),
        content: Text(
          hasMembers
              ? 'Nommez d’abord un administrateur, puis vous pourrez transférer la propriété.'
              : 'Vous êtes seul propriétaire. La communauté ne peut pas rester sans owner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Compris'),
          ),
        ],
      );
    },
  );
}

Future<CommunityMember?> selectEligibleMemberForAdmin(
  BuildContext context, {
  required List<CommunityMember> members,
}) async {
  if (members.isEmpty) {
    return null;
  }
  return showDialog<CommunityMember>(
    context: context,
    builder: (context) {
      CommunityMember? selected = members.length == 1 ? members.first : null;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            key: const ValueKey('community-no-admin-picker'),
            title: const Text('Aucun administrateur'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Désignez un membre comme administrateur avant de transférer la propriété et de quitter.',
                  ),
                  const SizedBox(height: 12),
                  for (final member in members)
                    RadioListTile<int>(
                      key: ValueKey('community-no-admin-option-${member.userId}'),
                      title: Text(member.login),
                      value: member.userId,
                      groupValue: selected?.userId,
                      onChanged: (_) {
                        setState(() {
                          selected = member;
                        });
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              TextButton(
                key: const ValueKey('community-no-admin-continue'),
                onPressed: selected == null ? null : () => Navigator.of(context).pop(selected),
                child: const Text('Continuer'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String key,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        key: ValueKey(key),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: ValueKey('$key-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

CommunityMember? plannedSuccessor(List<CommunityMember> members) => oldestCurrentAdmin(members);
