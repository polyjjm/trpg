/// 캐시(재화) 충전 상품 한 종류.
class CashPackage {
  final String id;

  /// 원 단위 가격.
  final int priceWon;

  /// 기본 지급 캐시.
  final int cashAmount;

  /// 추가로 얹어 주는 보너스 캐시. 없으면 0.
  final int bonusCashAmount;

  const CashPackage({
    required this.id,
    required this.priceWon,
    required this.cashAmount,
    required this.bonusCashAmount,
  });

  /// 구매 성공 시 실제로 지급되는 총 캐시(기본 + 보너스).
  int get totalCashAmount => cashAmount + bonusCashAmount;
}
