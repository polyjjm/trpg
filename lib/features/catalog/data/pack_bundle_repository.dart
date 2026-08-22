import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pack_bundle.dart';

/// packBundles 컬렉션 — 홈 탭 "번들 상품" 섹션과 스토리팩 상세 화면의
/// "이 팩이 포함된 번들"이 읽는 리더 쪽 조회. admin의
/// AdminPackBundleRepository와 같은 컬렉션을 보지만(admin/reader 분리 관례대로)
/// 별개 파일이고, 여긴 읽기 전용에 "지금 노출해도 되는 번들만" 거르는
/// 로직까지 포함한다.
class PackBundleRepository {
  PackBundleRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _bundles =>
      _firestore.collection('packBundles');

  /// active == true인 번들만 sortOrder 순으로 — 홈 탭 "번들 상품" 섹션.
  Stream<List<PackBundle>> watchActiveBundles() {
    return _bundles
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(_fromDoc).toList(),
        );
  }

  /// 특정 팩이 포함된 번들 — 스토리팩 상세 화면의 "이 팩이 포함된 번들".
  /// packIds arrayContains 하나만 필터로 쓴다(추가 색인 없이 바로 동작) —
  /// active 여부는 여기서 클라이언트가 거른다(HomeBannerRepository와 같은
  /// "필터링을 클라이언트에서 조합" 패턴).
  Stream<List<PackBundle>> watchBundlesContainingPack(String packId) {
    return _bundles
        .where('packIds', arrayContains: packId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => doc.data()['active'] as bool? ?? true)
              .map(_fromDoc)
              .toList(),
        );
  }

  PackBundle _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return PackBundle(
      id: doc.id,
      name: data['name'] as String? ?? '',
      packIds: (data['packIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      price: (data['price'] as num?)?.toInt() ?? 0,
      salePrice: (data['salePrice'] as num?)?.toInt(),
      discountStartAt: (data['discountStartAt'] as Timestamp?)?.toDate(),
      discountEndAt: (data['discountEndAt'] as Timestamp?)?.toDate(),
    );
  }
}
