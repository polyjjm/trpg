import 'package:flutter/material.dart';

import 'admin_theme.dart';

/// 아직 기능이 없는 관리자 섹션(신고 처리 등)에서 쓰는 공용 "준비중" 상태.
/// 빈 화면 대신 최소한 "여기에 나중에 뭐가 생긴다"는 걸 보여준다.
class ComingSoonPlaceholder extends StatelessWidget {
  final String title;
  final String description;

  const ComingSoonPlaceholder({super.key, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_rounded, color: AdminColors.muted, size: 32),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminColors.ivory),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
