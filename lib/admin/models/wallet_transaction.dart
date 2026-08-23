import 'package:cloud_firestore/cloud_firestore.dart';

/// users/{uid}/wallet/current/transactions/{txId} 문서의 refundStatus.
enum AdminRefundStatus {
  none('none'),
  partial('partial'),
  full('full');

  final String wireValue;
  const AdminRefundStatus(this.wireValue);

  static AdminRefundStatus fromWire(String? value) {
    return AdminRefundStatus.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => AdminRefundStatus.none,
    );
  }
}

/// users/{uid}/wallet/current/transactions/{txId} 문서 중 type == 'charge' —
/// admin "결제내역" 탭 전용 읽기 모델. collectionGroup('transactions') 쿼리로
/// 여러 유저를 가로질러 읽으므로, 문서가 속한 uid를 문서 자체에 저장된
/// [uid] 필드로 들고 있어야 한다(경로의 {uid} 세그먼트는 collectionGroup
/// 쿼리의 필터 대상이 될 수 없다 — refundCoinCharge/confirmCoinCharge가
/// 쓰는 시점에 uid를 그대로 필드로 같이 적어 두는 이유).
class AdminChargeTransaction {
  final String id;
  final String uid;
  final String displayName;
  final String email;
  final String packageId;
  final int coinAmount;
  final int amountKRW;
  final String? relatedPaymentKey;
  final String? cardApproveNo;
  final int refundedCoins;
  final AdminRefundStatus refundStatus;
  final DateTime? createdAt;

  const AdminChargeTransaction({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.email,
    required this.packageId,
    required this.coinAmount,
    required this.amountKRW,
    required this.relatedPaymentKey,
    required this.cardApproveNo,
    required this.refundedCoins,
    required this.refundStatus,
    required this.createdAt,
  });

  factory AdminChargeTransaction.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return AdminChargeTransaction(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      packageId: data['packageId'] as String? ?? '',
      coinAmount: (data['amount'] as num?)?.toInt() ?? 0,
      amountKRW: (data['amountKRW'] as num?)?.toInt() ?? 0,
      relatedPaymentKey: data['relatedPaymentKey'] as String?,
      cardApproveNo: data['cardApproveNo'] as String?,
      refundedCoins: (data['refundedCoins'] as num?)?.toInt() ?? 0,
      refundStatus: AdminRefundStatus.fromWire(data['refundStatus'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// 화면에 미리 보여줄 상한선일 뿐이다 — 실제 환불 가능 코인(지갑 잔액까지
  /// 고려한 min())은 refundCoinCharge Cloud Function이 서버에서 다시
  /// 계산한다(RefundDialog가 그 응답을 보여준다).
  int get refundableCoinsUpperBound => coinAmount - refundedCoins;

  bool get canRefund =>
      refundStatus != AdminRefundStatus.full && refundableCoinsUpperBound > 0;
}

/// type == 'purchase' — admin "코인사용내역" 탭 전용. [bundleId]가 있으면
/// 번들 구매([bundlePackIds]가 이번 구매로 새로 소유하게 된 팩들), 없으면
/// 개별 팩 구매([packId])다.
class AdminPurchaseTransaction {
  final String id;
  final String uid;
  final String displayName;
  final String email;
  final int coins;
  final String? packId;
  final String? bundleId;
  final List<String> bundlePackIds;
  final DateTime? createdAt;

  const AdminPurchaseTransaction({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.email,
    required this.coins,
    required this.packId,
    required this.bundleId,
    required this.bundlePackIds,
    required this.createdAt,
  });

  factory AdminPurchaseTransaction.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return AdminPurchaseTransaction(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      coins: ((data['amount'] as num?)?.toInt() ?? 0).abs(),
      packId: data['packId'] as String?,
      bundleId: data['bundleId'] as String?,
      bundlePackIds:
          (data['packIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isBundle => bundleId != null;
}

/// type == 'refund' — 결제내역 탭에서 "환불됨/부분환불" 판단 자체는 charge
/// 문서의 refundStatus 필드만으로 충분해서 지금은 별도 목록 화면이 없다.
/// 그래도 거래 원장 자체를 나중에 감사/조회할 수 있도록 모델은 만들어 둔다.
class AdminRefundTransaction {
  final String id;
  final String uid;
  final String displayName;
  final String email;
  final String originalChargeTxId;
  final int refundedCoins;
  final int refundedKRW;
  final String? tossCancelTransactionKey;
  final String reason;
  final String processedBy;
  final DateTime? createdAt;

  const AdminRefundTransaction({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.email,
    required this.originalChargeTxId,
    required this.refundedCoins,
    required this.refundedKRW,
    required this.tossCancelTransactionKey,
    required this.reason,
    required this.processedBy,
    required this.createdAt,
  });

  factory AdminRefundTransaction.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return AdminRefundTransaction(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      originalChargeTxId: data['originalChargeTxId'] as String? ?? '',
      refundedCoins: (data['refundedCoins'] as num?)?.toInt() ?? 0,
      refundedKRW: (data['refundedKRW'] as num?)?.toInt() ?? 0,
      tossCancelTransactionKey: data['tossCancelTransactionKey'] as String?,
      reason: data['reason'] as String? ?? '',
      processedBy: data['processedBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
