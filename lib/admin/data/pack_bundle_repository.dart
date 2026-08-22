import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pack_bundle.dart';

/// packBundles 컬렉션 — "번들 상품 관리" 섹션(PackBundleManagementSection)의
/// CRUD. AdminPointPackageRepository와 같은 구조다. 가격 자체는 구매 시점에
/// Cloud Function(purchaseBundle)이 이 문서를 서버에서 다시 읽어 검증하므로,
/// 여기서 잘못된 값을 저장해도 클라이언트가 임의로 코인을 아끼는 일은 없다
/// — 다만 사용자에게 보여주는 가격/구성 자체는 이 문서가 유일한 원천이다.
class AdminPackBundleRepository {
  AdminPackBundleRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _bundles =>
      _firestore.collection('packBundles');

  /// 관리자 화면 전용 — 비활성 번들까지 전부 보여준다(리더 쪽 사본은
  /// active == true만 거른다).
  Stream<List<AdminPackBundle>> watchAllBundles() {
    return _bundles.orderBy('sortOrder').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => AdminPackBundle.fromFirestore(doc.id, doc.data()))
          .toList(),
    );
  }

  Future<void> createBundle({
    required String name,
    required List<String> packIds,
    required int price,
    required int? salePrice,
    required DateTime? discountStartAt,
    required DateTime? discountEndAt,
    required bool active,
    required int sortOrder,
  }) async {
    await _bundles.add({
      'name': name,
      'packIds': packIds,
      'price': price,
      'salePrice': salePrice,
      'discountStartAt': discountStartAt != null
          ? Timestamp.fromDate(discountStartAt)
          : null,
      'discountEndAt': discountEndAt != null
          ? Timestamp.fromDate(discountEndAt)
          : null,
      'active': active,
      'sortOrder': sortOrder,
    });
  }

  Future<void> updateBundle(
    String bundleId, {
    required String name,
    required List<String> packIds,
    required int price,
    required int? salePrice,
    required DateTime? discountStartAt,
    required DateTime? discountEndAt,
    required bool active,
    required int sortOrder,
  }) async {
    await _bundles.doc(bundleId).update({
      'name': name,
      'packIds': packIds,
      'price': price,
      'salePrice': salePrice,
      'discountStartAt': discountStartAt != null
          ? Timestamp.fromDate(discountStartAt)
          : null,
      'discountEndAt': discountEndAt != null
          ? Timestamp.fromDate(discountEndAt)
          : null,
      'active': active,
      'sortOrder': sortOrder,
    });
  }

  Future<void> deleteBundle(String bundleId) async {
    await _bundles.doc(bundleId).delete();
  }

  Future<void> reorder(List<String> orderedBundleIds) async {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedBundleIds.length; i++) {
      batch.update(_bundles.doc(orderedBundleIds[i]), {'sortOrder': i});
    }
    await batch.commit();
  }
}
