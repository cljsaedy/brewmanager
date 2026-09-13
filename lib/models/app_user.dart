/// A row from the `users` table.
///
/// Note there is no PIN field. The hash stays inside the repository; the rest
/// of the app only ever learns *who* logged in, never their PIN.
class AppUser {
  final int userId;
  final String name;
  final UserRole role;
  final bool isActive;

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

/// Matches the CHECK constraint on `users.role`.
enum UserRole {
  manager('Manager'),
  barista('Barista');

  const UserRole(this.dbValue);

  /// The exact string stored in the database.
  final String dbValue;

  static UserRole fromDb(String value) {
    return UserRole.values.firstWhere((r) => r.dbValue == value);
  }
}
