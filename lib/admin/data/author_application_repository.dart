import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/user/author_application_status.dart';
import '../../core/user/user_role.dart';
import '../models/author_application.dart';

/// authorApplications 컬렉션. 문서 id == 신청자 uid — "이미 신청했는가"를 쿼리
/// 없이 단건 조회로 확인할 수 있다.
class AuthorApplicationRepository {
  AuthorApplicationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('authorApplications').doc(uid);

  Future<AuthorApplication?> fetchApplication(String uid) async {
    final snapshot = await _doc(uid).get();
    final data = snapshot.data();
    if (data == null) return null;
    return AuthorApplication.fromFirestore(uid, data);
  }

  /// 신규 제출과 반려 후 재신청 모두 이 메서드 하나로 처리한다 — 항상 pending으로
  /// 덮어쓰고 이전 반려 사유/검토 기록은 지운다. users/{uid}.authorApplicationStatus는
  /// AdminGatePage가 화면을 가르는 데 쓰는 비정규화 필드라, 여기서 같은 배치로
  /// 같이 갱신해야 신청 직후 곧바로 대기 화면으로 넘어간다.
  Future<void> submitApplication({
    required String uid,
    required String displayName,
    required String bio,
    required List<String> portfolioLinks,
  }) async {
    final batch = _firestore.batch();

    batch.set(_doc(uid), {
      'uid': uid,
      'displayName': displayName,
      'bio': bio,
      'portfolioLinks': portfolioLinks,
      'status': AuthorApplicationStatus.pending.wireValue,
      'rejectionReason': null,
      'reviewedBy': null,
      'reviewedAt': null,
      'submittedAt': FieldValue.serverTimestamp(),
    });

    batch.set(_firestore.collection('users').doc(uid), {
      'authorApplicationStatus': AuthorApplicationStatus.pending.wireValue,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// 대기 중(pending)인 신청서를 전부 감시한다 — 관리자 검토 탭 전용.
  Stream<List<AuthorApplication>> watchPendingApplications() {
    return _firestore
        .collection('authorApplications')
        .where('status', isEqualTo: AuthorApplicationStatus.pending.wireValue)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AuthorApplication.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 승인: 신청서 자체와 users/{uid}(role→author, authorApplicationStatus→approved)를
  /// 한 배치로 같이 갱신한다 — "작가 자격 부여"만 하는 것이고, 이 계정이 실제로
  /// 쓴 콘텐츠는 여전히 기존 노드 승인 흐름(status/pendingAction/liveSnapshot)을
  /// 그대로 거쳐야 한다. 이 메서드는 그 흐름을 전혀 건드리지 않는다.
  Future<void> approveApplication(
    AuthorApplication application, {
    required String reviewerUid,
  }) async {
    final batch = _firestore.batch();

    batch.update(_doc(application.uid), {
      'status': AuthorApplicationStatus.approved.wireValue,
      'rejectionReason': null,
      'reviewedBy': reviewerUid,
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // .set(merge: true)가 아니라 .update()를 쓴다 — 신청서가 존재한다는 건 이미
    // ensureProfile()을 거쳐 users/{uid}가 만들어져 있다는 뜻이라, 이건 항상
    // "기존 사용자 갱신"이지 "새 사용자 생성"이 아니다. merge-set은 문서가 없을
    // 때 Firestore 규칙상 create로 취급되는데, users/{userId}의 create 규칙은
    // 본인만 허용해서 admin이 남의 문서에 쓰면 permission-denied가 난다.
    batch.update(_firestore.collection('users').doc(application.uid), {
      'role': UserRole.author.wireValue,
      'authorApplicationStatus': AuthorApplicationStatus.approved.wireValue,
    });

    await batch.commit();
  }

  /// 반려: role은 그대로 reader로 남고, authorApplicationStatus만 rejected로
  /// 바뀐다 — 신청자는 신청 폼을 다시 볼 수 있고(반려 사유 배너 포함), 재신청 시
  /// [submitApplication]이 이 문서를 그대로 덮어쓴다.
  Future<void> rejectApplication(
    AuthorApplication application, {
    required String reviewerUid,
    String? reason,
  }) async {
    final batch = _firestore.batch();

    batch.update(_doc(application.uid), {
      'status': AuthorApplicationStatus.rejected.wireValue,
      'rejectionReason': reason,
      'reviewedBy': reviewerUid,
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // approveApplication과 같은 이유로 .set(merge: true) 대신 .update() —
    // users/{uid}는 항상 이미 존재하는 문서이므로 update가 맞고, merge-set은
    // Firestore 규칙상 create로 오인되어 admin의 쓰기가 막힐 수 있었다.
    batch.update(_firestore.collection('users').doc(application.uid), {
      'authorApplicationStatus': AuthorApplicationStatus.rejected.wireValue,
    });

    await batch.commit();
  }
}
