import 'package:flutter/material.dart';

import '../models/admin_story_node_summary.dart';
import 'admin_theme.dart';
import 'status_tag.dart';

/// sidebar — "+ 새 스토리 노드" 버튼 + 일괄 삭제 툴바 + 노드 목록(상태 배지 포함).
class StoryNodeSidebar extends StatelessWidget {
  final List<AdminStoryNodeSummary> nodes;
  final String? selectedNodeId;
  final bool selectedNodeDirty;
  final VoidCallback onAddNode;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

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
    required this.selectedNodeDirty,
    required this.onAddNode,
    required this.onSelect,
    required this.onDelete,
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
      padding: const EdgeInsets.all(14),
      child: ListView(
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
                  onChanged: nodes.isEmpty ? null : (_) => onToggleSelectAll(),
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
          const SizedBox(height: 10),
          for (final node in nodes)
            _NodeItem(
              node: node,
              active: node.id == selectedNodeId,
              dirty: node.id == selectedNodeId && selectedNodeDirty,
              checked: bulkSelectedIds.contains(node.id),
              onTap: () => onSelect(node.id),
              onDelete: () => onDelete(node.id),
              onToggleChecked: () => onToggleBulkSelect(node.id),
            ),
        ],
      ),
    );
  }
}

class _NodeItem extends StatelessWidget {
  final AdminStoryNodeSummary node;
  final bool active;
  final bool dirty;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleChecked;

  const _NodeItem({
    required this.node,
    required this.active,
    required this.dirty,
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
                          dirty: dirty,
                        ),
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
            const SizedBox(width: 8),
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
