import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_ids.dart';
import 'monetization_service.dart';

/// AdMob 리워드 광고로 [MonetizationService.showRewardedAd]를 구현한 버전.
///
/// 부활 아이템 구매(`purchaseRevivalItem`)는 광고가 아니라 실제 인앱 결제(IAP)
/// SDK가 필요한 영역이라, SDK가 정해지기 전까지는 항상 실패를 반환한다.
class AdMobMonetizationService implements MonetizationService {
  AdMobMonetizationService();

  RewardedAd? _rewardedAd;
  Future<void>? _loadingFuture;

  /// `main()`에서 앱 시작 시 한 번 호출한다. 웹 빌드에서는 호출하지 않는다.
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  /// 리워드 광고를 미리 로드해 둔다. 부활 화면 진입 시점 등에서 미리 불러
  /// 두면 실제로 "광고 보기" 버튼을 눌렀을 때 대기 시간 없이 보여줄 수 있다.
  ///
  /// 이미 로드가 진행 중일 때 다시 호출되면(예: 화면 진입 시 미리 호출한 로드가
  /// 끝나기 전에 버튼을 눌러 showRewardedAd()가 또 호출하는 경우) 새로 요청을
  /// 보내지 않고, 진행 중인 로드가 끝날 때(onAdLoaded/onAdFailedToLoad) 함께
  /// 완료되는 같은 Future를 반환한다 — RewardedAd.load() 자체가 반환하는
  /// Future는 요청을 보냈다는 뜻일 뿐 로드 완료를 보장하지 않기 때문에
  /// 콜백 기반으로 직접 완료 시점을 관리한다.
  Future<void> preloadRewardedAd() {
    if (_rewardedAd != null) return Future.value();

    final inFlight = _loadingFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _loadingFuture = completer.future;

    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _loadingFuture = null;
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          debugPrint('리워드 광고 로드 실패: $error');
          _rewardedAd = null;
          _loadingFuture = null;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    return completer.future;
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
}
