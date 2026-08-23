import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Firebase Auth 계정의 `disabled` 플래그를 그대로 거울에 비춘 값 —
  /// Cloud Function(setAuthorAccountDisabled, Admin SDK 전용)만 쓴다. 클라
  /// 이언트는 Auth Admin API를 직접 조회할 수 없어서, "이 계정이 지금
  /// 로그인 차단 상태인가"를 화면에 보여주려면 이 거울 필드를 읽는 수밖에
  /// 없다 — 실제 로그인 차단 여부의 진짜 원천은 항상 Auth의 disabled
  /// 플래그이고, 이 필드는 그걸 반영만 한다(둘이 어긋나는 유일한 경우는
  /// Cloud Function 실행 중 실패인데, 그 함수는 Auth 갱신 다음에 이 필드를
  /// 쓰므로 실패해도 "실제보다 더 안전한 쪽"으로만 어긋난다).
  final bool accountDisabled;

  /// 계정 생성 시각(`FieldValue.serverTimestamp()`, `ensureProfile()`이 최초
  /// 로그인 때 찍는다). 이 필드가 생기기 전에 만들어진 계정에는 없다 —
  /// 백필하지 않는다. "회원 관리" 화면의 가입일 표시/최신순 정렬이 이
  /// 필드를 쓴다(AdminStoryPack.createdAt과 같은 nullable-safe 관례).
  final DateTime? createdAt;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.authorApplicationStatus,
    this.accountDisabled = false,
    this.createdAt,
  });

  factory UserProfile.fromFirestore(String uid, Map<String, dynamic> json) {
    return UserProfile(
      uid: uid,
      displayName: json['displayName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: UserRoleJson.fromWire(json['role'] as String?),
      authorApplicationStatus: AuthorApplicationStatusJson.fromWire(
        json['authorApplicationStatus'] as String?,
      ),
      accountDisabled: json['accountDisabled'] as bool? ?? false,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'email': email,
    'role': role.wireValue,
    'authorApplicationStatus': authorApplicationStatus.wireValue,
  };

  /// 작가 편집기(lib/admin/) 접근 가능 여부 — author/admin 둘 다 해당.
  bool get canAccessAuthorTool =>
      role == UserRole.author || role == UserRole.admin;

  bool get isAdmin => role == UserRole.admin;
}
