import '../../../core/monetization/cash_package.dart';

/// 하드코딩된 캐시 충전 상품 목록. 캐시 단가는 11원으로 통일하고,
/// 상품이 커질수록 보너스 비율을 늘렸다(0% → 10% → 15% → 20%).
final List<CashPackage> cashPackages = [
  const CashPackage(
    id: 'cash_100',
    priceWon: 1100,
    cashAmount: 100,
    bonusCashAmount: 0,
  ),
  const CashPackage(
    id: 'cash_500',
    priceWon: 5500,
    cashAmount: 500,
    bonusCashAmount: 50,
  ),
  const CashPackage(
    id: 'cash_1000',
    priceWon: 11000,
    cashAmount: 1000,
    bonusCashAmount: 150,
  ),
  const CashPackage(
    id: 'cash_5000',
    priceWon: 55000,
    cashAmount: 5000,
    bonusCashAmount: 1000,
  ),
];
