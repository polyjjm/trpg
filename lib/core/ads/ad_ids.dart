import 'dart:io';

import 'package:flutter/foundation.dart';

/// AdMob 광고 단위 ID 모음.
///
/// 디버그 빌드에서는 항상 구글 공식 테스트 ID를 사용하고,
/// 릴리즈 빌드에서만 실제 광고 단위 ID를 사용한다.
/// (테스트 중 실제 광고를 클릭/노출시키면 AdMob 계정이 정지될 수 있으므로
///  절대 디버그 빌드에서 실제 ID를 노출하지 않는다.)
class AdIds {
  AdIds._();

  /// 배너 광고 단위 ID
  static String get banner {
    if (!kReleaseMode) return _testBanner;
    if (Platform.isAndroid) return _androidBanner;
    if (Platform.isIOS) return _iosBanner;
    return _testBanner;
  }

  /// 전면 광고 단위 ID
  static String get interstitial {
    if (!kReleaseMode) return _testInterstitial;
    if (Platform.isAndroid) return _androidInterstitial;
    if (Platform.isIOS) return _iosInterstitial;
    return _testInterstitial;
  }

  /// 리워드(보상형) 광고 단위 ID
  ///
  /// 부활용 리워드 광고 단위는 아직 AdMob 콘솔에서 발급받지 않았다.
  /// "광고 단위 추가" → 보상형(Rewarded) 선택해서 만든 뒤
  /// [_androidRewarded] / [_iosRewarded] 값을 실제 ID로 교체할 것.
  /// 그전까지는 릴리즈 빌드에서도 구글 공식 테스트 ID를 사용한다.
  static String get rewarded {
    if (!kReleaseMode) return _testRewarded;
    if (Platform.isAndroid) return _androidRewarded;
    if (Platform.isIOS) return _iosRewarded;
    return _testRewarded;
  }

  // ---- 실제 광고 단위 ID (릴리즈 전용) ----
  static const _androidBanner = 'ca-app-pub-8340992511391681/4160955445';
  static const _androidInterstitial = 'ca-app-pub-8340992511391681/2847873773';

  // TODO: AdMob 콘솔에서 보상형 광고 단위를 만든 뒤 실제 ID로 교체.
  static const _androidRewarded = _testRewarded;

  // iOS용 광고 단위는 아직 발급되지 않았다.
  // AdMob 콘솔에서 iOS 앱을 등록하고 배너/전면/리워드 광고 단위를 만든 뒤
  // 아래 값들을 실제 ID로 교체할 것.
  static const _iosBanner = _testBanner;
  static const _iosInterstitial = _testInterstitial;
  static const _iosRewarded = _testRewarded;

  // ---- 구글 공식 테스트 ID (디버그 전용, 절대 실제 ID로 바꾸지 말 것) ----
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
}
