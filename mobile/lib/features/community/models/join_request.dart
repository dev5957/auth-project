import '../../chronique/models/chronique.dart';

const _joinRequestLeakedFields = <String>[
  'phone_number',
  'phone',
  'email',
  'password_hash',
  'birth_date',
  'first_name',
  'last_name',
  'members',
  'avatar_storage_key',
  'banner_storage_key',
  'user_id',
  'invitee_user_id',
];

void rejectJoinRequestLeaks(Map<String, dynamic> json) {
  for (final field in _joinRequestLeakedFields) {
    if (json.containsKey(field)) {
      throw const FormatException('Join request payload leaked private fields');
    }
  }
}

String formatJoinRequestDate(String? raw) {
  if (raw == null || raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

Set<int> pendingCommunityIdsFrom(Iterable<MyJoinRequest> items) {
  final pending = <int>{};
  final seen = <int>{};
  for (final item in items) {
    if (!seen.add(item.communityId)) {
      continue;
    }
    if (item.status == 'pending') {
      pending.add(item.communityId);
    }
  }
  return pending;
}

class CreatedJoinRequest {
  const CreatedJoinRequest({
    required this.id,
    required this.communityId,
    required this.status,
    this.createdAt,
  });

  final int id;
  final int communityId;
  final String status;
  final String? createdAt;

  factory CreatedJoinRequest.fromJson(Map<String, dynamic> json) {
    rejectJoinRequestLeaks(json);
    final status = json['status'];
    if (status is! String || status.isEmpty) {
      throw const FormatException('Invalid join request payload');
    }
    return CreatedJoinRequest(
      id: parseChroniqueId(json['id']),
      communityId: parseChroniqueId(json['community_id']),
      status: status,
      createdAt: json['created_at'] is String ? json['created_at'] as String : null,
    );
  }
}

class MyJoinRequest {
  const MyJoinRequest({
    required this.id,
    required this.communityId,
    required this.communityName,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int communityId;
  final String communityName;
  final String status;
  final String? createdAt;
  final String? updatedAt;

  factory MyJoinRequest.fromJson(Map<String, dynamic> json) {
    rejectJoinRequestLeaks(json);
    final name = json['community_name'];
    final status = json['status'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Invalid join request payload');
    }
    if (status is! String || status.isEmpty) {
      throw const FormatException('Invalid join request payload');
    }
    if (status != 'pending' &&
        status != 'accepted' &&
        status != 'declined' &&
        status != 'cancelled') {
      throw const FormatException('Invalid join request payload');
    }
    return MyJoinRequest(
      id: parseChroniqueId(json['id']),
      communityId: parseChroniqueId(json['community_id']),
      communityName: name,
      status: status,
      createdAt: json['created_at'] is String ? json['created_at'] as String : null,
      updatedAt: json['updated_at'] is String ? json['updated_at'] as String : null,
    );
  }

  String get requestedOnLabel => formatJoinRequestDate(createdAt);
}

class OwnerJoinRequest {
  const OwnerJoinRequest({
    required this.id,
    required this.status,
    this.requesterLogin,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String status;
  final String? requesterLogin;
  final String? createdAt;
  final String? updatedAt;

  factory OwnerJoinRequest.fromJson(Map<String, dynamic> json) {
    rejectJoinRequestLeaks(json);
    final status = json['status'];
    if (status is! String || status.isEmpty) {
      throw const FormatException('Invalid join request payload');
    }
    if (status != 'pending' && status != 'accepted' && status != 'declined') {
      throw const FormatException('Invalid join request payload');
    }
    final login = json['requester_login'];
    return OwnerJoinRequest(
      id: parseChroniqueId(json['id']),
      status: status,
      requesterLogin: login is String && login.trim().isNotEmpty ? login : null,
      createdAt: json['created_at'] is String ? json['created_at'] as String : null,
      updatedAt: json['updated_at'] is String ? json['updated_at'] as String : null,
    );
  }

  OwnerJoinRequest copyWithStatus(String nextStatus) {
    return OwnerJoinRequest(
      id: id,
      status: nextStatus,
      requesterLogin: requesterLogin,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String get requestedOnLabel => formatJoinRequestDate(createdAt);
}
