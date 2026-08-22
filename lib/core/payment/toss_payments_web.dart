import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'toss_popup_result.dart';

/// Toss 결제 팝업을 연다 — 메인 탭은 절대 이동/새로고침되지 않는다.
///
/// 흐름: 이 함수가 먼저 우리 오리진의 web/payment_popup_launch.html을
/// 팝업으로 연다(우리 오리진이라 팝업 차단 걱정 없이 즉시 열 수 있다). 그
/// 페이지가 스스로 Toss SDK를 불러와 TossPayments(clientKey).requestPayment(...)
/// 를 호출해서, 팝업 "안에서만" Toss의 실제 결제 페이지로 이동한다. 결제가
/// 끝나면 Toss가 그 팝업을 web/payment_popup_return.html(다시 우리
/// 오리진)로 돌려보내고, 그 페이지가 postMessage로 결과를 이 함수(=메인 탭,
/// window.opener)에 알린 뒤 스스로 닫힌다.
///
/// 반드시 버튼 클릭 핸들러 안에서, 그 전에 await를 한 번도 거치지 않고 곧장
/// 호출해야 한다 — html.window.open()이 클릭 이벤트와 같은 JS 태스크
/// 안에서 동기적으로 실행돼야 브라우저 팝업 차단기를 피할 수 있다(아래 URL
/// 조립은 전부 동기 코드라 이 함수 진입 시점부터 window.open 호출까지
/// await가 없다).
Future<TossPopupResult> openTossPaymentPopup({
  required String clientKey,
  required int amountKRW,
  required String orderId,
  required String orderName,
  required String packageId,
  String? customerName,
  String? customerEmail,
}) {
  final launchUrl = Uri.base.resolve('payment_popup_launch.html').replace(
    queryParameters: {
      'clientKey': clientKey,
      'amount': '$amountKRW',
      'orderId': orderId,
      'orderName': orderName,
      'packageId': packageId,
      if (customerName != null) 'customerName': customerName,
      if (customerEmail != null) 'customerEmail': customerEmail,
    },
  );

  // dart:html의 Window.open()은 WindowBase(널 불가)로 타입이 잡혀 있지만,
  // 실제 브라우저는 팝업이 차단되면 null을 돌려준다 — 그 타입 선언이
  // 정확하지 않다(오래돼 유지보수가 끊긴 dart:html의 알려진 허점). 정적
  // 타입을 믿지 않고 dynamic으로 받아서 실제 런타임 값을 그대로 널 체크한다.
  final dynamic popup = html.window.open(
    launchUrl.toString(),
    'toss_payment_popup',
    'width=420,height=650,menubar=no,toolbar=no,location=no,status=no,scrollbars=yes',
  );

  final completer = Completer<TossPopupResult>();
  StreamSubscription<html.MessageEvent>? messageSub;
  Timer? closedCheckTimer;
  var settled = false;

  void settle(TossPopupResult result) {
    if (settled) return;
    settled = true;
    messageSub?.cancel();
    closedCheckTimer?.cancel();
    completer.complete(result);
  }

  if (popup == null) {
    settle(const TossPopupBlocked());
    return completer.future;
  }

  messageSub = html.window.onMessage.listen((event) {
    // 보안: 우리 오리진에서 온 메시지만 신뢰한다 — 팝업이 결제가 진행되는
    // 동안 Toss 쪽 페이지(다른 오리진)에 가 있더라도, 그쪽에서 온 메시지는
    // 여기서 전부 무시된다. payment_popup_return.html도 postMessage의
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
    if (data['type'] != 'TOSS_PAYMENT_RESULT') return;

    if (data['success'] == true) {
      final resultAmount = int.tryParse('${data['amount']}');
      final paymentKey = data['paymentKey'] as String?;
      final resultOrderId = data['orderId'] as String?;
      if (resultAmount == null || paymentKey == null || resultOrderId == null) {
        settle(const TossPopupFailure(message: '결제 결과를 확인하지 못했어요.'));
        return;
      }
      settle(
        TossPopupSuccess(
          paymentKey: paymentKey,
          orderId: resultOrderId,
          amount: resultAmount,
        ),
      );
    } else {
      settle(
        TossPopupFailure(
          message: data['message'] as String? ?? '결제가 취소됐어요.',
        ),
      );
    }
  });

  // 결과 메시지 없이 사용자가 팝업을 직접 닫은 경우(취소) 감지 — 0.5초마다
  // 확인한다. 결과가 이미 도착해 settle()이 끝난 뒤(팝업이 스스로 닫히는
  // 정상 경로 포함)라면 settled 가드 덕분에 여기서 또 완료 처리되지 않는다.
  closedCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (popup.closed == true) {
      settle(const TossPopupCancelled());
    }
  });

  return completer.future;
}
