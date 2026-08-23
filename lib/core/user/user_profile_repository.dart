import 'package:cloud_firestore/cloud_firestore.dart';

import 'author_application_status.dart';
import 'user_profile.dart';
import 'user_role.dart';

/// users/{uid} 문서를 다루는 저장소. 게임 앱과 작가 편집기가 공통으로 쓴다.
class UserProfileRepository {
  UserProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid);

  Future<UserProfile?> fetchProfile(String uid) async {
    final snapshot = await _doc(uid).get();
    final data = snapshot.data();
    if (data == null) return null;
    return UserProfile.fromFirestore(uid, data);
  }

  /// role == 'author'인 계정 전부 — 관리자 화면의 "작가 관리"/개요 카드 전용.
  /// 단일 동등 필터만 쓰고 orderBy가 없어 복합 색인이 필요 없다(정렬은
  /// 호출부에서 클라이언트 쪽에 한다).
  Stream<List<UserProfile>> watchAuthors() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.author.wireValue)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => UserProfile.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// users 컬렉션 전체 — "회원 관리" 화면의 회원 탭(모든 role을 아우르는
  /// 검색/조회) 전용이다. [watchAuthors]와 달리 `where` 필터가 아예 없다 —
  /// 검색/역할 필터/정렬은 전부 호출부가 클라이언트에서 한다, 이 admin
  /// 도구의 다른 화면들과 같은 관례다(approvals/approval_filter.dart의
  /// 문서 참고 — 데이터셋이 유한한 내부용 화면이라 서버 쿼리를 늘릴 이유가
  /// 없다는 판단). 유저 수가 실제로 이 방식이 부담될 만큼 커지면 그때
  /// 페이지네이션을 붙이면 된다 — 지금 미리 만들어 두지 않는다.
  Stream<List<UserProfile>> watchAllUsers() {
    return _firestore
        .collection('users')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => UserProfile.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// [uids]에 해당하는 프로필만 한 번 읽어온다(라이브 스트림이 아니라
  /// Future) — role과 무관하게 "이 문서들의 실제 작성자가 지금 어떤
  /// 이름인지"를 찾을 때 쓴다([watchAuthors]는 role == author로 좁혀서
  /// admin이 만든 팩처럼 role이 author가 아닌 계정의 uid는 못 찾는다).
  /// Firestore의 `FieldPath.documentId` + `whereIn`은 한 번에 최대 30개까지만
  /// 되므로 30개씩 나눠 조회해 합친다 — 이 프로젝트의 admin 화면은 데이터가
  /// 유한하다는 전제라(approvals/approval_filter.dart 문서 참고) 이 정도
  /// 순차 조회로 충분하다.
  Future<List<UserProfile>> fetchProfilesByUids(List<String> uids) async {
    final distinctUids = uids.toSet().where((uid) => uid.isNotEmpty).toList();
    if (distinctUids.isEmpty) return const [];

    final results = <UserProfile>[];
    for (var i = 0; i < distinctUids.length; i += 30) {
      final chunk = distinctUids.sublist(
        i,
        i + 30 > distinctUids.length ? distinctUids.length : i + 30,
      );
      final snapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(
        snapshot.docs.map(
          (doc) => UserProfile.fromFirestore(doc.id, doc.data()),
        ),
      );
    }
    return results;
  }

  /// admin이 role을 직접 바꾼다 — 지금은 "작가 자격 회수"(author -> reader)
  /// 전용으로 쓰인다. firestore.rules의 `users/{userId}` admin 규칙
  /// (`allow update: if isAdmin();`)이 role을 포함해 이미 자유롭게 허용하고
  /// 있어서 이 메서드 자체에 별도 게이트가 필요 없다 — 다른 admin 액션들과
  /// 같은 패턴("규칙은 admin write를 넓게 허용하고, 실제로 무엇을 쓰는지는
  /// 이 저장소의 각 메서드가 좁힌다").
  ///
  /// [authorApplicationStatus]가 주어지면 같은 쓰기에 같이 반영한다 — 자격
  /// 회수 시 role만 reader로 되돌리고 authorApplicationStatus를 이전
  /// 값('approved')으로 남겨 두면, `AdminGatePage.canApply`가 여전히
  /// false로 평가돼(그 필드가 none/rejected일 때만 재신청 폼을 보여준다)
  /// 회수된 계정이 재신청 자체를 할 수 없게 되는 버그가 있었다 — role
  /// 변경과 항상 한 번의 쓰기로 같이 반영해서 그 어긋남이 생길 여지를
  /// 없앤다.
  Future<void> updateRole(
    String uid,
    UserRole role, {
    AuthorApplicationStatus? authorApplicationStatus,
  }) async {
    await _doc(uid).update({
      'role': role.wireValue,
      if (authorApplicationStatus != null)
        'authorApplicationStatus': authorApplicationStatus.wireValue,
    });
  }

  Stream<UserProfile?> watchProfile(String uid) {
    return _doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return UserProfile.fromFirestore(uid, data);
    });
  }

  /// 최초 로그인 시 문서가 없으면 role: reader인 기본 프로필로 새로 만든다.
  /// 이미 있으면 그대로 반환한다 — 기존 role/authorApplicationStatus를 덮어쓰지 않는다.
  Future<UserProfile> ensureProfile({
    required String uid,
    String? displayName,
    String? email,
  }) async {
    final existing = await fetchProfile(uid);
    if (existing != null) return existing;

    final profile = UserProfile(
      uid: uid,
      displayName: displayName ?? '',
      email: email ?? '',
      role: UserRole.reader,
      authorApplicationStatus: AuthorApplicationStatus.none,
    );

    await _doc(
      uid,
    ).set({...profile.toJson(), 'createdAt': FieldValue.serverTimestamp()});

    return profile;
  }
}
