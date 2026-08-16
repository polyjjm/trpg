/// users/{uid} 문서의 역할. 접근 권한을 가르는 단일 기준이다.
enum UserRole { reader, author, admin }

extension UserRoleJson on UserRole {
  String get wireValue => name;

  static UserRole fromWire(String? value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.reader,
    );
  }
}
