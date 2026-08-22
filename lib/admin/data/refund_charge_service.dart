import 'package:cloud_functions/cloud_functions.dart';

/// refundCoinCharge 결과 — 실제로 환불된 금액/코인은 전부 서버가 계산한
/// 값이다(클라이언트는 uid/chargeTxId/reason만 보냈다).
class RefundChargeResult {
  final bool success;
  final int refundedCoins;
  final int refundedKRW;
  final int newBalance;
  final String refundStatus;

  const RefundChargeResult({
    required this.success,
    required this.refundedCoins,
    required this.refundedKRW,
    required this.newBalance,
    required this.refundStatus,
  });
}

/// admin 전용 — 충전 건을 환불한다. purchasePack/confirmCoinCharge와 같은
/// 원칙: 클라이언트는 어떤 금액도 계산해서 보내지 않는다(uid/chargeTxId/
/// reason만). 실제 환불 가능 코인/KRW 계산, admin 권한 확인, Toss 취소
/// API 호출은 전부 refundCoinCharge Cloud Function이 서버에서 한다.
class RefundChargeService {
  RefundChargeService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<RefundChargeResult> refundCharge({
    required String uid,
    required String chargeTxId,
    required String reason,
  }) async {
    final callable = _functions.httpsCallable('refundCoinCharge');
    final result = await callable.call<Map<String, dynamic>>({
      'uid': uid,
      'chargeTxId': chargeTxId,
      'reason': reason,
    });

    final data = result.data;
    return RefundChargeResult(
      success: data['success'] as bool? ?? false,
      refundedCoins: (data['refundedCoins'] as num?)?.toInt() ?? 0,
      refundedKRW: (data['refundedKRW'] as num?)?.toInt() ?? 0,
      newBalance: (data['newBalance'] as num?)?.toInt() ?? 0,
      refundStatus: data['refundStatus'] as String? ?? 'none',
    );
  }
}
