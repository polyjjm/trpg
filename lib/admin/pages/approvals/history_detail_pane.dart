import 'package:flutter/material.dart';

import '../../models/activity_event.dart';
import '../../widgets/admin_theme.dart';
import 'approval_filter.dart';

/// 승인 대기함 "처리됨"/"전체" 상태에서 오른쪽 상세로 쓴다 — 이미 끝난
/// 일이라 [PendingDetailPane]과 달리 diff도, 승인/반려 버튼도 없다. 볼 수
/// 있는 건 그 순간 기록해 둔 한 줄([ActivityEvent.message])과 처리 시각뿐
/// — 노드 내용은 그 뒤로 다시 바뀌었을 수 있어서 지금 시점의 diff를 다시
/// 계산해 보여주는 건 오히려 "그때 실제로 뭘 승인/반려했는지"를 왜곡한다.
class HistoryDetailPane extends StatelessWidget {
  final ActivityEvent? event;
  final String packTitle;

  /// 목록에서의 위치 — "3 / 12".
  final int index;
  final int total;

  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const HistoryDetailPane({
    super.key,
    required this.event,
    required this.packTitle,
    required this.index,
    required this.total,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final current = event;
    if (current == null) {
      return Center(
        child: Text(
          '왼쪽에서 처리 이력을 선택하세요.',
          style: TextStyle(fontSize: 13, color: AdminColors.muted),
        ),
      );
    }

    final approved = current.kind == ActivityKind.nodeApproved;
    final resultLabel = approved ? '승인됨' : '반려됨';
    final resultBg = approved ? AdminColors.approveBg : AdminColors.rejectBg;
    final resultBorder = approved
        ? AdminColors.approveBorder
        : AdminColors.rejectBorder;
    final resultText = approved
        ? AdminColors.approveText
        : AdminColors.rejectText;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '처리 이력',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.muted,
                ),
              ),
              if (current.nodeId != null)
                Text(
                  '노드 ${current.nodeId}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.ivory,
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: resultBg,
                  border: Border.all(color: resultBorder),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  resultLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: resultText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$packTitle · ${formatRequestedDate(current.createdAt)} 처리'
            '${current.createdAt == null ? '' : ' (${formatWaitedLabel(current.createdAt)} 전)'}',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AdminColors.panel2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminColors.border),
            ),
            child: Text(
              current.message,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.ivory,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '처리 이력은 그 순간 기록해 둔 요약만 보여줘요 — 지금 노드 내용은'
            ' 그 뒤로 다시 바뀌었을 수 있어서 세부 변경 비교는 제공하지 않아요.',
            style: TextStyle(
              fontSize: 11.5,
              color: AdminColors.muted,
              height: 1.6,
            ),
          ),
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
