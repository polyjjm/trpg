import 'toss_popup_result.dart';

/// 비-웹 플랫폼(모바일)용 no-op — Toss Payments 결제 팝업은 웹 전용이다.
/// 모바일 결제는 별도 네이티브 SDK 연동이 필요하고 아직 없다.
Future<TossPopupResult> openTossPaymentPopup({
  required String clientKey,
  required int amountKRW,
  required String orderId,
  required String orderName,
  required String packageId,
  String? customerName,
  String? customerEmail,
}) async {
  return const TossPopupFailure(message: '코인 충전은 아직 웹에서만 지원돼요.');
}
