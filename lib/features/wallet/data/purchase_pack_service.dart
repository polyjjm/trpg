import 'package:cloud_functions/cloud_functions.dart';

/// purchasePack 결과 — [newBalance]는 서버가 계산한 최신 코인 잔액이다.
/// [alreadyOwned]가 true면 이미 보유 중이었거나(재구매), 팩이 무료라 과금
/// 없이 소유만 확인됐다는 뜻이다(코인은 안 깎였다).
class PurchasePackResult {
  final bool success;
  final bool alreadyOwned;
  final int newBalance;

  const PurchasePackResult({
    required this.success,
    required this.alreadyOwned,
    required this.newBalance,
  });
}

/// 코인으로 이야기 팩을 구매한다 — CoinChargeService와 같은 원칙: 클라이언트는
/// packId만 서버(purchasePack Cloud Function)에 넘긴다. 가격 조회(서버가
/// storyPacks 문서를 직접 다시 읽는다), 잔액 확인/차감, 소유권 부여는 전부
/// 서버가 트랜잭션으로 처리한다 — 클라이언트가 직접 잔액을 깎거나 소유권을
/// 스스로 부여할 방법은 없다.
class PurchasePackService {
  PurchasePackService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<PurchasePackResult> purchasePack({required String packId}) async {
    final callable = _functions.httpsCallable('purchasePack');
    final result = await callable.call<Map<String, dynamic>>({
      'packId': packId,
    });

    final data = result.data;
    return PurchasePackResult(
      success: data['success'] as bool? ?? false,
      alreadyOwned: data['alreadyOwned'] as bool? ?? false,
      newBalance: (data['newBalance'] as num?)?.toInt() ?? 0,
    );
  }
}
