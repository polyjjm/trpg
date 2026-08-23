import 'package:flutter/material.dart';

import '../../widgets/admin_theme.dart';
import '../approvals/approval_filter.dart' show formatWaitedLabel;
import 'pack_approval_filter.dart';

/// 스토리팩 승인 화면 왼쪽의 요청 목록 — 요청 하나가 곧 팩 하나라 승인
/// 대기함(PendingListPane)처럼 팩 단위로 묶을 필요가 없다. 행마다 요청
/// 유형·작품 제목·작가·대기 시간만 보여준다.
class PackPendingListPane extends StatelessWidget {
  final List<PendingPackRequest> requests;
  final String? selectedKey;
  final ValueChanged<PendingPackRequest> onSelect;

  const PackPendingListPane({
    super.key,
    required this.requests,
    required this.selectedKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
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
                Text(
                  '${requests.length}건 표시',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: requests.isEmpty
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
                      for (final request in requests)
                        _RequestRow(
                          request: request,
                          selected: selectedKey == request.key,
                          onSelect: () => onSelect(request),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final PendingPackRequest request;
  final bool selected;
  final VoidCallback onSelect;

  const _RequestRow({
    required this.request,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final pack = request.pack;
    final isSerialization = request.kind == PackRequestKind.serialization;

    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AdminColors.panel : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? AdminColors.gold : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(color: AdminColors.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSerialization
                        ? AdminColors.statusPendingBg
                        : AdminColors.imageCategoryBackgroundBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    request.kind.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSerialization
                          ? AdminColors.statusPendingText
                          : AdminColors.imageCategoryBackgroundText,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  formatWaitedLabel(request.requestedAt),
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              pack.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AdminColors.ivory,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pack.authorName.isEmpty ? '(작가 이름 없음)' : pack.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AdminColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
