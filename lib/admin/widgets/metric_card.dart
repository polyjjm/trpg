import 'package:flutter/material.dart';

import 'admin_theme.dart';

/// 관리자 대시보드 개요 화면의 숫자 카드 하나. count가 null이면(아직 로딩
/// 중이거나 스트림 에러) 숫자 대신 "-"를 보여준다 — 0과 "아직 모름"을
/// 구분하기 위해서다.
class MetricCard extends StatelessWidget {
  final String label;
  final int? count;

  const MetricCard({super.key, required this.label, required this.count});

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
          Text(
            count == null ? '-' : '$count',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AdminColors.gold),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AdminColors.muted)),
        ],
      ),
    );
  }
}
