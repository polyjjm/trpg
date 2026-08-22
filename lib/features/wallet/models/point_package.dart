import 'package:cloud_firestore/cloud_firestore.dart';

/// pointPackages/{packageId} — 충전 화면(ChargePage)에 노출되는 코인 상품.
/// admin 쪽 lib/admin/models/point_package.dart와 필드 모양은 같지만,
/// lib/features/**는 lib/admin/을 절대 import하지 않는다는 프로젝트 규칙
/// (CLAUDE.md, 모바일 빌드가 admin 코드를 안 끌어오게) 때문에 genres/
/// homeBanners와 같은 패턴으로 별개 클래스로 둔다.
enum PointPackagePlatform {
  web('web'),
  android('android'),
  ios('ios');

  final String wireValue;
  const PointPackagePlatform(this.wireValue);

  static PointPackagePlatform fromWire(String? value) {
    return PointPackagePlatform.values.firstWhere(
      (p) => p.wireValue == value,
      orElse: () => PointPackagePlatform.web,
    );
  }
}

class PointPackage {
  final String id;
  final String name;
  final int coinAmount;
  final int bonusCoins;
  final int originalPriceKRW;

  /// 할인가 — null이면 할인 없음.
  final int? salePriceKRW;
  final DateTime? discountStartAt;
  final DateTime? discountEndAt;
  final bool active;
  final int sortOrder;
  final PointPackagePlatform platform;

  const PointPackage({
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

  factory PointPackage.fromFirestore(String id, Map<String, dynamic> json) {
    return PointPackage(
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
      platform: PointPackagePlatform.fromWire(json['platform'] as String?),
    );
  }

  /// 총 지급 코인(기본 + 보너스) — 결제 성공 시 서버가 실제로 지급하는 양과
  /// 같은 계산이지만, 여기는 어디까지나 화면 표시용이다. 실제 지급량은
  /// Cloud Function이 이 문서를 서버에서 다시 읽어 계산한다(클라이언트 값을
  /// 신뢰하지 않는다).
  int get totalCoinAmount => coinAmount + bonusCoins;

  /// [at] 시점에 할인가가 적용 중인지 — salePriceKRW가 있고, 시작/종료일이
  /// 없거나 그 범위 안일 때. 두 필드 다 nullable이라 HomeBannerRepository의
  /// _isWithinWindow와 같은 모양으로 판정한다.
  bool isDiscountActiveAt(DateTime at) {
    if (salePriceKRW == null) return false;
    final start = discountStartAt;
    if (start != null && at.isBefore(start)) return false;
    final end = discountEndAt;
    if (end != null && at.isAfter(end)) return false;
    return true;
  }

  bool get hasActiveDiscount => isDiscountActiveAt(DateTime.now());

  /// 지금 이 순간 실제로 결제해야 할 금액 — 할인 중이면 salePriceKRW, 아니면
  /// originalPriceKRW. Cloud Function이 서버 시각 기준으로 다시 계산하는 값과
  /// 반드시 일치해야 하므로(신뢰의 원천은 서버), 이 값은 화면 표시와 Toss
  /// 위젯에 넘길 금액에만 쓴다.
  int get currentPriceKRW =>
      hasActiveDiscount ? salePriceKRW! : originalPriceKRW;
}
