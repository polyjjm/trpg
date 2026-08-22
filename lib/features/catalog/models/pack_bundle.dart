/// packBundles/{bundleId} 문서 — 스토리팩 여러 개를 묶어 코인으로 할인
/// 판매하는 번들. lib/admin/models/pack_bundle.dart와 필드 모양은 같지만,
/// admin/reader가 서로 import하지 않는 기존 관례(genres/homeBanners/
/// pointPackages와 같은 이유)를 그대로 따라 별개 클래스로 둔다.
class PackBundle {
  final String id;
  final String name;
  final List<String> packIds;
  final int price;
  final int? salePrice;
  final DateTime? discountStartAt;
  final DateTime? discountEndAt;

  const PackBundle({
    required this.id,
    required this.name,
    required this.packIds,
    required this.price,
    this.salePrice,
    this.discountStartAt,
    this.discountEndAt,
  });

  /// [at] 시점에 할인가가 적용 중인지 — StoryPack.isDiscountActiveAt/
  /// PointPackage.isDiscountActiveAt과 같은 모양(전부 "코인 + 선택적 할인
  /// 기간" 가격 모델을 공유한다).
  bool isDiscountActiveAt(DateTime at) {
    if (salePrice == null) return false;
    final start = discountStartAt;
    if (start != null && at.isBefore(start)) return false;
    final end = discountEndAt;
    if (end != null && at.isAfter(end)) return false;
    return true;
  }

  bool get hasActiveDiscount => isDiscountActiveAt(DateTime.now());

  /// 전체 팩을 하나도 안 가진 구매자 기준 가격 — 실제로 얼마를 내는지는
  /// [amountToChargeFor]로 이미 보유한 팩을 뺀 프로레이팅 값을 써야 한다.
  int get effectivePrice => hasActiveDiscount ? salePrice! : price;

  /// [ownedPackIds] 중 이 번들에 포함되지 않았거나 안 겹치는 것과 무관하게,
  /// packIds 중 이미 보유한 것의 개수.
  int ownedCountAmong(Set<String> ownedPackIds) =>
      packIds.where(ownedPackIds.contains).length;

  /// 서버(purchaseBundle Cloud Function)와 정확히 같은 프로레이팅 계산 —
  /// 화면에 "N코인만 더 내면돼요"를 미리 보여주는 용도다(실제 청구 금액의
  /// 유일한 원천은 서버). 전부 이미 보유 중이면 0을 돌려준다 — 호출부가
  /// "구매할 게 없다"는 걸 따로 판단해야 한다(canPurchaseGiven 참고).
  int amountToChargeFor(Set<String> ownedPackIds) {
    final total = packIds.length;
    if (total == 0) return 0;
    final unowned = total - ownedCountAmong(ownedPackIds);
    if (unowned <= 0) return 0;
    return (effectivePrice * unowned / total).round();
  }

  bool canPurchaseGiven(Set<String> ownedPackIds) =>
      ownedCountAmong(ownedPackIds) < packIds.length;
}
