import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'kakao_popup_result.dart';

/// 카카오 로그인 팝업을 연다 — 메인 탭은 절대 이동/새로고침되지 않는다
/// (toss_payments_web.dart의 openTossPaymentPopup과 정확히 같은 패턴).
///
/// 흐름: 이 함수가 카카오의 OAuth 인가 엔드포인트(kauth.kakao.com/oauth/
/// authorize)를 곧장 팝업으로 연다 — Toss와 달리 별도의 SDK 초기화가 필요
/// 없어서(카카오 JS SDK를 아예 안 쓴다, 아래 참고) 우리 오리진의 중간
/// launch 페이지도 필요 없다. 사용자가 카카오 로그인/동의를 마치면 카카오가
/// 그 팝업을 [redirectUri](우리 오리진의 web/kakao_login_return.html, 카카오
/// 개발자 콘솔에 미리 등록해 둬야 한다)로 돌려보내고, 그 페이지가
/// postMessage로 인가 코드를 이 함수(=메인 탭, window.opener)에 알린 뒤
/// 스스로 닫힌다.
///
/// 카카오 JS SDK를 안 쓰는 이유: 카카오의 현재 로그인 흐름은
/// `Kakao.Auth.authorize()`를 쓰든 안 쓰든 결국 순수한 OAuth 인가 코드
/// 요청(그냥 URL)일 뿐이라, SDK를 통째로 불러와 초기화할 필요 없이 이
/// 함수가 그 URL을 직접 조립해서 연다 — 로드할 외부 스크립트가 늘지 않는다.
///
/// 반드시 버튼 클릭 핸들러 안에서, 그 전에 await를 한 번도 거치지 않고 곧장
/// 호출해야 한다 — html.window.open()이 클릭 이벤트와 같은 JS 태스크 안에서
/// 동기적으로 실행돼야 브라우저 팝업 차단기를 피할 수 있다.
Future<KakaoPopupResult> openKakaoLoginPopup({
  required String jsKey,
  required String redirectUri,
}) {
  final authorizeUrl = Uri.https('kauth.kakao.com', '/oauth/authorize', {
    'client_id': jsKey,
    'redirect_uri': redirectUri,
    'response_type': 'code',
  });

  // dart:html의 Window.open()은 WindowBase(널 불가)로 타입이 잡혀 있지만,
  // 실제 브라우저는 팝업이 차단되면 null을 돌려준다(toss_payments_web.dart와
  // 같은 알려진 허점) — 정적 타입을 믿지 않고 dynamic으로 받는다.
  final dynamic popup = html.window.open(
    authorizeUrl.toString(),
    'kakao_login_popup',
    'width=420,height=650,menubar=no,toolbar=no,location=no,status=no,scrollbars=yes',
  );

  final completer = Completer<KakaoPopupResult>();
  StreamSubscription<html.MessageEvent>? messageSub;
  Timer? closedCheckTimer;
  var settled = false;

  void settle(KakaoPopupResult result) {
    if (settled) return;
    settled = true;
    messageSub?.cancel();
    closedCheckTimer?.cancel();
    completer.complete(result);
  }

  if (popup == null) {
    settle(const KakaoPopupBlocked());
    return completer.future;
  }

  messageSub = html.window.onMessage.listen((event) {
    // 보안: 우리 오리진에서 온 메시지만 신뢰한다 — 팝업이 로그인이 진행되는
    // 동안 카카오 쪽 페이지(다른 오리진)에 가 있더라도, 그쪽에서 온 메시지는
    // 여기서 전부 무시된다. kakao_login_return.html도 postMessage의
    // targetOrigin을 우리 오리진으로 명시해서 보내므로 이중으로 막혀 있다.
    if (event.origin != html.window.location.origin) return;

    final raw = event.data;
    if (raw is! String) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (data['type'] != 'KAKAO_LOGIN_RESULT') return;

    final code = data['code'] as String?;
    if (code != null && code.isNotEmpty) {
      settle(KakaoPopupSuccess(code: code));
    } else {
      settle(
        KakaoPopupFailure(
          message: data['error'] as String? ?? '카카오 로그인이 취소됐어요.',
        ),
      );
    }
  });

  // 결과 메시지 없이 사용자가 팝업을 직접 닫은 경우(취소) 감지 — Toss
  // 팝업과 같은 방식(0.5초마다 확인).
  closedCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (popup.closed == true) {
      settle(const KakaoPopupCancelled());
    }
  });

  return completer.future;
}
