import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/node_diff.dart';
import '../models/admin_image.dart';
import '../models/admin_node_choice.dart';
import '../models/pending_action.dart';
import '../models/pending_node_ref.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';

/// "승인 대기함" — admin 전용 페이지(AdminDashboardPage) 안에서만 쓰인다,
/// author가 쓰는 AuthorToolPage에는 아예 없다. 모든 스토리팩을 통틀어
/// pendingAction이 걸린 노드를 모아, "지금 편집 중인 내용"과
/// "마지막으로 승인된 liveSnapshot"의 diff(before/after)로 보여주고
/// 승인/반려를 처리한다. "작가 신청" 탭(작가 자격 심사)과는 완전히
/// 별개의 검토 흐름이다 — 여기서 승인하는 건 콘텐츠 하나하나다.
class ApprovalsTab extends StatefulWidget {
  final AdminStoryRepository repository;
  final AdminImageRepository imageRepository;
  final Map<String, String> packTitles;
  final Map<String, StoryPackType> packTypes;

  const ApprovalsTab({
    super.key,
    required this.repository,
    required this.imageRepository,
    required this.packTitles,
    required this.packTypes,
  });

  @override
  State<ApprovalsTab> createState() => _ApprovalsTabState();
}

enum _HandledStatus { approved, rejected }

/// 방금 처리한(승인/반려) 카드 하나 — 처리 순간의 [PendingNodeRef]를 그대로
/// 들고 있는다. `watchPendingNodes()`는 pendingAction이 걸린 문서만 돌려주므로,
/// 처리하고 나면 그 노드는 다음 스냅샷에서 조용히 빠진다 — 그대로 두면
/// "처리한 카드가 화면에서 사라지는" 것처럼 보인다("자리 유지 + 처리됨
/// 표시"라는 요구사항과 반대). 그래서 처리한 카드는 이 맵에 스냅샷으로
/// 남겨 두고, 목록 스트림에서 빠졌더라도 계속 그려서 admin이 방금 뭘
/// 처리했는지 스크롤 안 하고도 확인할 수 있게 한다.
class _HandledEntry {
  final PendingNodeRef ref;
  final _HandledStatus status;

  const _HandledEntry({required this.ref, required this.status});
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
  late final Stream<List<AdminImage>> _imagesStream = widget.imageRepository
      .watchImages();

  /// packId + node.id로 키를 만든다 — 노드 id는 팩마다 겹칠 수 있어 노드 id만으로는
  /// 여러 팩에 걸친 선택을 구분할 수 없다.
  final Set<String> _selectedKeys = {};
  bool _batchRunning = false;

  /// 승인/반려를 처리한 카드 — 위 [_HandledEntry] doc 참고. 이 State가
  /// 살아있는 동안(탭을 벗어나지 않는 한) 계속 남는다.
  final Map<String, _HandledEntry> _handled = {};

  /// 지금 승인/반려 네트워크 요청이 진행 중인 카드 — 그동안 그 카드의
  /// 버튼만 비활성화한다(다른 카드는 계속 조작할 수 있어야 한다).
  final Set<String> _processingKeys = {};

  String _keyFor(PendingNodeRef ref) => '${ref.packId}/${ref.node.id}';

  void _toggleSelected(String key) {
    setState(() {
      if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
    });
  }

