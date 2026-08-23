import 'package:cloud_functions/cloud_functions.dart';

/// 일회성 마이그레이션 Cloud Function 하나의 실행 결과.
class MaintenanceRunResult {
  /// 서버가 돌려준 숫자들 — 함수마다 키가 다르다(updated / copied / skipped /
  /// nodes / refs). 화면은 그대로 나열만 한다.
  final Map<String, int> counts;

  const MaintenanceRunResult({required this.counts});

  String get summary => counts.isEmpty
      ? '완료'
      : counts.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
}

/// admin 전용 일회성 마이그레이션 실행기.
///
/// 이 함수들은 전부 `onCall` callable이고 서버가 호출자의
/// `users/{uid}.role == 'admin'`을 직접 다시 확인한다. 즉 **Firebase Auth
/// ID 토큰이 실린 호출**이어야만 통과한다 — `gcloud functions call`이 보내는
/// Google OIDC 토큰으로는 `request.auth`가 채워지지 않아 항상
/// "로그인이 필요합니다"로 거부된다. 그래서 관리자 화면에서 부르는 이
/// 경로가 사실상 유일한 실행 수단이다.
///
/// 셋 다 **멱등**이라 여러 번 눌러도 안전하다:
/// - `backfillPublishedNodeCounts`: 매번 실제 published 개수를 다시 센다.
/// - `backfillNodeDraftDocuments`: 이미 있는 draft 문서는 건너뛴다(덮어쓰지 않음).
/// - `migrateLegacyTtsTokensNow`: 완료 마커를 보고 두 번째부터는 즉시 끝난다.
class MaintenanceService {
  MaintenanceService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<MaintenanceRunResult> _run(String name) async {
    final result = await _functions.httpsCallable(name).call<Map<String, dynamic>>();
    final counts = <String, int>{};
    result.data.forEach((key, value) {
      if (value is num) counts[key] = value.toInt();
    });
    return MaintenanceRunResult(counts: counts);
  }

  /// storyPacks.publishedNodeCount 백필 — PR #6. 안 돌리면 홈 탭이 통째로 빈다
  /// (모든 팩의 발행 노드 수를 0으로 읽는다).
  Future<MaintenanceRunResult> backfillPublishedNodeCounts() =>
      _run('backfillPublishedNodeCounts');

  /// nodes → draftNodes 복사 — PR #7. 안 돌리면 작가 편집기의 노드 목록이 빈다
  /// (watchNodeSummaries가 draftNodes만 본다).
  Future<MaintenanceRunResult> backfillNodeDraftDocuments() =>
      _run('backfillNodeDraftDocuments');

  /// 예전 TTS 파일에 박힌 영구 download token 폐기 — PR #4. 예약 실행도 매일
  /// 돌지만, 배포 직후 바로 돌리고 싶을 때 쓴다.
  Future<MaintenanceRunResult> migrateLegacyTtsTokensNow() =>
      _run('migrateLegacyTtsTokensNow');
}
