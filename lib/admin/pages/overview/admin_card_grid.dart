import 'package:flutter/material.dart';

/// 개요 화면의 카드 행 배치 규칙 한 곳 — 목업의
/// `grid-template-columns: repeat(auto-fill, minmax(180px, 1fr))`와 같은
/// 동작이다: 최소 [minCardWidth]를 지키면서 들어갈 수 있는 만큼 한 줄에 넣고,
/// 남는 폭은 그 줄의 카드들이 나눠 갖는다.
///
/// 숫자 카드(MetricCard)와 매출 카드가 같은 리듬을 유지해야 해서, 두
/// 파일에 같은 LayoutBuilder를 복붙하지 않고 여기로 모았다.
class AdminCardGrid extends StatelessWidget {
  final List<Widget> children;
  final double minCardWidth;
  final double gap;

  const AdminCardGrid({
    super.key,
    required this.children,
    this.minCardWidth = 180,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = ((constraints.maxWidth + gap) / (minCardWidth + gap))
            .floor();
        if (columns < 1) columns = 1;
        if (columns > children.length) columns = children.length;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
