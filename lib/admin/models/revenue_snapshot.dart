/// revenueSnapshots/{date}("YYYY-MM-DD" KST) 문서 — admin "정산내역" 탭
/// 전용. functions/src/index.ts의 computeDailyRevenueSnapshot(매일 KST
/// 00:20 예약 실행)이 그 직전 하루치를 집계해 채운다 — 그래서 "오늘"
/// 문서는 다음날 00:20에나 생긴다(오늘 데이터는 아직 없는 게 정상).
class AdminRevenueSnapshot {
  final String dateKey;
  final int revenueKRW;
  final int chargeCount;
  final int coinsGranted;
  final int coinsSpent;
  final int refundedKRW;
  final int refundedCoins;

  const AdminRevenueSnapshot({
    required this.dateKey,
    required this.revenueKRW,
    required this.chargeCount,
    required this.coinsGranted,
    required this.coinsSpent,
    required this.refundedKRW,
    required this.refundedCoins,
  });

  factory AdminRevenueSnapshot.fromFirestore(String dateKey, Map<String, dynamic> json) {
    return AdminRevenueSnapshot(
      dateKey: dateKey,
      revenueKRW: (json['revenueKRW'] as num?)?.toInt() ?? 0,
      chargeCount: (json['chargeCount'] as num?)?.toInt() ?? 0,
      coinsGranted: (json['coinsGranted'] as num?)?.toInt() ?? 0,
      coinsSpent: (json['coinsSpent'] as num?)?.toInt() ?? 0,
      refundedKRW: (json['refundedKRW'] as num?)?.toInt() ?? 0,
      refundedCoins: (json['refundedCoins'] as num?)?.toInt() ?? 0,
    );
  }
}
