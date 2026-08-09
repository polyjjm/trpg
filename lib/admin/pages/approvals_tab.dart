import 'package:flutter/material.dart';

import '../data/admin_story_repository.dart';
import '../models/pending_action.dart';
import '../models/pending_node_ref.dart';
import '../widgets/admin_theme.dart';

/// "승인 대기함" 탭 — 모든 스토리팩을 통틀어 pendingAction이 걸린 노드를 모아
/// 보여주고, 승인/반려를 처리한다. 지금은 역할 구분이 없어 이 화면 자체가
/// "관리자 시점 데모"를 겸한다(본사/대리점 역할은 나중 단계에서 분리한다).
class ApprovalsTab extends StatelessWidget {
  final AdminStoryRepository repository;
  final Map<String, String> packTitles;

  const ApprovalsTab({super.key, required this.repository, required this.packTitles});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('승인 대기함', style: TextStyle(fontSize: 16, color: AdminColors.ivory, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            '이 탭은 원래 대리점/본사 계정에서 보이는 화면이에요. 지금은 하나의 편집기 안에서 '
            '승인 흐름을 같이 확인해볼 수 있게 임시로 붙여놨어요.',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<PendingNodeRef>>(
            stream: repository.watchPendingNodes(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? const <PendingNodeRef>[];
              if (pending.isEmpty) {
                return const Text('대기 중인 요청이 없어요.', style: TextStyle(fontSize: 13, color: AdminColors.muted));
              }
              return Column(
                children: [
                  for (final ref in pending)
                    _ApprovalCard(
                      ref: ref,
                      packTitle: packTitles[ref.packId] ?? ref.packId,
                      onApprove: () => repository.approveNode(ref.packId, ref.node),
                      onReject: () => repository.rejectNode(ref.packId, ref.node),
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
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.ref,
    required this.packTitle,
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
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[$label] ${ref.node.title.isEmpty ? '(제목 없음)' : ref.node.title}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AdminColors.ivory),
                ),
                const SizedBox(height: 4),
                Text(
                  '스토리팩: $packTitle · 노드 ID: ${ref.node.id}',
                  style: const TextStyle(fontSize: 12, color: AdminColors.muted),
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
