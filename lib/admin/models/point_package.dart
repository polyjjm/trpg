import 'package:cloud_firestore/cloud_firestore.dart';

/// pointPackages/{packageId} 문서 — admin이 충전 화면 상품을 관리하는 원본.
/// 리더 쪽 lib/features/wallet/models/point_package.dart와 필드 모양은 같지만,
/// admin/reader가 서로 import하지 않는 기존 관례(genres/homeBanners와 같은
/// 이유)를 그대로 따라 별개 클래스로 둔다.
enum AdminPointPackagePlatform {
  web('web', '웹'),
  android('android', '안드로이드'),
  ios('ios', 'iOS');

  final String wireValue;
  final String label;
  const AdminPointPackagePlatform(this.wireValue, this.label);

  static AdminPointPackagePlatform fromWire(String? value) {
    return AdminPointPackagePlatform.values.firstWhere(
      (p) => p.wireValue == value,
      orElse: () => AdminPointPackagePlatform.web,
    );
  }
}

class AdminPointPackage {
  final String id;
  final String name;
  final int coinAmount;
  final int bonusCoins;
  final int originalPriceKRW;
  final int? salePriceKRW;
  final DateTime? discountStartAt;
  final DateTime? discountEndAt;
  final bool active;
  final int sortOrder;
  final AdminPointPackagePlatform platform;

  const AdminPointPackage({
    required this.id,
    required this.name,
    required this.coinAmount,
    required this.bonusCoins,
    required this.originalPriceKRW,
    required this.salePriceKRW,
    required this.discountStartAt,
    required this.discountEndAt,
    required this.active,
    required this.sortOrder,
    required this.platform,
  });

  factory AdminPointPackage.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminPointPackage(
      id: id,
      name: json['name'] as String? ?? '',
      coinAmount: (json['coinAmount'] as num?)?.toInt() ?? 0,
      bonusCoins: (json['bonusCoins'] as num?)?.toInt() ?? 0,
      originalPriceKRW: (json['originalPriceKRW'] as num?)?.toInt() ?? 0,
      salePriceKRW: (json['salePriceKRW'] as num?)?.toInt(),
      discountStartAt: (json['discountStartAt'] as Timestamp?)?.toDate(),
      discountEndAt: (json['discountEndAt'] as Timestamp?)?.toDate(),
      active: json['active'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      platform: AdminPointPackagePlatform.fromWire(json['platform'] as String?),
    );
  }
}
