import 'package:flutter/material.dart';

import '../models/admin_story_node.dart';
import '../models/node_status.dart';
import '../models/pending_action.dart';
import 'admin_theme.dart';

/// renderStatusTag()와 동일한 우선순위로 노드 하나의 상태 배지를 그린다:
/// 로컬 미저장 변경 > 삭제 승인대기 > 등록/수정 승인대기 > 연재중 > 초안.
class StatusTag extends StatelessWidget {
  final NodeStatus status;
  final PendingAction? pendingAction;
  final bool dirty;

  const StatusTag({
    super.key,
    required this.status,
    required this.pendingAction,
    this.dirty = false,
  });

  factory StatusTag.forNode(AdminStoryNode node, {bool? dirtyOverride}) {
    return StatusTag(
      status: node.status,
      pendingAction: node.pendingAction,
      dirty: dirtyOverride ?? node.dirty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _resolve();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  (String, Color, Color) _resolve() {
    if (dirty) {
      return (
        '수정중(미저장)',
        AdminColors.statusDraftBg,
        AdminColors.statusDraftText,
      );
    }
    if (pendingAction == PendingAction.delete) {
      return (
        '삭제 승인대기',
        AdminColors.statusPendingDeleteBg,
        AdminColors.statusPendingDeleteText,
      );
    }
    if (pendingAction == PendingAction.create) {
      return (
        '등록 승인대기',
        AdminColors.statusPendingBg,
        AdminColors.statusPendingText,
      );
    }
    if (pendingAction == PendingAction.edit) {
      return (
        '수정 승인대기',
        AdminColors.statusPendingBg,
        AdminColors.statusPendingText,
      );
    }
    if (status == NodeStatus.published) {
      return (
        '연재중',
        AdminColors.statusPublishedBg,
        AdminColors.statusPublishedText,
      );
    }
    return ('초안', AdminColors.statusDraftBg, AdminColors.statusDraftText);
  }
}
