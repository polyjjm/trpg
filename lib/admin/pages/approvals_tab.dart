import 'package:flutter/material.dart';

import '../data/activity_log_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/activity_event.dart';
import '../models/admin_image.dart';
import '../models/pending_action.dart';
import '../models/pending_node_ref.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';
import 'approvals/approval_filter.dart';
import 'approvals/approvals_filter_bar.dart';
import 'approvals/history_detail_pane.dart';
import 'approvals/node_diff_view.dart';
import 'approvals/pending_detail_pane.dart';
import 'approvals/pending_list_pane.dart';

/// "승인 대기함" — admin 전용. 모든 스토리팩을 통틀어 pendingAction이 걸린
/// 노드를 모아 검토/승인/반려한다.
///
/// 목록(왼쪽) + 상세(오른쪽) 2단이다. 예전에는 카드마다 diff가 전부 펼쳐진
/// 한 줄 목록이어서, 요청이 열 건만 넘어도 "지금 뭐가 얼마나 밀려 있는지"를
/// 스크롤 없이 알 수 없었다 — 훑는 화면과 판단하는 화면을 분리했다.
/// 검색(작가/작품/노드 ID)·요청일 기준 기간 필터·정렬은 전부 클라이언트
/// 계산이다(approvals/approval_filter.dart의 doc 참고).
class ApprovalsTab extends StatefulWidget {
  final AdminStoryRepository repository;
  final AdminImageRepository imageRepository;
  final Map<String, String> packTitles;
  final Map<String, StoryPackType> packTypes;

  /// packId → 작가 이름. 검색과 목록 그룹 헤더가 쓴다 — "누가 요청했는지"로
  /// 찾는 게 가장 흔한 조회라 필수 인자로 받는다(없으면 '-').
  final Map<String, String> packAuthors;

  /// 승인/반려를 개요의 "최근 활동"에 남긴다. null이면 기록하지 않는다.
  final ActivityLogRepository? activityLog;
  final String reviewerUid;

  const ApprovalsTab({
    super.key,
    required this.repository,
    required this.imageRepository,
    required this.packTitles,
    required this.packTypes,
    required this.packAuthors,
    required this.reviewerUid,
    this.activityLog,
  });

  @override
  State<ApprovalsTab> createState() => _ApprovalsTabState();
}

enum _HandledStatus { approved, rejected }

class _ApprovalsTabState extends State<ApprovalsTab> {
  /// State에 한 번만 만든다 — build()에서 매번 새로 구독하면 부모가 재빌드될
  /// 때마다 목록이 나타났다 사라진다(이 프로젝트에서 반복해 겪은 문제).
  late final Stream<List<PendingNodeRef>> _pendingStream = widget.repository
      .watchPendingNodes();
  late final Stream<List<AdminImage>> _imagesStream = widget.imageRepository
      .watchImages();

  /// "처리됨"/"전체" 상태에서만 쓰인다. activityLog가 없는 인스턴스(테스트 등)
  /// 에서는 그냥 빈 스트림으로 둔다.
  late final Stream<List<ActivityEvent>> _historyStream =
      widget.activityLog?.watchNodeApprovalHistory() ??
      Stream.value(const <ActivityEvent>[]);

  ApprovalFilter _filter = const ApprovalFilter();
  String? _selectedKey;
  final Set<String> _checkedKeys = {};
  final Set<String> _processingKeys = {};

  /// 처리한 요청은 `watchPendingNodes()` 다음 스냅샷에서 빠진다 — 그대로 두면
  /// 방금 처리한 게 화면에서 사라져서 뭘 눌렀는지 확인할 수 없다. 이 State가
  /// 살아있는 동안 스냅샷으로 붙잡아 두고 배지만 바꿔 보여준다.
  final Map<String, _HandledStatus> _handled = {};
  final Map<String, PendingNodeRef> _handledRefs = {};
  bool _batchRunning = false;

  String _keyFor(PendingNodeRef ref) => PendingListPane.keyFor(ref);
  String _titleOf(String packId) => widget.packTitles[packId] ?? packId;
  String _authorOf(String packId) => widget.packAuthors[packId] ?? '-';

  Future<void> _log(PendingNodeRef ref, {required bool approved}) async {
    final log = widget.activityLog;
    if (log == null) return;
    final action = switch (ref.node.pendingAction) {
      PendingAction.create => '등록',
      PendingAction.edit => '수정',
      PendingAction.delete => '삭제',
      null => '',
    };
    await log.log(
      kind: approved ? ActivityKind.nodeApproved : ActivityKind.nodeRejected,
      actorUid: widget.reviewerUid,
      message:
          '${_authorOf(ref.packId)} · 「${_titleOf(ref.packId)}」 '
          '${ref.node.id} 노드 $action ${approved ? '승인' : '반려'}',
      packId: ref.packId,
      nodeId: ref.node.id,
      authorName: _authorOf(ref.packId),
    );
  }

