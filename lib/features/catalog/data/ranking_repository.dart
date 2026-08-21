import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ranking_snapshot.dart';

/// rankingSnapshots 컬렉션 — 홈 탭의 "실시간 랭킹" 섹션이 오늘/어제 스냅샷을
/// 함께 읽는다. 하루 한 번만 바뀌는 데이터라(functions/src/index.ts의
/// computeDailyRankingSnapshot, 매일 KST 00:10) 실시간 구독(snapshots())이
/// 아니라 한 번만 읽는 Future로 충분하다.
class RankingRepository {
  RankingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// 문서 id는 KST(UTC+9) 기준 "YYYY-MM-DD" — 함수 쪽 kstDateKey()와 반드시
  /// 같은 시간대·형식으로 맞춘다. 기기 로컬 시간대에 기대지 않고 UTC에
  /// 명시적으로 9시간을 더해 계산한다.
  Future<RankingSnapshotPair> fetchLatest() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    final todayKey = _dateKey(now);
    final yesterdayKey = _dateKey(now.subtract(const Duration(days: 1)));

    final results = await Future.wait([
      _fetchPackIds(todayKey),
      _fetchPackIds(yesterdayKey),
    ]);

    return RankingSnapshotPair(
      todayPackIds: results[0],
      yesterdayPackIds: results[1],
    );
  }

  Future<List<String>> _fetchPackIds(String dateKey) async {
    try {
      final doc = await _firestore
          .collection('rankingSnapshots')
          .doc(dateKey)
          .get();
      final ids = doc.data()?['packIds'] as List<dynamic>?;
      return ids?.cast<String>() ?? const [];
    } catch (_) {
      // 스냅샷이 아직 한 번도 안 만들어졌거나(배포 직후) 읽기 실패 —
      // 랭킹 섹션이 조용히 숨는 것으로 충분하다(다른 홈 섹션은 계속 동작).
      return const [];
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
