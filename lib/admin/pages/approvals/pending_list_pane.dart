import 'package:flutter/material.dart';

import '../../data/node_diff.dart';
import '../../models/activity_event.dart';
import '../../models/pending_action.dart';
import '../../models/pending_node_ref.dart';
import '../../models/story_pack_type.dart';
import '../../widgets/admin_theme.dart';
import 'approval_filter.dart';
import 'node_diff_view.dart';

/// 승인 대기함 왼쪽의 요청 목록 — 작품별로 묶고, 행마다 요청 유형·노드 ID·
/// 대기 시간·변경 태그만 보여준다. diff 본문은 오른쪽 상세 패널의 몫이다.
///
/// 예전엔 카드마다 diff 전체가 펼쳐져 있어서 요청이 열 건만 넘어도 "지금 뭐가
/// 밀려 있는지"를 스크롤 없이 파악할 수 없었다 — 목록은 훑는 화면, 상세는
/// 판단하는 화면으로 역할을 나눴다.
class PendingListPane extends StatelessWidget {
  final List<PendingGroup> groups;
  final Map<String, StoryPackType> packTypes;

  /// `packId/nodeId` 키.
  final String? selectedKey;
  final Set<String> checkedKeys;
  final int visibleCount;

  final ValueChanged<PendingNodeRef> onSelect;
  final ValueChanged<PendingNodeRef> onToggleCheck;
  final VoidCallback onToggleAll;
  final VoidCallback onClearChecks;
  final VoidCallback onBatchApprove;
  final bool batchRunning;

  /// "처리됨"/"전체" 상태 필터일 때만 채워진다 — 승인/반려 이력
  /// (activityLog)이다. 대기 목록과 같은 행 컴포넌트 관례(패딩/선택
  /// 표시/배지 스타일)를 따르는 [_HistoryRow]로 그리되, 체크박스와
  /// 승인·반려 버튼은 없다(요청 사양) — 이미 끝난 일이라 다시 처리할
  /// 대상이 아니다. 대기 목록 아래에 별도 섹션으로 이어 붙는다.
  final List<ActivityEvent> historyEntries;
  final String? selectedHistoryKey;
  final ValueChanged<ActivityEvent> onSelectHistory;

  const PendingListPane({
    super.key,
    required this.groups,
    required this.packTypes,
    required this.selectedKey,
    required this.checkedKeys,
    required this.visibleCount,
    required this.onSelect,
    required this.onToggleCheck,
    required this.onToggleAll,
    required this.onClearChecks,
    required this.onBatchApprove,
    required this.batchRunning,
    this.historyEntries = const [],
    this.selectedHistoryKey,
    required this.onSelectHistory,
  });

  static String keyFor(PendingNodeRef ref) => '${ref.packId}/${ref.node.id}';

  /// [historyEntries] 선택 키 — 대기 항목 키(`packId/nodeId`)와 절대 겹치지
  /// 않게 접두어를 둔다(activityLog 문서 id는 자동 생성 id라 형식이 다르지만,
  /// 그래도 명시적으로 구분해 두는 편이 안전하다).
  static String historyKeyFor(ActivityEvent event) => 'history/${event.id}';

  @override
  Widget build(BuildContext context) {
    final allChecked = visibleCount > 0 && checkedKeys.length >= visibleCount;

    return Container(
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        border: Border(right: BorderSide(color: AdminColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AdminColors.border)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: onToggleAll,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AdminColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      allChecked ? '전체 해제' : '전체 선택',
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '$visibleCount건 표시',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty && historyEntries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '조건에 해당하는 요청이 없어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.muted,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final group in groups) ...[
                        _GroupHeader(group: group),
                        for (final ref in group.items)
                          _PendingRow(
                            ref: ref,
                            packType:
                                packTypes[ref.packId] ??
                                StoryPackType.interactive,
                            selected: selectedKey == keyFor(ref),
                            checked: checkedKeys.contains(keyFor(ref)),
                            onSelect: () => onSelect(ref),
                            onToggleCheck: () => onToggleCheck(ref),
                          ),
                      ],
                      if (historyEntries.isNotEmpty) ...[
                        _HistorySectionHeader(count: historyEntries.length),
                        for (final event in historyEntries)
                          _HistoryRow(
                            event: event,
                            selected:
                                selectedHistoryKey == historyKeyFor(event),
                            onSelect: () => onSelectHistory(event),
                          ),
                      ],
                    ],
                  ),
          ),
          if (checkedKeys.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AdminColors.panel,
                border: Border(top: BorderSide(color: AdminColors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    '${checkedKeys.length}건 선택',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AdminColors.ivory,
                    ),
                  ),
                  const Spacer(),
                  ApprovalActionButton(
                    label: batchRunning ? '승인 처리 중…' : '일괄 승인',
                    bg: AdminColors.approveBg,
                    fg: AdminColors.approveText,
                    border: AdminColors.approveBorder,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    fontSize: 12,
                    onTap: batchRunning ? null : onBatchApprove,
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onClearChecks,
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AdminColors.border),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '해제',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final PendingGroup group;

  const _GroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              group.packTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AdminColors.ivory,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AdminColors.badgeBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${group.items.length}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AdminColors.statusDraftText,
              ),
            ),
          ),
          const Spacer(),
          Text(
            group.authorName,
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        ],
      ),
    );
  }
}

