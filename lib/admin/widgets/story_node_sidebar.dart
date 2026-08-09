import 'package:flutter/material.dart';

import '../models/admin_story_node_summary.dart';
import 'admin_theme.dart';
import 'status_tag.dart';

/// sidebar — "+ 새 스토리 노드" 버튼 + 노드 목록(상태 배지 포함).
class StoryNodeSidebar extends StatelessWidget {
  final List<AdminStoryNodeSummary> nodes;
  final String? selectedNodeId;
  final bool selectedNodeDirty;
  final VoidCallback onAddNode;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  const StoryNodeSidebar({
    super.key,
    required this.nodes,
    required this.selectedNodeId,
    required this.selectedNodeDirty,
    required this.onAddNode,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: AdminColors.panel,
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onAddNode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.gold,
                foregroundColor: const Color(0xFF111111),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('+ 새 스토리 노드', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
          for (final node in nodes)
            _NodeItem(
              node: node,
              active: node.id == selectedNodeId,
              dirty: node.id == selectedNodeId && selectedNodeDirty,
              onTap: () => onSelect(node.id),
              onDelete: () => onDelete(node.id),
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
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NodeItem({
    required this.node,
    required this.active,
    required this.dirty,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AdminColors.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AdminColors.border : Colors.transparent),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          node.title.isEmpty ? '(제목 없음)' : node.title,
                          style: TextStyle(
                            fontSize: 13,
                            color: active ? AdminColors.ivory : AdminColors.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      StatusTag(status: node.status, pendingAction: node.pendingAction, dirty: dirty),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(node.id, style: const TextStyle(fontSize: 11, color: Color(0xFF5C5C66))),
                ],
              ),
            ),
            InkWell(
              onTap: onDelete,
              child: const Text('삭제', style: TextStyle(fontSize: 11, color: AdminColors.danger)),
            ),
          ],
        ),
      ),
    );
  }
}
