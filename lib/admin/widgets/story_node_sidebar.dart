import 'package:flutter/material.dart';

import '../models/admin_story_node_summary.dart';
import 'admin_theme.dart';
import 'status_tag.dart';

/// sidebar — "+ 새 스토리 노드" 버튼 + 일괄 삭제 툴바 + 드래그로 순서를 바꿀
/// 수 있는 노드 목록(상태 배지 포함).
class StoryNodeSidebar extends StatelessWidget {
  final List<AdminStoryNodeSummary> nodes;
  final String? selectedNodeId;

  /// 세션 캐시(node_edit_session_cache.dart)에 저장 안 한 편집 내용이 있는
  /// 노드 id 전부 — 선택 여부와 무관하게, 목록에 있는 모든 노드에 대해
  /// "수정됨" 배지를 보여주는 데 쓴다.
  final Set<String> unsavedNodeIds;

  final VoidCallback onAddNode;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  /// 드래그로 노드 순서를 바꿨을 때 — ReorderableListView 관례 그대로
  /// (oldIndex, newIndex)를 넘긴다. story_tab_view.dart가 order 값을
  /// 다시 매겨 세션 캐시에 반영한다(즉시 Firestore에 쓰지 않는다).
  final void Function(int oldIndex, int newIndex) onReorder;

  /// 일괄 삭제 선택 상태 — story_tab_view.dart의 State가 들고 있는다(다른
  /// 편집 상태와 같은 패턴).
  final Set<String> bulkSelectedIds;
  final ValueChanged<String> onToggleBulkSelect;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onBulkDelete;

  const StoryNodeSidebar({
    super.key,
    required this.nodes,
    required this.selectedNodeId,
    required this.unsavedNodeIds,
    required this.onAddNode,
    required this.onSelect,
    required this.onDelete,
    required this.onReorder,
    required this.bulkSelectedIds,
    required this.onToggleBulkSelect,
    required this.onToggleSelectAll,
    required this.onBulkDelete,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected =
        nodes.isNotEmpty && bulkSelectedIds.length == nodes.length;

    return Container(
      width: 260,
      color: AdminColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ReorderableListView(
        padding: const EdgeInsets.symmetric(vertical: 14),
        onReorder: onReorder,
        // 기본값 true면 우리가 직접 넣은 드래그 핸들(_NodeItem 안의
        // ReorderableDragStartListener) 말고도 Flutter가 각 항목 끝에
        // 자기 기본 드래그 핸들을 하나 더 겹쳐 그린다 — 삭제 아이콘 아래에
        // 뜬 정체불명의 "≡"가 바로 그 기본 핸들이었다(실제로 겪은 버그).
        buildDefaultDragHandles: false,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAddNode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.coralSoftBg,
                    foregroundColor: AdminColors.coralSoftText,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '+ 새 스토리 노드',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: allSelected,
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
                      onChanged: nodes.isEmpty
                          ? null
                          : (_) => onToggleSelectAll(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '전체 선택',
                    style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: bulkSelectedIds.isEmpty ? null : onBulkDelete,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: bulkSelectedIds.isEmpty
                            ? AdminColors.panel2
                            : AdminColors.rejectBg,
                        border: Border.all(
                          color: bulkSelectedIds.isEmpty
                              ? AdminColors.border
                              : AdminColors.rejectBorder,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '선택 삭제 (${bulkSelectedIds.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: bulkSelectedIds.isEmpty
                              ? AdminColors.muted
                              : AdminColors.rejectText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        children: [
          for (var i = 0; i < nodes.length; i++)
            _NodeItem(
              key: ValueKey(nodes[i].id),
              index: i,
              node: nodes[i],
              active: nodes[i].id == selectedNodeId,
              hasUnsavedEdits: unsavedNodeIds.contains(nodes[i].id),
              checked: bulkSelectedIds.contains(nodes[i].id),
              onTap: () => onSelect(nodes[i].id),
              onDelete: () => onDelete(nodes[i].id),
              onToggleChecked: () => onToggleBulkSelect(nodes[i].id),
            ),
        ],
      ),
    );
  }
}

class _NodeItem extends StatelessWidget {
  final int index;
  final AdminStoryNodeSummary node;
  final bool active;
  final bool hasUnsavedEdits;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleChecked;

  const _NodeItem({
    required super.key,
    required this.index,
    required this.node,
    required this.active,
    required this.hasUnsavedEdits,
    required this.checked,
    required this.onTap,
    required this.onDelete,
    required this.onToggleChecked,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? Colors.transparent : AdminColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AdminColors.gold : Colors.transparent,
            width: active ? 1 : 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: checked,
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
                onChanged: (_) => onToggleChecked(),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.preview.isEmpty ? '(내용 없음)' : node.preview,
                      style: TextStyle(
                        fontSize: 13,
                        color: active ? AdminColors.ivory : AdminColors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StatusTag(
                          status: node.status,
                          pendingAction: node.pendingAction,
                        ),
                        if (hasUnsavedEdits) ...[
                          const SizedBox(width: 4),
                          const _UnsavedBadge(),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            node.id,
                            style: TextStyle(
                              fontSize: 11,
                              color: AdminColors.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 18,
                  color: AdminColors.muted,
                ),
              ),
            ),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AdminColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// StatusTag 옆에 붙는 작은 표시 — 실제 발행 상태(초안/연재중/승인대기)와는
/// 별개로, 이 노드에 세션 캐시(브라우저 탭 한정, Firestore에 아직 안 반영된)
/// 편집 내용이 있음을 알려준다.
class _UnsavedBadge extends StatelessWidget {
  const _UnsavedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AdminColors.gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AdminColors.gold.withOpacity(0.55)),
      ),
      child: const Text(
        '수정됨',
        style: TextStyle(
          fontSize: 9.5,
          color: AdminColors.gold,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