  Future<void> _handleApprove(PendingNodeRef ref) async {
    final key = _keyFor(ref);
    setState(() => _processingKeys.add(key));
    try {
      await widget.repository.approveNode(ref.packId, ref.node);
      if (!mounted) return;
      setState(() {
        _handled[key] = _HandledEntry(
          ref: ref,
          status: _HandledStatus.approved,
        );
        _selectedKeys.remove(key);
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

  /// 반려는 사유를 반드시 입력해야 보낼 수 있다 — pack_approvals_tab.dart의
  /// 반려 사유 다이얼로그와 같은 UI 패턴을 따르되(다이얼로그 하나로
  /// 텍스트 입력 + 취소/반려하기), 이쪽은 필수다(빈 채로 못 보낸다).
  /// 이 사유는 노드 문서의 rejectionReason 필드에 저장돼 작가 쪽 사이드바/
  /// 편집 화면에도 그대로 보인다(story_node_sidebar.dart/node_editor.dart) —
  /// requestApprovalForNode(작가가 다시 제출하는 시점)가 이 필드를 지운다.
  Future<void> _handleReject(PendingNodeRef ref) async {
    final reason = await _promptRejectionReason(context);
    if (reason == null || !mounted) return;

    final key = _keyFor(ref);
    setState(() => _processingKeys.add(key));
    try {
      await widget.repository.rejectNode(ref.packId, ref.node, reason: reason);
      if (!mounted) return;
      setState(() {
        _handled[key] = _HandledEntry(
          ref: ref,
          status: _HandledStatus.rejected,
        );
        _selectedKeys.remove(key);
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
        _handled[_keyFor(ref)] = _HandledEntry(
          ref: ref,
          status: _HandledStatus.approved,
        );
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
            '모든 작가의 스토리팩을 통틀어 등록/수정/삭제 요청을 검토해요. '
            '본문/배경 이미지/선택지는 마지막으로 승인된 버전과 비교해서 보여줘요.',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<AdminImage>>(
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
                    // 캐시된 streaming 픽스만으로는 안 잡히는 경우 — 스트림 자체가
                    // 에러 이벤트를 낸 것이다(예: 색인 문제). AsyncSnapshot은 에러가
                    // 나면 data를 null로 리셋하기 때문에, 이 체크 없이는 방금까지
                    // 보이던 목록이 "그냥 비어 보임"으로 조용히 사라진다.
                    return SelectableText(
                      '승인 대기 목록을 불러오지 못했어요: ${snapshot.error}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.danger,
                      ),
                    );
                  }

                  final pending = snapshot.data ?? const <PendingNodeRef>[];
                  final pendingKeys = pending.map(_keyFor).toSet();

                  // 처리된 카드 중 지금 스트림에서 이미 빠진 것만 뒤에 이어
                  // 붙인다 — 아직 pending으로 남아 있다면(레이스 등) 위
                  // pending 목록 쪽 카드를 그대로 쓴다(중복 렌더 방지).
                  final staleHandled = _handled.entries
                      .where((e) => !pendingKeys.contains(e.key))
                      .toList();

                  if (pending.isEmpty && staleHandled.isEmpty) {
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
                      if (pending.isNotEmpty)
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
                          key: ValueKey(_keyFor(ref)),
                          ref: ref,
                          packTitle:
                              widget.packTitles[ref.packId] ?? ref.packId,
                          packType:
                              widget.packTypes[ref.packId] ??
                              StoryPackType.interactive,
                          imagesById: imagesById,
                          selected: _selectedKeys.contains(_keyFor(ref)),
                          processing: _processingKeys.contains(_keyFor(ref)),
                          handledStatus: null,
                          onToggleSelected: () => _toggleSelected(_keyFor(ref)),
                          onApprove: () => _handleApprove(ref),
                          onReject: () => _handleReject(ref),
                        ),
                      for (final entry in staleHandled)
                        _ApprovalCard(
                          key: ValueKey(entry.key),
                          ref: entry.value.ref,
                          packTitle:
                              widget.packTitles[entry.value.ref.packId] ??
                              entry.value.ref.packId,
                          packType:
                              widget.packTypes[entry.value.ref.packId] ??
                              StoryPackType.interactive,
                          imagesById: imagesById,
                          selected: false,
                          processing: false,
                          handledStatus: entry.value.status,
                          onToggleSelected: () {},
                          onApprove: () {},
                          onReject: () {},
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<String?> _promptRejectionReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final canSubmit = controller.text.trim().isNotEmpty;
        return AlertDialog(
          backgroundColor: AdminColors.panel,
          title: Text('반려 사유 (필수)', style: TextStyle(color: AdminColors.ivory)),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              onChanged: (_) => setDialogState(() {}),
              style: TextStyle(color: AdminColors.ivory),
              decoration: InputDecoration(
                hintText: '작가에게 무엇을 고쳐야 하는지 알려주세요.',
                hintStyle: TextStyle(color: AdminColors.muted, fontSize: 12),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AdminColors.border),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AdminColors.gold),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('취소', style: TextStyle(color: AdminColors.muted)),
            ),
            TextButton(
              onPressed: canSubmit
                  ? () => Navigator.pop(dialogContext, controller.text.trim())
                  : null,
              child: const Text(
                '반려하기',
                style: TextStyle(color: AdminColors.rejectText),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ApprovalCard extends StatelessWidget {
  final PendingNodeRef ref;
  final String packTitle;
  final StoryPackType packType;
  final Map<String, AdminImage> imagesById;
  final bool selected;
  final bool processing;

  /// null이면 아직 처리 전(활성 카드) — 승인됨/반려됨이면 처리 완료된
  /// 카드로, 흐리게 + 상태 배지만 보여주고 액션 버튼은 안 보여준다.
  final _HandledStatus? handledStatus;

  final VoidCallback onToggleSelected;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required super.key,
    required this.ref,
    required this.packTitle,
    required this.packType,
    required this.imagesById,
    required this.selected,
    required this.processing,
    required this.handledStatus,
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
    final isDelete = ref.node.pendingAction == PendingAction.delete;
    // 삭제 요청은 비교할 "새 콘텐츠"가 없다 — liveSnapshot(지금 라이브인
    // 내용) 자체를 없앨지 말지를 묻는 요청이라, diff 대신 그 사실만 안내한다.
    final diff = isDelete ? null : NodeDiff.compute(ref.node);
    final handled = handledStatus != null;

    return Opacity(
      opacity: handled ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AdminColors.panel,
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!handled)
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
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            '[$label]',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AdminColors.ivory,
                            ),
                          ),
                          if (diff != null) ..._buildChangeTags(diff, packType),
                          if (handled) _HandledPill(status: handledStatus!),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '스토리팩: $packTitle · 노드 ID: ${ref.node.id}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!handled) ...[
                  const SizedBox(width: 12),
                  _ActionButton(
                    label: '승인',
                    bg: AdminColors.approveBg,
                    fg: AdminColors.approveText,
                    border: AdminColors.approveBorder,
                    onTap: processing ? null : onApprove,
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    label: '반려',
                    bg: AdminColors.rejectBg,
                    fg: AdminColors.rejectText,
                    border: AdminColors.rejectBorder,
                    onTap: processing ? null : onReject,
                  ),
                ],
              ],
            ),
            if (isDelete) ...[
              const SizedBox(height: 10),
              Text(
                '이 노드를 삭제해도 되는지 검토해주세요 — 승인하면 문서가 완전히 지워지고, '
                '반려하면 삭제 요청만 취소되고 노드는 그대로 남아요.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AdminColors.muted,
                  height: 1.4,
                ),
              ),
            ] else if (diff != null) ...[
              const SizedBox(height: 10),
              if (diff.bodyChanged) ...[
                _DiffSectionLabel('본문'),
                const SizedBox(height: 4),
                _BodyDiffText(segments: diff.bodySegments),
                const SizedBox(height: 10),
              ],
              if (diff.orderChanged) ...[
                _DiffSectionLabel('순서'),
                const SizedBox(height: 4),
                _OrderDiff(
                  beforeOrder: diff.beforeOrder!,
                  afterOrder: diff.afterOrder,
                ),
                const SizedBox(height: 10),
              ],
              if (diff.backgroundChanged) ...[
                _DiffSectionLabel('배경 이미지'),
                const SizedBox(height: 4),
                _BackgroundImageDiff(
                  beforeImage: imagesById[diff.beforeBackgroundImageId],
                  afterImage: imagesById[diff.afterBackgroundImageId],
                ),
                const SizedBox(height: 10),
              ],
              if (packType == StoryPackType.interactive &&
                  diff.choicesChanged) ...[
                _DiffSectionLabel('선택지'),
                const SizedBox(height: 4),
                _ChoicesDiff(
                  added: diff.addedChoices,
                  removed: diff.removedChoices,
                ),
                const SizedBox(height: 10),
              ],
              if (diff.effectsChanged) ...[
                _DiffSectionLabel('연출 효과'),
                const SizedBox(height: 4),
                Text(
                  '연출 효과(암전/화면 흔들림/효과음/화면 플래시/진동/배경음악/'
                  '내레이션) 설정이 바뀌었어요 — 자세한 값은 노드 편집 화면에서 확인하세요.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AdminColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
              if (!diff.anyChanged)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '내용상 변경 없음 — 승인된 버전과 완전히 같아요(이미 같은 내용을 다시 제출했어요).',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildChangeTags(NodeDiff diff, StoryPackType packType) {
    return [
      if (diff.bodyChanged)
        const _ChangeTag(
          label: '본문 수정',
          color: AdminColors.liveNoteText,
          bg: AdminColors.liveNoteBg,
        ),
      if (diff.orderChanged)
        const _ChangeTag(
          label: '순서 변경',
          color: AdminColors.statusPendingText,
          bg: AdminColors.statusPendingBg,
        ),
      if (diff.backgroundChanged)
        const _ChangeTag(
          label: '배경 이미지 변경',
          color: AdminColors.imageCategoryBackgroundText,
          bg: AdminColors.imageCategoryBackgroundBg,
        ),
      if (packType == StoryPackType.interactive && diff.choicesChanged)
        const _ChangeTag(
          label: '선택지 변경',
          color: AdminColors.imageCategoryChoiceText,
          bg: AdminColors.imageCategoryChoiceBg,
        ),
      if (diff.effectsChanged)
        const _ChangeTag(
          label: '연출 효과 변경',
          color: AdminColors.imageCategoryOtherText,
          bg: AdminColors.imageCategoryOtherBg,
        ),
    ];
  }
}

class _HandledPill extends StatelessWidget {
  final _HandledStatus status;

  const _HandledPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final approved = status == _HandledStatus.approved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: approved ? AdminColors.approveBg : AdminColors.rejectBg,
        border: Border.all(
          color: approved
              ? AdminColors.approveBorder
              : AdminColors.rejectBorder,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        approved ? '✓ 승인됨' : '반려됨',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: approved ? AdminColors.approveText : AdminColors.rejectText,
        ),
      ),
    );
  }
}

class _ChangeTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _ChangeTag({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DiffSectionLabel extends StatelessWidget {
  final String text;

  const _DiffSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AdminColors.muted,
      ),
    );
  }
}

/// 본문 word/문장 수준 diff — DIFF_EQUAL은 그대로, DIFF_INSERT는 초록
/// 배경(추가), DIFF_DELETE는 빨간 취소선(삭제)으로 보여준다.
class _BodyDiffText extends StatelessWidget {
  final List<Diff> segments;

  const _BodyDiffText({required this.segments});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 12.5,
            color: AdminColors.ivory,
            height: 1.6,
          ),
          children: [
            for (final segment in segments)
              TextSpan(
                text: segment.text,
                style: switch (segment.operation) {
                  DIFF_INSERT => const TextStyle(
                    backgroundColor: Color(0x334CAF50),
                    color: Color(0xFF9BE39B),
                  ),
                  DIFF_DELETE => const TextStyle(
                    backgroundColor: Color(0x33E0524B),
                    color: Color(0xFFE0938F),
                    decoration: TextDecoration.lineThrough,
                  ),
                  _ => null,
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// "N번째 → M번째로 이동" — order(beforeOrder/afterOrder)는 항상 0-based라
/// NodeDiff.orderRankLabel로 사람이 읽는 1-based 순번으로 바꿔서 보여준다.
class _OrderDiff extends StatelessWidget {
  final int beforeOrder;
  final int afterOrder;

  const _OrderDiff({required this.beforeOrder, required this.afterOrder});

  @override
  Widget build(BuildContext context) {
    return Text(
      '${NodeDiff.orderRankLabel(beforeOrder)} → ${NodeDiff.orderRankLabel(afterOrder)}로 이동',
      style: TextStyle(
        fontSize: 12.5,
        color: AdminColors.statusPendingText,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _BackgroundImageDiff extends StatelessWidget {
  final AdminImage? beforeImage;
  final AdminImage? afterImage;

  const _BackgroundImageDiff({
    required this.beforeImage,
    required this.afterImage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ImageThumb(image: beforeImage),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: AdminColors.muted,
          ),
        ),
        _ImageThumb(image: afterImage),
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final AdminImage? image;

  const _ImageThumb({required this.image});

  @override
  Widget build(BuildContext context) {
    final url = image?.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 72,
        height: 44,
        color: AdminColors.panel2,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.image_not_supported_outlined,
                  size: 16,
                  color: AdminColors.muted,
                ),
              )
            : Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: AdminColors.muted,
                ),
              ),
      ),
    );
  }
}

class _ChoicesDiff extends StatelessWidget {
  final List<AdminNodeChoice> added;
  final List<AdminNodeChoice> removed;

  const _ChoicesDiff({required this.added, required this.removed});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final choice in added) _ChoiceDiffRow(choice: choice, added: true),
        for (final choice in removed)
          _ChoiceDiffRow(choice: choice, added: false),
      ],
    );
  }
}

class _ChoiceDiffRow extends StatelessWidget {
  final AdminNodeChoice choice;
  final bool added;

  const _ChoiceDiffRow({required this.choice, required this.added});

  @override
  Widget build(BuildContext context) {
    final color = added ? AdminColors.approveText : AdminColors.rejectText;
    final label = choice.label.isEmpty ? '(문구 없음)' : choice.label;
    final target = choice.nextNodeId.isEmpty ? '(대상 없음)' : choice.nextNodeId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        '${added ? '+' : '−'} $label → $target',
        style: TextStyle(
          fontSize: 12.5,
          color: color,
          decoration: added ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: disabled ? AdminColors.panel2 : bg,
          border: Border.all(color: disabled ? AdminColors.border : border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: disabled ? AdminColors.muted : fg,
          ),
        ),
      ),
    );
  }
}
