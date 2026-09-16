/// a row from the users table
class AppUser {
  final int userId;
  final String name;
  final UserRole role;
  final bool isActive;

  // no pin field on purpose, the app only needs to know who logged in not their pin
  const AppUser({
    required this.userId,
    required this.name,
    required this.role,
    required this.isActive,
  });

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      userId: map['user_id'] as int,
      name: map['name'] as String,
      role: UserRole.fromDb(map['role'] as String),
      isActive: (map['is_active'] as int) == 1,
    );
  }

  bool get isManager => role == UserRole.manager;
}

/// matches the CHECK constraint on users.role
enum UserRole {
  manager('Manager'),
  barista('Barista');

  const UserRole(this.dbValue);

  /// exact string stored in the db
  final String dbValue;

  static UserRole fromDb(String value) {
    return UserRole.values.firstWhere((r) => r.dbValue == value);
  }
}
