import 'package:flutter/material.dart';

import '../data/admin_story_repository.dart';
import '../models/pending_action.dart';
import '../models/pending_node_ref.dart';
import '../widgets/admin_theme.dart';

/// "승인 대기함" — admin 전용 페이지(AdminDashboardPage) 안에서만 쓰인다,
/// author가 쓰는 AuthorToolPage에는 아예 없다. 모든 스토리팩을 통틀어 pendingAction이 걸린
/// 노드를 모아 보여주고, 승인/반려를 처리한다. "작가 신청" 탭(작가 자격 심사)과는
/// 완전히 별개의 검토 흐름이다 — 여기서 승인하는 건 콘텐츠 하나하나다.
class ApprovalsTab extends StatefulWidget {
  final AdminStoryRepository repository;
  final Map<String, String> packTitles;

  const ApprovalsTab({
    super.key,
    required this.repository,
    required this.packTitles,
  });

  @override
  State<ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends State<ApprovalsTab> {
  /// State에 한 번만 만든다 — StatelessWidget이었을 때는 이 위젯의 부모가
  /// 재빌드될 때마다(팩 목록 스트림이 새 이벤트를 받을 때마다) build()가
  /// 다시 돌면서 watchPendingNodes()를 매번 새로 호출했다.
  /// 그러면 StreamBuilder가 매번 "다른 스트림"을 받아 구독을 끊었다 다시
  /// 맺었고, 그 사이 잠깐 이전 스냅샷이 그대로 보이다(깜빡 나타났다) 새
  /// 구독이 첫 이벤트를 받기 전까지 빈 상태로 리셋됐다(사라짐) — 승인/반려
  /// 직후에도 이 재빌드가 일어나 목록이 나타났다 사라지는 것처럼 보였다.
  late final Stream<List<PendingNodeRef>> _pendingStream = widget.repository
      .watchPendingNodes();

  /// packId + node.id로 키를 만든다 — 노드 id는 팩마다 겹칠 수 있어 노드 id만으로는
  /// 여러 팩에 걸친 선택을 구분할 수 없다.
  final Set<String> _selectedKeys = {};
  bool _batchRunning = false;

  String _keyFor(PendingNodeRef ref) => '${ref.packId}/${ref.node.id}';

  void _toggleSelected(String key) {
    setState(() {
      if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
    });
  }

  Future<void> _handleBatchApprove(List<PendingNodeRef> pending) async {
    final targets = pending
        .where((ref) => _selectedKeys.contains(_keyFor(ref)))
        .toList();
    if (targets.isEmpty || _batchRunning) return;

    setState(() => _batchRunning = true);

    var succeeded = 0;
    var failed = 0;
    for (final ref in targets) {
      try {
        await widget.repository.approveNode(ref.packId, ref.node);
        succeeded += 1;
      } catch (_) {
        failed += 1;
      }
    }

    if (!mounted) return;
    setState(() {
      _batchRunning = false;
      _selectedKeys.clear();
    });

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminColors.panel,
        title: Text('일괄 승인 완료', style: TextStyle(color: AdminColors.ivory)),
        content: Text(
          failed == 0
              ? '$succeeded개 모두 승인했어요.'
              : '$succeeded개 승인, $failed개 실패했어요.',
          style: TextStyle(color: AdminColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인', style: TextStyle(color: AdminColors.gold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '승인 대기함',
            style: TextStyle(
              fontSize: 16,
              color: AdminColors.ivory,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '모든 작가의 스토리팩을 통틀어 등록/수정/삭제 요청을 검토해요.',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<PendingNodeRef>>(
            stream: _pendingStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                // 캐시된 streaming 픽스만으로는 안 잡히는 경우 — 스트림 자체가
                // 에러 이벤트를 낸 것이다(예: 색인 문제). AsyncSnapshot은 에러가
                // 나면 data를 null로 리셋하기 때문에, 이 체크 없이는 방금까지
                // 보이던 목록이 "그냥 비어 보임"으로 조용히 사라진다 — 새
                // 스토리팩 다이얼로그의 장르 목록에서 겪은 것과 같은 종류의
                // 버그다.
                return SelectableText(
                  '승인 대기 목록을 불러오지 못했어요: ${snapshot.error}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.danger,
                  ),
                );
              }

              final pending = snapshot.data ?? const <PendingNodeRef>[];
              if (pending.isEmpty) {
                return Text(
                  '대기 중인 요청이 없어요.',
                  style: TextStyle(fontSize: 13, color: AdminColors.muted),
                );
              }

              final selectedCount = pending
                  .where((ref) => _selectedKeys.contains(_keyFor(ref)))
                  .length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ElevatedButton(
                      onPressed: (selectedCount == 0 || _batchRunning)
                          ? null
                          : () => _handleBatchApprove(pending),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.gold,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AdminColors.panel2,
                        disabledForegroundColor: AdminColors.muted,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _batchRunning
                            ? '승인 처리 중...'
                            : selectedCount == 0
                            ? '선택 항목 일괄 승인'
                            : '선택 항목 일괄 승인 ($selectedCount)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  for (final ref in pending)
                    _ApprovalCard(
                      ref: ref,
                      packTitle: widget.packTitles[ref.packId] ?? ref.packId,
                      selected: _selectedKeys.contains(_keyFor(ref)),
                      onToggleSelected: () => _toggleSelected(_keyFor(ref)),
                      onApprove: () =>
                          widget.repository.approveNode(ref.packId, ref.node),
                      onReject: () =>
                          widget.repository.rejectNode(ref.packId, ref.node),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final PendingNodeRef ref;
  final String packTitle;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.ref,
    required this.packTitle,
    required this.selected,
    required this.onToggleSelected,
    required this.onApprove,
    required this.onReject,
  });

  static const _actionLabel = {
    PendingAction.create: '신규 등록 요청',
    PendingAction.edit: '수정 요청',
    PendingAction.delete: '삭제 요청',
  };

  @override
  Widget build(BuildContext context) {
    final label = _actionLabel[ref.node.pendingAction] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(
          color: selected ? AdminColors.gold : AdminColors.border,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AdminColors.gold
                  : AdminColors.checkboxUncheckedFill,
            ),
            checkColor: AdminColors.checkboxCheckColor,
            side: BorderSide(
              color: AdminColors.checkboxUncheckedBorder,
              width: 1.5,
            ),
            onChanged: (_) => onToggleSelected(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[$label] ${ref.node.previewText.isEmpty ? '(내용 없음)' : ref.node.previewText}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AdminColors.ivory,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '스토리팩: $packTitle · 노드 ID: ${ref.node.id}',
                  style: TextStyle(fontSize: 12, color: AdminColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            label: '승인',
            bg: AdminColors.approveBg,
            fg: AdminColors.approveText,
            border: AdminColors.approveBorder,
            onTap: onApprove,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: '반려',
            bg: AdminColors.rejectBg,
            fg: AdminColors.rejectText,
            border: AdminColors.rejectBorder,
            onTap: onReject,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: fg)),
      ),
    );
  }
}
