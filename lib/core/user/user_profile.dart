import 'author_application_status.dart';
import 'user_role.dart';

/// users/{uid} 문서. 게임 세이브(users/{uid}/save/current)와는 별개로, 신원/권한만
/// 다룬다 — 게임 앱(lib/main.dart)과 작가 편집기(lib/main_admin.dart) 둘 다 이 문서를
/// 읽고 그 위에서 화면을 가른다(FIRESTORE_SCHEMA.md의 users/{uid} 참고).
class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final UserRole role;
  final AuthorApplicationStatus authorApplicationStatus;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.authorApplicationStatus,
  });

  factory UserProfile.fromFirestore(String uid, Map<String, dynamic> json) {
    return UserProfile(
      uid: uid,
      displayName: json['displayName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: UserRoleJson.fromWire(json['role'] as String?),
      authorApplicationStatus:
          AuthorApplicationStatusJson.fromWire(json['authorApplicationStatus'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'email': email,
        'role': role.wireValue,
        'authorApplicationStatus': authorApplicationStatus.wireValue,
      };

  /// 작가 편집기(lib/admin/) 접근 가능 여부 — author/admin 둘 다 해당.
  bool get canAccessAuthorTool => role == UserRole.author || role == UserRole.admin;

  bool get isAdmin => role == UserRole.admin;
}
