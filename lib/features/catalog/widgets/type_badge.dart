import 'package:flutter/material.dart';

import '../models/story_pack.dart';

/// 인터랙티브(청록 + 분기 아이콘)/선형(파랑 + 책 아이콘) 형식을 색으로
/// 한눈에 구별하는 작은 원형 배지. 표지 색과 무관하게 항상 같은 고정 색을
/// 쓴다 — 표지마다 색이 다르면 "이게 인터랙티브였나 선형이었나" 매번 다시
/// 읽어야 해서, 스캔성이 색 일관성에 달려 있다.
///
/// ti-git-branch/ti-book-2(Tabler Icons) 아이콘을 그대로 쓰지 않는다 —
/// 이 프로젝트에 Tabler Icons 패키지가 없어서, 의미가 가장 가까운 Material
/// 아이콘(분기 경로 / 책)으로 대체했다.
class TypeBadge extends StatelessWidget {
  final StoryPackFormat format;
  final double size;

  const TypeBadge({super.key, required this.format, this.size = 22});

  static const Color _interactiveColor = Color(0xFF2AA198);
  static const Color _linearColor = Color(0xFF3A7BD5);

  @override
  Widget build(BuildContext context) {
    final isInteractive = format == StoryPackFormat.interactive;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isInteractive ? _interactiveColor : _linearColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        isInteractive ? Icons.call_split_rounded : Icons.menu_book_rounded,
        color: Colors.white,
        size: size * 0.58,
      ),
    );
  }
}
