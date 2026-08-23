import 'package:flutter/material.dart';

import '../data/maintenance_service.dart';
import '../widgets/admin_theme.dart';

/// "유지보수" — 배포 직후 admin이 한 번씩 눌러야 하는 일회성 마이그레이션들.
///
/// 이 함수들은 서버가 호출자의 `users/{uid}.role == 'admin'`을 직접 확인하는
/// callable이라 **Firebase Auth ID 토큰이 실린 호출**이어야만 통과한다.
/// `gcloud functions call`이 보내는 Google OIDC 토큰으로는 `request.auth`가
/// 비어서 항상 거부되므로, 실질적으로 이 화면이 유일한 실행 수단이다
/// (MaintenanceService 문서 참고).
///
/// 셋 다 멱등이라 실수로 두 번 눌러도 안전하다 — 그래서 확인 다이얼로그를
/// 두지 않았다. 대신 실행 중에는 버튼을 잠그고, 결과(처리 건수)를 카드에
/// 그대로 남겨서 "돌긴 돌았는지"를 눈으로 확인할 수 있게 한다.
class MaintenanceSection extends StatefulWidget {
  final MaintenanceService service;

  const MaintenanceSection({super.key, required this.service});

  @override
  State<MaintenanceSection> createState() => _MaintenanceSectionState();
}

class _MaintenanceSectionState extends State<MaintenanceSection> {
  /// 지금 실행 중인 작업 키 — 중복 클릭을 막는다.
  String? _running;

  /// 작업 키 → 마지막 실행 결과(성공 문구 또는 에러 문구).
  final Map<String, String> _lastResult = {};
  final Map<String, bool> _lastFailed = {};

  Future<void> _run(
    String key,
    Future<MaintenanceRunResult> Function() action,
  ) async {
    if (_running != null) return;
    setState(() => _running = key);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _lastResult[key] = '완료 — ${result.summary}';
        _lastFailed[key] = false;
      });
    } catch (e) {
      // 스트림/콜백 에러를 삼키지 않는다는 이 프로젝트의 관례대로, 실제 예외
      // 문구를 그대로 화면에 남긴다 — permission-denied인지 네트워크인지
      // 구분이 돼야 다음 조치를 정할 수 있다.
      if (!mounted) return;
      setState(() {
        _lastResult[key] = '실패 — $e';
        _lastFailed[key] = true;
      });
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '유지보수',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AdminColors.ivory,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '배포 직후 한 번씩 실행하는 일회성 마이그레이션이에요. 전부 여러 번 '
              '눌러도 안전하고(멱등), 실행 순서는 아래 카드 순서와 같아요.',
              style: TextStyle(fontSize: 13, color: AdminColors.muted),
            ),
            const SizedBox(height: 20),
            _MaintenanceCard(
              order: 1,
              title: '발행 노드 수 백필',
              functionName: 'backfillPublishedNodeCounts',
              description:
                  '모든 스토리팩의 storyPacks.publishedNodeCount를 다시 센다. '
                  '이걸 안 돌리면 새 카탈로그 코드가 모든 팩을 "발행 노드 0개"로 '
                  '읽어서 홈 탭이 통째로 빈다. 이후에는 maintainPublishedNodeCount '
                  '트리거가 값을 자동으로 유지한다.',
              running: _running == 'counts',
              disabled: _running != null,
              result: _lastResult['counts'],
              failed: _lastFailed['counts'] ?? false,
              onRun: () =>
                  _run('counts', widget.service.backfillPublishedNodeCounts),
            ),
            const SizedBox(height: 14),
            _MaintenanceCard(
              order: 2,
              title: '노드 draft 문서 백필',
              functionName: 'backfillNodeDraftDocuments',
              description:
                  '기존 nodes 문서를 같은 id의 draftNodes로 복사한다. 이미 draft가 '
                  '있으면 건너뛴다(작가의 새 초안을 절대 덮어쓰지 않는다). 이걸 안 '
                  '돌리면 새 작가 편집기의 노드 목록이 빈 채로 보인다 — 편집기는 '
                  'draftNodes만 보기 때문이다. 기존 nodes는 그대로 남으므로 '
                  '이 단계는 되돌릴 수 있다.',
              running: _running == 'draft',
              disabled: _running != null,
              result: _lastResult['draft'],
              failed: _lastFailed['draft'] ?? false,
              onRun: () =>
                  _run('draft', widget.service.backfillNodeDraftDocuments),
            ),
            const SizedBox(height: 14),
            _MaintenanceCard(
              order: 3,
              title: '옛 TTS 다운로드 토큰 폐기',
              functionName: 'migrateLegacyTtsTokensNow',
              description:
                  '예전 내레이션 파일에 박혀 있는 영구 Firebase download token을 '
                  '실제 Storage 메타데이터에서 지우고, Firestore 캐시를 Storage '
                  '경로 형태로 정규화한다. 매일 새벽 예약 실행도 같은 일을 하므로 '
                  '급하지 않다면 안 눌러도 된다 — 배포 직후 바로 끝내고 싶을 때만 '
                  '쓴다.',
              running: _running == 'tts',
              disabled: _running != null,
              result: _lastResult['tts'],
              failed: _lastFailed['tts'] ?? false,
              onRun: () => _run('tts', widget.service.migrateLegacyTtsTokensNow),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  final int order;
  final String title;
  final String functionName;
  final String description;
  final bool running;
  final bool disabled;
  final String? result;
  final bool failed;
  final VoidCallback onRun;

  const _MaintenanceCard({
    required this.order,
    required this.title,
    required this.functionName,
    required this.description,
    required this.running,
    required this.disabled,
    required this.result,
    required this.failed,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final resultText = result;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AdminColors.panel2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AdminColors.border),
                ),
                child: Text(
                  '$order',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.ivory,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.ivory,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      functionName,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: AdminColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: disabled ? null : onRun,
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminColors.gold,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AdminColors.panel2,
                    disabledForegroundColor: AdminColors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black54,
                          ),
                        )
                      : const Text(
                          '실행',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AdminColors.muted,
            ),
          ),
          if (resultText != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AdminColors.panel2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: failed ? AdminColors.rejectBorder : AdminColors.approveBorder,
                ),
              ),
              child: Text(
                resultText,
                style: TextStyle(
                  fontSize: 12.5,
                  color: failed ? AdminColors.rejectText : AdminColors.ivory,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
