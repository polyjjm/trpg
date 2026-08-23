import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/point_package.dart';

/// pointPackages 컬렉션 — "포인트 상품 관리" 섹션(PointPackageManagementSection)
/// 의 CRUD. GenreRepository/HomeBannerRepository와 같은 구조다. 가격 자체는
/// 결제 승인 시점에 Cloud Function(confirmCoinCharge)이 이 문서를 서버에서
/// 다시 읽어 검증하므로, 여기서 잘못된 값을 저장해도 클라이언트가 임의로
/// 코인을 더 받아가는 일은 없다 — 다만 사용자에게 보여주는 가격/코인 수량
/// 자체는 이 문서가 유일한 원천이다.
class AdminPointPackageRepository {
  AdminPointPackageRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _packages =>
      _firestore.collection('pointPackages');

  /// 관리자 화면 전용 — 비활성 상품까지 전부 보여준다(리더 쪽 사본의
  /// watchWebPackages가 active==true && platform=='web'만 거른다).
  Stream<List<AdminPointPackage>> watchAllPackages() {
    return _packages
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminPointPackage.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> createPackage({
    required String name,
    required int coinAmount,
    required int bonusCoins,
    required int originalPriceKRW,
    required int? salePriceKRW,
    required DateTime? discountStartAt,
    required DateTime? discountEndAt,
    required bool active,
    required int sortOrder,
    required AdminPointPackagePlatform platform,
  }) async {
    await _packages.add({
      'name': name,
      'coinAmount': coinAmount,
      'bonusCoins': bonusCoins,
      'originalPriceKRW': originalPriceKRW,
      'salePriceKRW': salePriceKRW,
      'discountStartAt': discountStartAt != null
          ? Timestamp.fromDate(discountStartAt)
          : null,
      'discountEndAt': discountEndAt != null
          ? Timestamp.fromDate(discountEndAt)
          : null,
      'active': active,
      'sortOrder': sortOrder,
      'platform': platform.wireValue,
    });
  }

  Future<void> updatePackage(
    String packageId, {
    required String name,
    required int coinAmount,
    required int bonusCoins,
    required int originalPriceKRW,
    required int? salePriceKRW,
    required DateTime? discountStartAt,
    required DateTime? discountEndAt,
    required bool active,
    required int sortOrder,
    required AdminPointPackagePlatform platform,
  }) async {
    await _packages.doc(packageId).update({
      'name': name,
      'coinAmount': coinAmount,
      'bonusCoins': bonusCoins,
      'originalPriceKRW': originalPriceKRW,
      'salePriceKRW': salePriceKRW,
      'discountStartAt': discountStartAt != null
          ? Timestamp.fromDate(discountStartAt)
          : null,
      'discountEndAt': discountEndAt != null
          ? Timestamp.fromDate(discountEndAt)
          : null,
      'active': active,
      'sortOrder': sortOrder,
      'platform': platform.wireValue,
    });
  }

  Future<void> deletePackage(String packageId) async {
    await _packages.doc(packageId).delete();
  }
}
