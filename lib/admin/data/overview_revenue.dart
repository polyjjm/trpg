import '../models/revenue_snapshot.dart';
import 'billing_repository.dart';

/// 개요 화면의 매출 카드 4장에 필요한 값만 모은 결과.
///
/// 전부 기존 `revenueSnapshots` 문서에서 나온다 — 새 집계나 새 필드가 없다.
/// [yesterday]가 null이면 어제치 집계가 아직 안 돌았다는 뜻이다
/// (computeDailyRevenueSnapshot은 KST 00:20 실행 — 그 전에는 문서가 없다).
class OverviewRevenue {
  /// 오늘을 제외한 최근 7일 합계. 오늘은 문서 자체가 없어서 항상 빠진다.
  final int weekRevenueKRW;
  final AdminRevenueSnapshot? yesterday;

  const OverviewRevenue({required this.weekRevenueKRW, this.yesterday});
}

/// AdminBillingRepository를 고치지 않고 개요 전용 조회 하나만 덧붙인다 —
/// 공개 메서드([AdminBillingRepository.fetchRevenueRange])만 쓰므로
/// extension으로 충분하고, 결제·정산 탭 쪽 코드를 건드릴 이유가 없다.
extension OverviewRevenueQuery on AdminBillingRepository {
  Future<OverviewRevenue> fetchOverviewRevenue({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final end = today.subtract(const Duration(days: 1));
    final start = today.subtract(const Duration(days: 7));

    final snapshots = await fetchRevenueRange(start, end);
    if (snapshots.isEmpty) {
      return const OverviewRevenue(weekRevenueKRW: 0, yesterday: null);
    }

    final total = snapshots.fold<int>(0, (sum, s) => sum + s.revenueKRW);
    final yesterdayKey = AdminBillingRepository.dateKeyOf(end);
    AdminRevenueSnapshot? yesterday;
    for (final s in snapshots) {
      if (s.dateKey == yesterdayKey) yesterday = s;
    }

    return OverviewRevenue(weekRevenueKRW: total, yesterday: yesterday);
  }
}
