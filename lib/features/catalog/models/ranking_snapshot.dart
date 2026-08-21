/// rankingSnapshots/{date}(KST "YYYY-MM-DD") 문서 두 개(오늘/어제)를 함께
/// 들고 있는 값 객체 — RankingSection이 오늘 배열의 인덱스로 순위를, 어제
/// 배열과의 인덱스 비교로 순위 변동(▲/▼/-/NEW)을 계산한다. 스키마 자체는
/// {packIds: [...]} 하나뿐이라(functions/src/index.ts의
/// computeDailyRankingSnapshot 참고) 델타를 문서에 미리 구워두지 않고 항상
/// 클라이언트에서 그때그때 비교한다.
class RankingSnapshotPair {
  final List<String> todayPackIds;
  final List<String> yesterdayPackIds;

  const RankingSnapshotPair({
    required this.todayPackIds,
    required this.yesterdayPackIds,
  });

  static const empty = RankingSnapshotPair(todayPackIds: [], yesterdayPackIds: []);
}
