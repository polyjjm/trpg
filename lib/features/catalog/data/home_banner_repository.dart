import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/home_banner.dart';

/// homeBanners 컬렉션 — 홈 화면 히어로 배너 캐러셀(HeroBannerSection)이
/// 읽는 리더 쪽 조회. admin의 HomeBannerRepository와 같은 컬렉션을 보지만
/// (CLAUDE.md의 admin/reader 분리 관례대로) 별개 파일이고, 여긴 읽기 전용에
/// "지금 노출해도 되는 배너만" 거르는 로직까지 포함한다.
class HomeBannerRepository {
  HomeBannerRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// active == true인 배너를 정렬 순서대로 받은 뒤, startAt/endAt 기간을
  /// 클라이언트에서 걸러낸다 — 두 필드 모두 nullable이라 Firestore 쿼리
  /// 하나로 "그 사이" 조건을 걸면(둘 다 부등호라 같은 쿼리에 못 넣거나,
  /// 필드가 없는 문서를 부등호가 자동으로 걸러버리는 문제) 복잡해지기만
  /// 하고, 배너 개수 자체가 적어서 클라이언트 필터링 비용이 무시할 만하다.
  /// active만 걸러도 sortOrder 단일 필드 orderBy라 복합 색인이 필요 없다.
  Stream<List<HomeBanner>> watchActiveBanners() {
    return _firestore
        .collection('homeBanners')
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          return snapshot.docs
              .where((doc) => _isWithinWindow(doc.data(), now))
              .map((doc) => HomeBanner.fromFirestore(doc.id, doc.data()))
              .toList();
        });
  }

  bool _isWithinWindow(Map<String, dynamic> data, DateTime now) {
    final startAt = (data['startAt'] as Timestamp?)?.toDate();
    if (startAt != null && now.isBefore(startAt)) return false;

    final endAt = (data['endAt'] as Timestamp?)?.toDate();
    if (endAt != null && now.isAfter(endAt)) return false;

    return true;
  }
}
