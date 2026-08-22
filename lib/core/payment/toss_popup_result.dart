/// openTossPaymentPopup()의 결과 — 팝업이 결과 메시지를 보내고 스스로 닫힐
/// 때까지, 또는 사용자가 결과 없이 팝업을 직접 닫을 때까지, 또는 팝업 자체가
/// 차단됐을 때까지 기다린 뒤 이 중 하나로 확정된다.
sealed class TossPopupResult {
  const TossPopupResult();
}

/// Toss가 결제를 확인해 줬다는 뜻이다 — 아직 코인이 지급된 건 아니다.
/// [paymentKey]/[orderId]/[amount]를 그대로 confirmCoinCharge Cloud Function에
/// 넘겨서 서버가 다시 검증한 뒤에야 코인이 지급된다.
class TossPopupSuccess extends TossPopupResult {
  final String paymentKey;
  final String orderId;
  final int amount;

  const TossPopupSuccess({
    required this.paymentKey,
    required this.orderId,
    required this.amount,
  });
}

/// Toss가 결제 실패/취소 사유를 안고 돌아왔다(예: 카드 한도 초과, 사용자가
/// Toss 결제 페이지 안에서 취소).
class TossPopupFailure extends TossPopupResult {
  final String message;

  const TossPopupFailure({required this.message});
}

/// 결과 메시지 없이 사용자가 팝업 창을 직접 닫았다 — 실패가 아니라 단순
/// 취소로 취급한다(에러 다이얼로그를 띄우지 않는다).
class TossPopupCancelled extends TossPopupResult {
  const TossPopupCancelled();
}

/// 브라우저가 window.open() 자체를 차단했다(팝업 차단기).
class TossPopupBlocked extends TossPopupResult {
  const TossPopupBlocked();
}
