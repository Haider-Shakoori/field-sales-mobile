/// Authenticated session payload returned by the login endpoint.
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

class UserInfo {
  UserInfo({
    required this.id,
    required this.name,
    required this.email,
    this.role,
    this.branchId,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
    id: json['id'] as int? ?? 0,
    name: json['name']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    role: json['role']?.toString(),
    branchId: json['branch_id'] as int?,
  );

  final int id;
  final String name;
  final String email;
  final String? role;
  final int? branchId;
}

class TenantInfo {
  TenantInfo({required this.id, required this.name, this.slug});

  factory TenantInfo.fromJson(Map<String, dynamic> json) => TenantInfo(
    id: json['id'] as int? ?? 0,
    name: json['name']?.toString() ?? '',
    slug: json['slug']?.toString(),
  );

  final int id;
  final String name;
  final String? slug;
}

class DeviceInfo {
  DeviceInfo({required this.id, this.uuid, this.status});

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    id: json['id'] as int? ?? 0,
    uuid: json['uuid']?.toString(),
    status: json['status']?.toString(),
  );

  final int id;
  final String? uuid;
  final String? status;
}
