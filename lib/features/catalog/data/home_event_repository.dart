import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/home_event.dart';

/// homeEvents 컬렉션 — 홈 탭이 앱이 열릴 때 한 번(하루 한 번, 또는 "다시 보지
/// 않기" 전까지) 띄우는 이벤트 팝업이 읽는 리더 쪽 조회. admin의
/// HomeEventRepository와 같은 컬렉션을 보지만(admin/reader 분리 관례) 별개
/// 파일이고, 여긴 읽기 전용에 "지금 노출해도 되는 이벤트만" 거르는 로직까지
/// 포함한다 — HomeBannerRepository(리더 사본)와 같은 구조다.
class HomeEventRepository {
  HomeEventRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// active == true인 이벤트를 sortOrder 순으로 받은 뒤, startDate/endDate
  /// 기간과 "지금 노출 가능한지"를 클라이언트에서 걸러낸다(HomeBannerRepository와
  /// 같은 이유 — 이벤트 개수가 적어서 클라이언트 필터링 비용이 무시할
  /// 만하다). 동시에 여러 이벤트가 활성 상태여도 모달을 여러 개 겹쳐 띄우지
  /// 않도록, sortOrder가 가장 작은 것 하나만 골라 낸다 — 그 선택은 여기가
  /// 아니라 호출부(HomeTab)가 한다(로컬 노출 이력과 합쳐서 판단해야 해서).
  Stream<List<HomeEvent>> watchActiveEvents() {
    return _firestore
        .collection('homeEvents')
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          return snapshot.docs
              .where((doc) => _isWithinWindow(doc.data(), now))
              .map((doc) => HomeEvent.fromFirestore(doc.id, doc.data()))
              .toList();
        });
  }

  bool _isWithinWindow(Map<String, dynamic> data, DateTime now) {
    final startDate = (data['startDate'] as Timestamp?)?.toDate();
    if (startDate != null && now.isBefore(startDate)) return false;

    final endDate = (data['endDate'] as Timestamp?)?.toDate();
    if (endDate != null && now.isAfter(endDate)) return false;

    return true;
  }
}
