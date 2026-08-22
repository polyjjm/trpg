import 'package:cloud_functions/cloud_functions.dart';

/// purchaseBundle 결과 — [newBalance]는 서버가 계산한 최신 코인 잔액이고,
/// [newlyOwnedPackIds]는 이번 구매로 새로 소유하게 된 팩 id 목록이다(이미
/// 갖고 있던 팩은 빠진다 — 부분 보유 프로레이팅 참고).
class PurchaseBundleResult {
  final bool success;
  final int newBalance;
  final List<String> newlyOwnedPackIds;

  const PurchaseBundleResult({
    required this.success,
    required this.newBalance,
    required this.newlyOwnedPackIds,
  });
}

/// 코인으로 번들을 구매한다 — PurchasePackService/CoinChargeService와 같은
/// 원칙: 클라이언트는 bundleId만 서버(purchaseBundle Cloud Function)에
/// 넘긴다. 가격 조회(서버가 packBundles 문서를 직접 다시 읽는다), 이미
/// 보유한 팩을 뺀 프로레이팅 계산, 잔액 확인/차감, 소유권 부여는 전부
/// 서버가 트랜잭션으로 처리한다.
class PurchaseBundleService {
  PurchaseBundleService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<PurchaseBundleResult> purchaseBundle({required String bundleId}) async {
    final callable = _functions.httpsCallable('purchaseBundle');
    final result = await callable.call<Map<String, dynamic>>({
      'bundleId': bundleId,
    });

    final data = result.data;
    return PurchaseBundleResult(
      success: data['success'] as bool? ?? false,
      newBalance: (data['newBalance'] as num?)?.toInt() ?? 0,
      newlyOwnedPackIds:
          (data['newlyOwnedPackIds'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}
