import 'package:cloud_functions/cloud_functions.dart';

/// confirmCoinCharge 결과 — [newBalance]는 서버가 계산한 최신 잔액이다. 화면은
/// 이 값을 굳이 직접 쓰지 않아도 된다(WalletRepository.watchBalance 스트림이
/// 곧 갱신되어 들어온다) — 그래도 성공 직후 스낵바 등에 바로 쓸 수 있게 같이
/// 돌려준다.
class CoinChargeResult {
  final bool success;
  final int newBalance;
  final bool alreadyProcessed;

  const CoinChargeResult({
    required this.success,
    required this.newBalance,
    required this.alreadyProcessed,
  });
}

/// 코인 충전 결제 승인 — 클라이언트는 Toss 위젯이 돌려준 paymentKey/orderId와
/// 선택했던 packageId만 서버에 넘긴다. 실제 결제 확인(Toss /v1/payments/confirm
/// 호출, 금액 검증)과 코인 지급은 전부 confirmCoinCharge Cloud Function(서버,
/// 비밀키 보유)이 한다 — 클라이언트가 "성공했다"고 주장하는 것만으로는 절대
/// 코인이 지급되지 않는다.
class CoinChargeService {
  CoinChargeService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<CoinChargeResult> confirmCharge({
    required String paymentKey,
    required String orderId,
    required int amount,
    required String packageId,
  }) async {
    final callable = _functions.httpsCallable('confirmCoinCharge');
    final result = await callable.call<Map<String, dynamic>>({
      'paymentKey': paymentKey,
      'orderId': orderId,
      'amount': amount,
      'packageId': packageId,
    });

    final data = result.data;
    return CoinChargeResult(
      success: data['success'] as bool? ?? false,
      newBalance: (data['newBalance'] as num?)?.toInt() ?? 0,
      alreadyProcessed: data['alreadyProcessed'] as bool? ?? false,
    );
  }
}
