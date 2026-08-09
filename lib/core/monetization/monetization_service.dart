import 'cash_package.dart';

/// 인앱 결제 / 광고 관련 기능을 위한 추상화.
///
/// CLAUDE.md의 "Death / Revival system", "Monetization" 절에서 계획한 부활 아이템 구매·
/// 리워드 광고 시청·캐시 충전을 위한 자리(seam)만 잡아 둔다. 실제 IAP/광고 SDK가 정해지면
/// 이 인터페이스를 구현하는 새 클래스로 교체한다 — 지금은 [NoOpMonetizationService]만
/// 있고, 실제 결제는 항상 실패로 처리된다.
abstract class MonetizationService {
  /// 리워드 광고를 보여준다. 끝까지 시청을 완료했을 때만 true를 반환한다.
  Future<bool> showRewardedAd();

  /// 부활 아이템(유료 재화)을 구매한다. 구매에 성공했을 때만 true를 반환한다.
  Future<bool> purchaseRevivalItem();

  /// 캐시(재화) 패키지를 구매한다.
  /// 성공 시 호출부가 GameState.addCash(package.totalCashAmount)를 호출해 잔액에 반영한다.
  Future<CashPurchaseResult> purchaseCashPackage(CashPackage package);
}

/// [MonetizationService.purchaseCashPackage] 결과.
enum CashPurchaseResult { success, failure }
