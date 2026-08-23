/// openKakaoLoginPopup()의 결과 — toss_popup_result.dart의 TossPopupResult와
/// 정확히 같은 구조(같은 팝업+postMessage 패턴을 공유한다).
sealed class KakaoPopupResult {
  const KakaoPopupResult();
}

/// 카카오가 인가 코드(authorization code)를 돌려줬다는 뜻이다 — 아직
/// 로그인이 끝난 게 아니다. 이 코드를 kakaoSignIn Cloud Function에 넘겨서
/// 서버가 카카오 REST API 키/클라이언트 시크릿으로 액세스 토큰과 교환하고,
/// 그 토큰으로 카카오 사용자 정보를 직접 확인한 뒤에야 Firebase 커스텀
/// 토큰이 발급된다 — 클라이언트가 돌려받은 code 자체는 절대 신뢰의 근거가
/// 아니다.
class KakaoPopupSuccess extends KakaoPopupResult {
  final String code;

  const KakaoPopupSuccess({required this.code});
}

/// 카카오가 실패/거부 사유를 안고 돌아왔다(예: 사용자가 동의 화면에서 취소).
class KakaoPopupFailure extends KakaoPopupResult {
  final String message;

  const KakaoPopupFailure({required this.message});
}

/// 결과 메시지 없이 사용자가 팝업 창을 직접 닫았다.
class KakaoPopupCancelled extends KakaoPopupResult {
  const KakaoPopupCancelled();
}

/// 브라우저가 window.open() 자체를 차단했다(팝업 차단기).
class KakaoPopupBlocked extends KakaoPopupResult {
  const KakaoPopupBlocked();
}