class _HistorySectionHeader extends StatelessWidget {
  final int count;

  const _HistorySectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          Text(
            '처리됨',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AdminColors.ivory,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AdminColors.badgeBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AdminColors.statusDraftText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 처리 이력 한 줄 — [_PendingRow]와 같은 패딩/선택 표시(왼쪽 골드 선) 관례를
/// 따르되, 체크박스와 요청 유형(등록/수정/삭제) 대신 승인/반려 결과 배지를
/// 보여준다(요청 사양: "체크박스와 승인·반려 버튼은 없앤다"). diff 태그도
/// 없다 — 처리 이력엔 다시 비교할 대상이 없다.
class _HistoryRow extends StatelessWidget {
  final ActivityEvent event;
  final bool selected;
  final VoidCallback onSelect;

  const _HistoryRow({
    required this.event,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final approved = event.kind == ActivityKind.nodeApproved;
    final resultBg = approved ? AdminColors.approveBg : AdminColors.rejectBg;
    final resultFg = approved
        ? AdminColors.approveText
        : AdminColors.rejectText;

    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AdminColors.badgeBg : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: AdminColors.border),
            left: BorderSide(
              color: selected ? AdminColors.gold : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 체크박스가 없는 대신 자리를 비워 대기 목록 행과 좌우 정렬을
            // 맞춘다(체크박스 폭 16 + 여백 10).
            const SizedBox(width: 26),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: resultBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          approved ? '승인됨' : '반려됨',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: resultFg,
                          ),
                        ),
                      ),
                      if (event.nodeId != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            event.nodeId!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AdminColors.ivory,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        formatWaitedLabel(event.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final PendingNodeRef ref;
  final StoryPackType packType;
  final bool selected;
  final bool checked;
  final VoidCallback onSelect;
  final VoidCallback onToggleCheck;

  const _PendingRow({
    required this.ref,
    required this.packType,
    required this.selected,
    required this.checked,
    required this.onSelect,
    required this.onToggleCheck,
  });

  static const _kindLabel = {
    PendingAction.create: '등록',
    PendingAction.edit: '수정',
    PendingAction.delete: '삭제',
  };

  (Color, Color) _kindColors() {
    switch (ref.node.pendingAction) {
      case PendingAction.delete:
        return (
          AdminColors.statusPendingDeleteBg,
          AdminColors.statusPendingDeleteText,
        );
      case PendingAction.create:
        return (AdminColors.approveBg, AdminColors.approveText);
      default:
        return (AdminColors.statusPendingBg, AdminColors.statusPendingText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDelete = ref.node.pendingAction == PendingAction.delete;
    // 삭제 요청은 비교할 "새 콘텐츠"가 없다 — 태그도 붙지 않는다.
    final diff = isDelete ? null : NodeDiff.compute(ref.node);
    final (kindBg, kindFg) = _kindColors();
    final preview = ref.node.previewText;

    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AdminColors.badgeBg : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: AdminColors.border),
            left: BorderSide(
              color: selected ? AdminColors.gold : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 체크박스만 따로 탭 가능해야 한다 — 행 전체 탭은 "상세 열기"다.
            InkWell(
              onTap: onToggleCheck,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: checked
                      ? AdminColors.gold
                      : AdminColors.checkboxUncheckedFill,
                  border: Border.all(
                    color: checked
                        ? AdminColors.gold
                        : AdminColors.checkboxUncheckedBorder,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: checked
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kindBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _kindLabel[ref.node.pendingAction] ?? '-',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: kindFg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          ref.node.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AdminColors.ivory,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatWaitedLabel(ref.requestedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview.isEmpty ? '(내용 없음)' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                  if (diff != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: buildChangeTags(diff, packType),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