  Future<void> _approve(PendingNodeRef ref) async {
    final key = _keyFor(ref);
    if (_processingKeys.contains(key)) return;
    setState(() => _processingKeys.add(key));
    try {
      await widget.repository.approveNode(ref.packId, ref.node);
      await _log(ref, approved: true);
      if (!mounted) return;
      setState(() {
        _handled[key] = _HandledStatus.approved;
        _handledRefs[key] = ref;
        _checkedKeys.remove(key);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('승인에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _processingKeys.remove(key));
    }
  }

  Future<void> _reject(PendingNodeRef ref) async {
    final reason = await promptRejectionReason(context);
    if (reason == null || !mounted) return;

    final key = _keyFor(ref);
    setState(() => _processingKeys.add(key));
    try {
      await widget.repository.rejectNode(ref.packId, ref.node, reason: reason);
      await _log(ref, approved: false);
      if (!mounted) return;
      setState(() {
        _handled[key] = _HandledStatus.rejected;
        _handledRefs[key] = ref;
        _checkedKeys.remove(key);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('반려에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _processingKeys.remove(key));
    }
  }

  Future<void> _batchApprove(List<PendingNodeRef> visible) async {
    final targets = visible
        .where((ref) => _checkedKeys.contains(_keyFor(ref)))
        .toList();
    if (targets.isEmpty || _batchRunning) return;

    setState(() => _batchRunning = true);
    var succeeded = 0;
    var failed = 0;
    for (final ref in targets) {
      try {
        await widget.repository.approveNode(ref.packId, ref.node);
        await _log(ref, approved: true);
        succeeded += 1;
        _handled[_keyFor(ref)] = _HandledStatus.approved;
        _handledRefs[_keyFor(ref)] = ref;
      } catch (_) {
        failed += 1;
      }
    }

    if (!mounted) return;
    setState(() {
      _batchRunning = false;
      _checkedKeys.clear();
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

  String _summary(List<PendingNodeRef> pending) {
    if (pending.isEmpty) return '대기 중인 요청이 없어요.';
    DateTime? oldest;
    for (final ref in pending) {
      final at = ref.requestedAt;
      if (at == null) continue;
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    final waited = oldest == null
        ? ''
        : ' · 가장 오래 기다린 요청 ${formatWaitedLabel(oldest)}';
    return '${pending.length}건 대기$waited';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminImage>>(
      stream: _imagesStream,
      builder: (context, imageSnapshot) {
        final imagesById = {
          for (final img in imageSnapshot.data ?? const <AdminImage>[])
            img.id: img,
        };

        return StreamBuilder<List<PendingNodeRef>>(
          stream: _pendingStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '승인 대기 목록을 불러오지 못했어요: ${snapshot.error}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.danger,
                  ),
                ),
              );
            }

            final pending = snapshot.data ?? const <PendingNodeRef>[];
            final pendingKeys = pending.map(_keyFor).toSet();

            // 처리했지만 아직 스트림에 남아 있는 건(레이스) 중복으로 그리지
            // 않는다 — pending 쪽 항목을 그대로 쓴다.
            final staleHandled = [
              for (final entry in _handledRefs.entries)
                if (!pendingKeys.contains(entry.key)) entry.value,
            ];

            // 상태 필터가 "처리됨"이면 대기 목록 자체를 비운다 — 목록 왼쪽엔
            // 이력만 보인다. "전체"는 둘 다, "대기중"(기본)은 대기만.
            final showPending = _filter.status != ApprovalStatusFilter.handled;
            final showHistory = _filter.status != ApprovalStatusFilter.pending;

            final visible = showPending
                ? applyApprovalFilter(
                    [...pending, ...staleHandled],
                    _filter,
                    packTitles: widget.packTitles,
                    packAuthors: widget.packAuthors,
                  )
                : const <PendingNodeRef>[];
            final groups = groupPendingByPack(
              visible,
              packTitles: widget.packTitles,
              packAuthors: widget.packAuthors,
            );

            return StreamBuilder<List<ActivityEvent>>(
              stream: _historyStream,
              builder: (context, historySnapshot) {
                final historyEvents =
                    historySnapshot.data ?? const <ActivityEvent>[];
                final visibleHistory = showHistory
                    ? applyHistoryFilter(
                        historyEvents,
                        _filter,
                        packTitles: widget.packTitles,
                        packAuthors: widget.packAuthors,
                      )
                    : const <ActivityEvent>[];

                // 대기 목록 뒤에 이력이 이어 붙는 순서 그대로 하나의 키 목록을
                // 만든다 — PendingListPane이 그리는 순서와 같아야 이전/다음
                // 이동이 화면과 어긋나지 않는다.
                final combinedKeys = [
                  for (final ref in visible) _keyFor(ref),
                  for (final event in visibleHistory)
                    PendingListPane.historyKeyFor(event),
                ];

                // 필터가 바뀌어 선택 항목이 목록에서 빠졌으면 첫 항목으로
                // 옮긴다 — 상세가 빈 화면으로 남는 것보다 낫다.
                var index = _selectedKey == null
                    ? -1
                    : combinedKeys.indexOf(_selectedKey!);
                if (index == -1 && combinedKeys.isNotEmpty) index = 0;

                PendingNodeRef? selected;
                ActivityEvent? selectedHistory;
                if (index >= 0) {
                  if (index < visible.length) {
                    selected = visible[index];
                  } else {
                    selectedHistory = visibleHistory[index - visible.length];
                  }
                }

                final selectedKey = index >= 0 ? combinedKeys[index] : null;
                final handledStatus = selected == null
                    ? null
                    : _handled[_keyFor(selected)];

                void goTo(int target) {
                  setState(() => _selectedKey = combinedKeys[target]);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ApprovalsFilterBar(
                      filter: _filter,
                      summary: _summary(pending),
                      onChanged: (next) => setState(() => _filter = next),
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 목록은 줄어들 수 있게 둔다(290~400) — 고정 폭이면
                          // 좁은 창에서 상세가 잘린다.
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 290,
                              maxWidth: 400,
                            ),
                            child: SizedBox(
                              width: 360,
                              child: PendingListPane(
                                groups: groups,
                                packTypes: widget.packTypes,
                                selectedKey: selectedKey,
                                checkedKeys: _checkedKeys,
                                visibleCount: visible.length,
                                batchRunning: _batchRunning,
                                onSelect: (ref) =>
                                    setState(() => _selectedKey = _keyFor(ref)),
                                onToggleCheck: (ref) => setState(() {
                                  final key = _keyFor(ref);
                                  if (!_checkedKeys.remove(key)) {
                                    _checkedKeys.add(key);
                                  }
                                }),
                                onToggleAll: () => setState(() {
                                  if (_checkedKeys.length >= visible.length) {
                                    _checkedKeys.clear();
                                  } else {
                                    _checkedKeys
                                      ..clear()
                                      ..addAll(visible.map(_keyFor));
                                  }
                                }),
                                onClearChecks: () =>
                                    setState(_checkedKeys.clear),
                                onBatchApprove: () => _batchApprove(visible),
                                historyEntries: visibleHistory,
                                selectedHistoryKey: selectedHistory == null
                                    ? null
                                    : selectedKey,
                                onSelectHistory: (event) => setState(
                                  () => _selectedKey =
                                      PendingListPane.historyKeyFor(event),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: selectedHistory != null
                                ? HistoryDetailPane(
                                    event: selectedHistory,
                                    packTitle: selectedHistory.packId == null
                                        ? ''
                                        : _titleOf(selectedHistory.packId!),
                                    index: index,
                                    total: combinedKeys.length,
                                    onPrev: index > 0
                                        ? () => goTo(index - 1)
                                        : null,
                                    onNext: index < combinedKeys.length - 1
                                        ? () => goTo(index + 1)
                                        : null,
                                  )
                                : PendingDetailPane(
                                    ref: selected,
                                    packTitle: selected == null
                                        ? ''
                                        : _titleOf(selected.packId),
                                    authorName: selected == null
                                        ? ''
                                        : _authorOf(selected.packId),
                                    packType: selected == null
                                        ? StoryPackType.interactive
                                        : widget.packTypes[selected.packId] ??
                                              StoryPackType.interactive,
                                    imagesById: imagesById,
                                    handledLabel: handledStatus == null
                                        ? null
                                        : (handledStatus ==
                                                  _HandledStatus.approved
                                              ? '✓ 승인됨'
                                              : '반려됨'),
                                    handledApproved:
                                        handledStatus ==
                                        _HandledStatus.approved,
                                    processing:
                                        selectedKey != null &&
                                        _processingKeys.contains(selectedKey),
                                    index: index,
                                    total: combinedKeys.length,
                                    onApprove: selected == null
                                        ? () {}
                                        : () => _approve(selected!),
                                    onReject: selected == null
                                        ? () {}
                                        : () => _reject(selected!),
                                    onPrev: index > 0
                                        ? () => goTo(index - 1)
                                        : null,
                                    onNext:
                                        index >= 0 &&
                                            index < combinedKeys.length - 1
                                        ? () => goTo(index + 1)
                                        : null,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
