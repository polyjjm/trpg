import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notice.dart';

/// notices 컬렉션 — 하단 탭 "공지사항"(NoticeListTab)과 CatalogShellPage의
/// 안 읽음 배지가 읽는다. active == true인 공지만, 최신순으로 노출한다.
class NoticeRepository {
  NoticeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Query<Map<String, dynamic>> get _activeNoticesQuery => _firestore
      .collection('notices')
      .where('active', isEqualTo: true)
      .orderBy('createdAt', descending: true);

  Stream<List<Notice>> watchActiveNotices() {
    return _activeNoticesQuery.snapshots().map(
      (snapshot) => snapshot.docs.map((doc) => Notice.fromFirestore(doc.id, doc.data())).toList(),
    );
  }

  /// 안 읽음 배지 전용 — 본문 전체를 구독할 필요 없이, 가장 최근 활성
  /// 공지 하나의 작성 시각만 가볍게 구독한다(CatalogShellPage가 이 값을
  /// readerPrefs.lastNoticeReadAt과 비교한다). 공지가 하나도 없으면 null.
  Stream<DateTime?> watchLatestNoticeAt() {
    return _activeNoticesQuery.limit(1).snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return (snapshot.docs.first.data()['createdAt'] as Timestamp?)?.toDate();
    });
  }
}
