/// Authenticated session payload returned by the login endpoint.
///
/// Laravel exposes UUID public ids (`id => $this->uuid`) for users, tenants and
/// devices, while legacy/mock payloads may still carry integer ids. The models
/// therefore keep a tolerant numeric [id] and a canonical [publicId] string.
class Session {
  Session({
    required this.token,
    required this.user,
    required this.tenant,
    this.permissions = const [],
    this.device,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] as Map<String, dynamic>? ?? const {};
    final tenantJson = json['tenant'] as Map<String, dynamic>? ?? const {};
    final deviceJson = json['device'] as Map<String, dynamic>?;

    return Session(
      token: json['token']?.toString() ?? '',
      user: UserInfo.fromJson(userJson),
      tenant: TenantInfo.fromJson(tenantJson),
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .cast<String>(),
      device: deviceJson == null ? null : DeviceInfo.fromJson(deviceJson),
    );
  }

  final String token;
  final UserInfo user;
  final TenantInfo tenant;
  final List<String> permissions;
  final DeviceInfo? device;
}

int tolerantIntId(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class UserInfo {
  UserInfo({
    required this.id,
    this.publicId = '',
    required this.name,
    required this.email,
    this.role,
    this.branchId,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
    id: tolerantIntId(json['id']),
    publicId: _publicId(json),
    name: json['name']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    role: json['role']?.toString(),
    branchId: json['branch_id'] is int
        ? json['branch_id'] as int
        : int.tryParse(json['branch_id']?.toString() ?? ''),
  );

  final int id;

  /// Canonical public id (UUID on real Laravel responses).
  final String publicId;
  final String name;
  final String email;
  final String? role;
  final int? branchId;

  /// Stable identity key used for local tenant/user scoping.
  String get key => publicId.isNotEmpty ? publicId : id.toString();
}

class TenantInfo {
  TenantInfo({
    required this.id,
    this.publicId = '',
    required this.name,
    this.slug,
  });

  factory TenantInfo.fromJson(Map<String, dynamic> json) => TenantInfo(
    id: tolerantIntId(json['id']),
    publicId: _publicId(json),
    name: json['name']?.toString() ?? '',
    slug: json['slug']?.toString(),
  );

  final int id;

  /// Canonical public id (UUID on real Laravel responses).
  final String publicId;
  final String name;
  final String? slug;

  /// Stable identity key used for local tenant scoping.
  String get key => publicId.isNotEmpty ? publicId : id.toString();
}

class DeviceInfo {
  DeviceInfo({required this.id, this.publicId = '', this.uuid, this.status});

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    id: tolerantIntId(json['id']),
    publicId: _publicId(json),
    uuid: json['uuid']?.toString() ?? json['device_uuid']?.toString(),
    status: json['status']?.toString(),
  );

  final int id;
  final String publicId;
  final String? uuid;
  final String? status;
}

String _publicId(Map<String, dynamic> json) {
  final uuid = json['uuid']?.toString();
  if (uuid != null && uuid.isNotEmpty) {
    return uuid;
  }
  final raw = json['id'];
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return '';
}
