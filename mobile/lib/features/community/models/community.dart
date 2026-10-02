import '../../chronique/models/chronique.dart';

enum CommunityRole {
  owner,
  admin,
  member;

  static CommunityRole parse(String raw) {
    switch (raw) {
      case 'owner':
        return CommunityRole.owner;
      case 'admin':
        return CommunityRole.admin;
      case 'member':
        return CommunityRole.member;
      default:
        throw const FormatException('Invalid community role');
    }
  }

  String get apiValue {
    switch (this) {
      case CommunityRole.owner:
        return 'owner';
      case CommunityRole.admin:
        return 'admin';
      case CommunityRole.member:
        return 'member';
    }
  }

  String get label {
    switch (this) {
      case CommunityRole.owner:
        return 'Propriétaire';
      case CommunityRole.admin:
        return 'Administrateur';
      case CommunityRole.member:
        return 'Membre';
    }
  }
}

class Community {
  const Community({
    required this.id,
    required this.name,
    required this.visibility,
    required this.myRole,
    required this.memberCount,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String? description;
  final String visibility;
  final CommunityRole myRole;
  final int memberCount;
  final String? createdAt;
  final String? updatedAt;

  factory Community.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final visibility = json['visibility'];
    final myRole = json['my_role'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Invalid community payload');
    }
    if (visibility is! String || myRole is! String) {
      throw const FormatException('Invalid community payload');
    }
    final description = json['description'];
    return Community(
      id: parseChroniqueId(json['id']),
      name: name,
      description: description is String && description.isNotEmpty ? description : null,
      visibility: visibility,
      myRole: CommunityRole.parse(myRole),
      memberCount: json['member_count'] is int
          ? json['member_count'] as int
          : parseChroniqueId(json['member_count']),
      createdAt: json['created_at'] is String ? json['created_at'] as String : null,
      updatedAt: json['updated_at'] is String ? json['updated_at'] as String : null,
    );
  }
}

class CommunitySearchPreview {
  const CommunitySearchPreview({
    required this.id,
    required this.name,
    required this.memberCount,
    this.description,
  });

  final int id;
  final String name;
  final String? description;
  final int memberCount;

  factory CommunitySearchPreview.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Invalid community search payload');
    }
    if (json.containsKey('my_role') ||
        json.containsKey('members') ||
        json.containsKey('avatar_storage_key') ||
        json.containsKey('email')) {
      throw const FormatException('Community search payload leaked private fields');
    }
    final description = json['description'];
    return CommunitySearchPreview(
      id: parseChroniqueId(json['id']),
      name: name,
      description: description is String && description.isNotEmpty ? description : null,
      memberCount: json['member_count'] is int
          ? json['member_count'] as int
          : parseChroniqueId(json['member_count']),
    );
  }
}

class UserSearchHit {
  const UserSearchHit({
    required this.userId,
    required this.login,
  });

  final int userId;
  final String login;

  static const _leakedFields = <String>[
    'phone_number',
    'phone',
    'email',
    'password_hash',
    'birth_date',
    'first_name',
    'last_name',
    'auth_provider',
    'provider_user_id',
  ];

  factory UserSearchHit.fromJson(Map<String, dynamic> json) {
    final login = json['login'];
    if (login is! String || login.isEmpty) {
      throw const FormatException('Invalid user search payload');
    }
    for (final field in _leakedFields) {
      if (json.containsKey(field)) {
        throw const FormatException('User search payload leaked private fields');
      }
    }
    return UserSearchHit(
      userId: parseChroniqueId(json['user_id']),
      login: login,
    );
  }
}

class CommunityMember {
  const CommunityMember({
    required this.userId,
    required this.login,
    required this.role,
  });

  final int userId;
  final String login;
  final CommunityRole role;

  factory CommunityMember.fromJson(Map<String, dynamic> json) {
    final login = json['login'];
    final role = json['role'];
    if (login is! String || role is! String) {
      throw const FormatException('Invalid community member payload');
    }
    return CommunityMember(
      userId: parseChroniqueId(json['user_id']),
      login: login,
      role: CommunityRole.parse(role),
    );
  }
}
