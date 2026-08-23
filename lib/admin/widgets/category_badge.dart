import 'package:flutter/material.dart';

import '../models/admin_image_category.dart';
import 'admin_theme.dart';

/// StatusTag와 같은 모양의 작은 파스텔 배지 — 이미지 카드에서 분류(배경/
/// 선택지/기타)를 보여준다.
class CategoryBadge extends StatelessWidget {
  final AdminImageCategory category;

  const CategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (category) {
      AdminImageCategory.background => (
        AdminColors.imageCategoryBackgroundBg,
        AdminColors.imageCategoryBackgroundText,
      ),
      AdminImageCategory.choice => (
        AdminColors.imageCategoryChoiceBg,
        AdminColors.imageCategoryChoiceText,
      ),
      AdminImageCategory.other => (
        AdminColors.imageCategoryOtherBg,
        AdminColors.imageCategoryOtherText,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category.label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
