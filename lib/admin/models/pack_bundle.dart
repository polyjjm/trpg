import 'package:cloud_firestore/cloud_firestore.dart';

/// packBundles/{bundleId} 문서 — admin이 관리하는, 스토리팩 여러 개를 묶어
/// 코인으로 할인 판매하는 번들. pointPackages와 같은 "코인 + 선택적 할인
/// 기간" 가격 모델을 공유하지만(가격 단위만 KRW 대신 코인), 승인 게이트
/// 없이 admin이 직접 만들고 바로 반영된다는 점도 pointPackages/homeBanners와
/// 같다 — storyPacks처럼 draft/liveMetadata 이중 게이트가 없다.
class AdminPackBundle {
  final String id;
  final String name;
  final List<String> packIds;
  final int price;
  final int? salePrice;
  final DateTime? discountStartAt;
  final DateTime? discountEndAt;
  final bool active;
  final int sortOrder;

  const AdminPackBundle({
    required this.id,
    required this.name,
    required this.packIds,
    required this.price,
    required this.salePrice,
    required this.discountStartAt,
    required this.discountEndAt,
    required this.active,
    required this.sortOrder,
  });

  factory AdminPackBundle.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminPackBundle(
      id: id,
      name: json['name'] as String? ?? '',
      packIds: (json['packIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      price: (json['price'] as num?)?.toInt() ?? 0,
      salePrice: (json['salePrice'] as num?)?.toInt(),
      discountStartAt: (json['discountStartAt'] as Timestamp?)?.toDate(),
      discountEndAt: (json['discountEndAt'] as Timestamp?)?.toDate(),
      active: json['active'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  /// [at] 시점에 할인가가 적용 중인지 — AdminPointPackage.isDiscountActiveAt/
  /// AdminStoryPack.isDiscountActiveAt과 같은 모양.
  bool isDiscountActiveAt(DateTime at) {
    if (salePrice == null) return false;
    final start = discountStartAt;
    if (start != null && at.isBefore(start)) return false;
    final end = discountEndAt;
    if (end != null && at.isAfter(end)) return false;
    return true;
  }

  bool get hasActiveDiscount => isDiscountActiveAt(DateTime.now());

  /// admin 미리보기용 "지금 적용 중인 가격" — 부분 보유 프로레이팅 전,
  /// 전체 팩을 하나도 안 가진 구매자 기준의 정가/할인가다. 실제 구매
  /// 시점의 프로레이팅 계산은 purchaseBundle Cloud Function이 서버에서
  /// 한다(functions/src/index.ts).
  int get effectivePrice => hasActiveDiscount ? salePrice! : price;
}
