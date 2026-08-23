import 'package:flutter/material.dart';

import 'admin_theme.dart';

/// 관리자 대시보드 개요 화면의 숫자 카드 하나. count가 null이면(아직 로딩
/// 중이거나 스트림 에러) 숫자 대신 "-"를 보여준다 — 0과 "아직 모름"을
/// 구분하기 위해서다.
///
/// [delta]는 숫자 오른쪽에 붙는 작은 보조 문구('+3 어제' 등). null이면 아예
/// 그려지지 않아서, 기존 호출부(label/count만 넘기는 곳)는 그대로 동작한다.
class MetricCard extends StatelessWidget {
  final String label;
  final int? count;
  final String? delta;

  const MetricCard({
    super.key,
    required this.label,
    required this.count,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                count == null ? '-' : '$count',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.gold,
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    delta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AdminColors.muted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: AdminColors.muted)),
        ],
      ),
    );
  }
}
