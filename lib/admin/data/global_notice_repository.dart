import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/global_notice.dart';

/// notices 컬렉션 — "공지사항 관리" 섹션(GlobalNoticeManagementSection)의
/// CRUD. genres/homeBanners와 같은 구조(admin만 쓰고, 승인 게이트 없이 바로
/// 반영된다) — writerNotices(작가가 자기 팩에 올리는 공지, 완전히 다른
/// 컬렉션/기능)와 혼동하지 않는다.
class AdminGlobalNoticeRepository {
  AdminGlobalNoticeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _notices =>
      _firestore.collection('notices');

  /// 관리자 화면 전용 — 비활성 공지까지 전부, 최신순으로.
  Stream<List<AdminGlobalNotice>> watchAllNotices() {
    return _notices
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminGlobalNotice.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> createNotice({
    required String title,
    required String body,
    required String authorId,
  }) async {
    await _notices.add({
      'title': title,
      'body': body,
      'active': true,
      'authorId': authorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 제목/내용/활성 여부만 고친다 — createdAt/authorId는 처음 쓴 그대로
  /// 남긴다(리뷰의 createdAt과 같은 이유 — 언제·누가 썼는지는 기록이다).
  Future<void> updateNotice(
    String noticeId, {
    required String title,
    required String body,
    required bool active,
  }) async {
    await _notices.doc(noticeId).update({
      'title': title,
      'body': body,
      'active': active,
    });
  }

  Future<void> deleteNotice(String noticeId) async {
    await _notices.doc(noticeId).delete();
  }
}
