import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import '../../data/node_diff.dart';
import '../../models/admin_image.dart';
import '../../models/admin_node_choice.dart';
import '../../models/story_pack_type.dart';
import '../../widgets/admin_theme.dart';

/// 예전 approvals_tab.dart 안에 private으로 있던 diff 표시 위젯들을 그대로
/// 옮겨 공개한 것 — 목록 카드가 아니라 상세 패널에서 쓰게 되면서 파일이
/// 갈라졌기 때문이다. 표시 규칙(색·기호·문구)은 하나도 바꾸지 않았다:
/// 승인 판단의 기준이 되는 화면이라, 옮기는 김에 손보는 건 위험하다.

/// 변경 종류 배지 — 목록 행과 상세 헤더가 같은 걸 쓴다.
class ChangeTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const ChangeTag({
    super.key,
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

List<Widget> buildChangeTags(NodeDiff diff, StoryPackType packType) {
  return [
    if (diff.bodyChanged)
      const ChangeTag(
        label: '본문 수정',
        color: AdminColors.liveNoteText,
        bg: AdminColors.liveNoteBg,
      ),
    if (diff.orderChanged)
      const ChangeTag(
        label: '순서 변경',
        color: AdminColors.statusPendingText,
        bg: AdminColors.statusPendingBg,
      ),
    if (diff.backgroundChanged)
      const ChangeTag(
        label: '배경 이미지 변경',
        color: AdminColors.imageCategoryBackgroundText,
        bg: AdminColors.imageCategoryBackgroundBg,
      ),
    if (packType == StoryPackType.interactive && diff.choicesChanged)
      const ChangeTag(
        label: '선택지 변경',
        color: AdminColors.imageCategoryChoiceText,
        bg: AdminColors.imageCategoryChoiceBg,
      ),
    if (diff.effectsChanged)
      const ChangeTag(
        label: '연출 효과 변경',
        color: AdminColors.imageCategoryOtherText,
        bg: AdminColors.imageCategoryOtherBg,
      ),
  ];
}

class DiffSectionLabel extends StatelessWidget {
  final String text;

  const DiffSectionLabel(this.text, {super.key});

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
class BodyDiffText extends StatelessWidget {
  final List<Diff> segments;

  const BodyDiffText({super.key, required this.segments});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 13, color: AdminColors.ivory, height: 1.9),
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

/// "N번째 → M번째로 이동" — order는 항상 0-based라 NodeDiff.orderRankLabel로
/// 사람이 읽는 1-based 순번으로 바꿔서 보여준다.
class OrderDiff extends StatelessWidget {
  final int beforeOrder;
  final int afterOrder;

  const OrderDiff({
    super.key,
    required this.beforeOrder,
    required this.afterOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AdminColors.statusPendingBg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '${NodeDiff.orderRankLabel(beforeOrder)} → ${NodeDiff.orderRankLabel(afterOrder)}로 이동',
        style: const TextStyle(
          fontSize: 13,
          color: AdminColors.statusPendingText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class BackgroundImageDiff extends StatelessWidget {
  final AdminImage? beforeImage;
  final AdminImage? afterImage;

  const BackgroundImageDiff({
    super.key,
    required this.beforeImage,
    required this.afterImage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ImageThumb(image: beforeImage),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 132,
        height: 80,
        color: AdminColors.panel2,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.image_not_supported_outlined,
                  size: 18,
                  color: AdminColors.muted,
                ),
              )
            : Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 18,
                  color: AdminColors.muted,
                ),
              ),
      ),
    );
  }
}

class ChoicesDiff extends StatelessWidget {
  final List<AdminNodeChoice> added;
  final List<AdminNodeChoice> removed;

  const ChoicesDiff({super.key, required this.added, required this.removed});

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
    final label = choice.label.isEmpty ? '(문구 없음)' : choice.label;
    final target = choice.nextNodeId.isEmpty ? '(대상 없음)' : choice.nextNodeId;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: added ? AdminColors.approveBg : AdminColors.rejectBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${added ? '+' : '−'} $label → $target',
        style: TextStyle(
          fontSize: 13,
          color: added ? AdminColors.approveText : AdminColors.rejectText,
          decoration: added ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }
}

/// 승인/반려/보조 버튼 — 상세 헤더와 일괄 처리 바가 같은 걸 쓴다.
class ApprovalActionButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double fontSize;

  const ApprovalActionButton({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: disabled ? AdminColors.panel2 : bg,
          border: Border.all(color: disabled ? AdminColors.border : border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          softWrap: false,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: disabled ? AdminColors.muted : fg,
          ),
        ),
      ),
    );
  }
}

/// 반려 사유 입력 — 비워두면 보낼 수 없다(작가가 무엇을 고쳐야 하는지 모르는
/// 반려는 결국 다시 같은 내용으로 재제출된다).
Future<String?> promptRejectionReason(BuildContext context) {
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
