import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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
    debugPrint('[랭킹] fetchLatest 시작 — todayKey=$todayKey, yesterdayKey=$yesterdayKey');

    final results = await Future.wait([
      _fetchPackIds(todayKey),
      _fetchPackIds(yesterdayKey),
    ]);

    debugPrint(
      '[랭킹] fetchLatest 완료 — today ${results[0].length}개, yesterday ${results[1].length}개',
    );
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
      if (!doc.exists) {
        // ⚠️ 진단용 — computeDailyRankingSnapshot(매일 KST 00:10)이 아직 이
        // 날짜로 한 번도 안 돌았을 수 있다(배포 직후, 로컬/테스트 데이터
        // 리셋 직후 등) — 이 경우 문서 자체가 없는 게 정상이라 빈 배열을
        // 돌려주는 게 맞다. 하지만 permission-denied 등 진짜 에러와
        // "문서가 원래 없음"을 구분하려면 이 로그가 필요하다.
        debugPrint('[랭킹] rankingSnapshots/$dateKey 문서 없음(아직 집계 안 됨)');
        return const [];
      }
      final ids = doc.data()?['packIds'] as List<dynamic>?;
      debugPrint('[랭킹] rankingSnapshots/$dateKey 문서 있음 — packIds ${ids?.length ?? 0}개');
      return ids?.cast<String>() ?? const [];
    } catch (e, stackTrace) {
      // ⚠️ 이 프로젝트에서 반복된 실패 패턴 — catch (_)로 조용히 삼키면
      // permission-denied 같은 진짜 에러가 "데이터가 원래 없음"과 구분이
      // 안 된다. 랭킹 섹션이 조용히 숨는 동작 자체는 유지하되(다른 홈
      // 섹션은 계속 동작해야 하니), 원인은 반드시 콘솔에 남긴다.
      debugPrint('[랭킹] rankingSnapshots/$dateKey 조회 실패: $e\n$stackTrace');
      return const [];
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
