import 'monetization_service.dart';

/// 실제 IAP/광고 SDK가 붙기 전까지 쓰는 기본 구현. 항상 실패를 반환한다.
class NoOpMonetizationService implements MonetizationService {
  const NoOpMonetizationService();

  @override
  Future<bool> showRewardedAd() async {
    // TODO: 실제 리워드 광고 SDK 연동 지점.
    return false;
  }

  @override
  Future<bool> purchaseRevivalItem() async {
    // TODO: 실제 인앱 결제(IAP) SDK 연동 지점.
    return false;
  }
}
