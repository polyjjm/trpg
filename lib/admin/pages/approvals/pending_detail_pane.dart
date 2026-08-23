import 'package:flutter/material.dart';

import '../../data/node_diff.dart';
import '../../models/admin_image.dart';
import '../../models/pending_action.dart';
import '../../models/pending_node_ref.dart';
import '../../models/story_pack_type.dart';
import '../../widgets/admin_theme.dart';
import 'approval_filter.dart';
import 'node_diff_view.dart';

/// 승인 대기함 오른쪽 상세 — 한 요청의 diff 전체와 승인/반려 버튼.
///
/// 하단에 이전/다음이 있어서 목록으로 돌아가지 않고 연속으로 처리할 수 있다.
/// 승인/반려 직후에도 이 패널은 자리를 지킨다 — 처리 결과는 [handled]로
/// 배지만 바뀌고, 다음 항목으로 넘어가는 건 운영자가 결정한다(자동으로
/// 넘기면 방금 뭘 처리했는지 확인할 틈이 없다).
class PendingDetailPane extends StatelessWidget {
  final PendingNodeRef? ref;
  final String packTitle;
  final String authorName;
  final StoryPackType packType;
  final Map<String, AdminImage> imagesById;

  /// 이 노드를 방금 처리했는지 — '승인됨'/'반려됨' 배지.
  final String? handledLabel;
  final bool handledApproved;
  final bool processing;

  /// 목록에서의 위치 — "3 / 12".
  final int index;
  final int total;

  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onOpenInEditor;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const PendingDetailPane({
    super.key,
    required this.ref,
    required this.packTitle,
    required this.authorName,
    required this.packType,
    required this.imagesById,
    required this.handledLabel,
    required this.handledApproved,
    required this.processing,
    required this.index,
    required this.total,
    required this.onApprove,
    required this.onReject,
    this.onOpenInEditor,
    this.onPrev,
    this.onNext,
  });

  static const _kindLabel = {
    PendingAction.create: '신규 등록 요청',
    PendingAction.edit: '수정 요청',
    PendingAction.delete: '삭제 요청',
  };

  @override
  Widget build(BuildContext context) {
    final current = ref;
    if (current == null) {
      return Center(
        child: Text(
          '왼쪽에서 요청을 선택하세요.',
          style: TextStyle(fontSize: 13, color: AdminColors.muted),
        ),
      );
    }

    final node = current.node;
    final isDelete = node.pendingAction == PendingAction.delete;
    final diff = isDelete ? null : NodeDiff.compute(node);
    final handled = handledLabel != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _kindLabel[node.pendingAction] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.muted,
                          ),
                        ),
                        Text(
                          '노드 ${node.id}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.ivory,
                          ),
                        ),
                        if (handled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: handledApproved
                                  ? AdminColors.approveBg
                                  : AdminColors.rejectBg,
                              border: Border.all(
                                color: handledApproved
                                    ? AdminColors.approveBorder
                                    : AdminColors.rejectBorder,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              handledLabel!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: handledApproved
                                    ? AdminColors.approveText
                                    : AdminColors.rejectText,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$packTitle · $authorName · '
                      '${formatRequestedDate(current.requestedAt)} 요청'
                      '${current.requestedAt == null ? '' : ' (${formatWaitedLabel(current.requestedAt)} 대기)'}',
                      style: TextStyle(fontSize: 12, color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!handled)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ApprovalActionButton(
                      label: '승인',
                      bg: AdminColors.approveBg,
                      fg: AdminColors.approveText,
                      border: AdminColors.approveBorder,
                      onTap: processing ? null : onApprove,
                    ),
                    ApprovalActionButton(
                      label: '반려',
                      bg: AdminColors.rejectBg,
                      fg: AdminColors.rejectText,
                      border: AdminColors.rejectBorder,
                      onTap: processing ? null : onReject,
                    ),
                    if (onOpenInEditor != null)
                      ApprovalActionButton(
                        label: '편집기에서 열기',
                        bg: AdminColors.panel2,
                        fg: AdminColors.muted,
                        border: AdminColors.border,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        onTap: onOpenInEditor,
                      ),
                  ],
                ),
            ],
          ),

          if (diff != null && diff.anyChanged) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: buildChangeTags(diff, packType),
            ),
          ],

          if (isDelete) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: AdminColors.statusPendingDeleteBg,
                border: Border.all(color: AdminColors.rejectBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '삭제 요청',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.statusPendingDeleteText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '승인하면 문서가 완전히 지워지고, 반려하면 삭제 요청만 취소되고 노드는 그대로 남아요.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AdminColors.ivory,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (diff != null) ...[
            if (diff.bodyChanged) ...[
              const SizedBox(height: 22),
              const DiffSectionLabel('본문'),
              const SizedBox(height: 6),
              BodyDiffText(segments: diff.bodySegments),
            ],
            if (diff.orderChanged) ...[
              const SizedBox(height: 20),
              const DiffSectionLabel('순서'),
              const SizedBox(height: 6),
              OrderDiff(
                beforeOrder: diff.beforeOrder!,
                afterOrder: diff.afterOrder,
              ),
            ],
            if (diff.backgroundChanged) ...[
              const SizedBox(height: 20),
              const DiffSectionLabel('배경 이미지'),
              const SizedBox(height: 8),
              BackgroundImageDiff(
                beforeImage: imagesById[diff.beforeBackgroundImageId],
                afterImage: imagesById[diff.afterBackgroundImageId],
              ),
            ],
            if (packType == StoryPackType.interactive &&
                diff.choicesChanged) ...[
              const SizedBox(height: 20),
              const DiffSectionLabel('선택지'),
              const SizedBox(height: 6),
              ChoicesDiff(
                added: diff.addedChoices,
                removed: diff.removedChoices,
              ),
            ],
            if (diff.effectsChanged) ...[
              const SizedBox(height: 20),
              const DiffSectionLabel('연출 효과'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AdminColors.panel2,
                  border: Border.all(color: AdminColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '연출 효과(암전/화면 흔들림/효과음/화면 플래시/진동/배경음악/내레이션) '
                  '설정이 바뀌었어요 — 자세한 값은 노드 편집 화면에서 확인하세요.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AdminColors.muted,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            if (!diff.anyChanged) ...[
              const SizedBox(height: 20),
              Text(
                '내용상 변경 없음 — 승인된 버전과 완전히 같아요(이미 같은 내용을 다시 제출했어요).',
                style: TextStyle(fontSize: 12.5, color: AdminColors.muted),
              ),
            ],
          ],

          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.only(top: 18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AdminColors.border)),
            ),
            child: Row(
              children: [
                Text(
                  '${index + 1} / $total',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
                const Spacer(),
                _NavButton(label: '← 이전', onTap: onPrev),
                const SizedBox(width: 8),
                _NavButton(label: '다음 →', onTap: onNext),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _NavButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AdminColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            softWrap: false,
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
        ),
      ),
    );
  }
}
