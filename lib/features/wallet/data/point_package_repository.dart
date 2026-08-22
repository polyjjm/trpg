import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/point_package.dart';

/// pointPackages 컬렉션 — 충전 화면(ChargePage)이 읽는 리더 쪽 조회. admin의
/// AdminPointPackageRepository와 같은 컬렉션을 보지만(CLAUDE.md의 admin/reader
/// 분리 관례대로) 별개 파일이고, 여긴 읽기 전용에 "지금 이 플랫폼에 노출해도
/// 되는 상품만" 거르는 로직까지 포함한다.
class PointPackageRepository {
  PointPackageRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// active == true && platform == 'web'인 상품만 sortOrder 순으로.
  /// (모바일 빌드가 생기면 platform 값만 바꿔 같은 메서드를 재사용한다.)
  Stream<List<PointPackage>> watchWebPackages() {
    return _firestore
        .collection('pointPackages')
        .where('active', isEqualTo: true)
        .where('platform', isEqualTo: PointPackagePlatform.web.wireValue)
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PointPackage.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }
}
