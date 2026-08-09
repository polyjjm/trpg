import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_ids.dart';
import 'cash_package.dart';
import 'monetization_service.dart';

/// AdMob 리워드 광고로 [MonetizationService.showRewardedAd]를 구현한 버전.
///
/// 부활 아이템 구매(`purchaseRevivalItem`)와 캐시 패키지 구매(`purchaseCashPackage`)는
/// 광고가 아니라 실제 인앱 결제(IAP) SDK가 필요한 영역이라, SDK가 정해지기 전까지는
/// [NoOpMonetizationService]와 동일하게 항상 실패를 반환한다.
class AdMobMonetizationService implements MonetizationService {
  AdMobMonetizationService();

  RewardedAd? _rewardedAd;
  bool _isLoadingRewardedAd = false;

  /// `main()`에서 앱 시작 시 한 번 호출한다. 웹 빌드에서는 호출하지 않는다.
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  /// 리워드 광고를 미리 로드해 둔다. 부활 화면 진입 시점 등에서 미리 불러
  /// 두면 실제로 "광고 보기" 버튼을 눌렀을 때 대기 시간 없이 보여줄 수 있다.
  Future<void> preloadRewardedAd() async {
    if (_rewardedAd != null || _isLoadingRewardedAd) return;
    _isLoadingRewardedAd = true;

    await RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoadingRewardedAd = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('리워드 광고 로드 실패: $error');
          _rewardedAd = null;
          _isLoadingRewardedAd = false;
        },
      ),
    );
  }

  @override
  Future<bool> showRewardedAd() async {
    // 미리 로드해 둔 광고가 없으면 지금 로드를 시도한다.
    if (_rewardedAd == null) {
      await preloadRewardedAd();
    }

    final ad = _rewardedAd;
    if (ad == null) {
      // 광고 로드에 실패했으면 시청 자체가 불가능하므로 false.
      return false;
    }

    _rewardedAd = null;

    var earnedReward = false;
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        // 다음 시청을 위해 미리 다시 로드해 둔다.
        preloadRewardedAd();
        if (!completer.isCompleted) completer.complete(earnedReward);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('리워드 광고 표시 실패: $error');
        ad.dispose();
        preloadRewardedAd();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await ad.show(
      onUserEarnedReward: (ad, reward) {
        earnedReward = true;
      },
    );

    return completer.future;
  }

  @override
  Future<bool> purchaseRevivalItem() async {
    // TODO: 실제 인앱 결제(IAP) SDK 연동 지점.
    return false;
  }

  @override
  Future<CashPurchaseResult> purchaseCashPackage(CashPackage package) async {
    // TODO: 실제 인앱 결제(IAP) SDK 연동 지점.
    return CashPurchaseResult.failure;
  }
}
