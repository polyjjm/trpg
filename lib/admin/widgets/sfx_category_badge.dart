import 'package:flutter/material.dart';

import '../models/admin_sfx_category.dart';
import 'admin_theme.dart';

/// CategoryBadge(이미지용)와 같은 모양의 작은 파스텔 배지 — 효과음 카드에서
/// 분류(문/발소리/비명/심장박동/기타)를 보여준다.
class SfxCategoryBadge extends StatelessWidget {
  final AdminSfxCategory category;

  const SfxCategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (category) {
      AdminSfxCategory.door => (
        AdminColors.sfxCategoryDoorBg,
        AdminColors.sfxCategoryDoorText,
      ),
      AdminSfxCategory.footsteps => (
        AdminColors.sfxCategoryFootstepsBg,
        AdminColors.sfxCategoryFootstepsText,
      ),
      AdminSfxCategory.scream => (
        AdminColors.sfxCategoryScreamBg,
        AdminColors.sfxCategoryScreamText,
      ),
      AdminSfxCategory.heartbeat => (
        AdminColors.sfxCategoryHeartbeatBg,
        AdminColors.sfxCategoryHeartbeatText,
      ),
      AdminSfxCategory.other => (
        AdminColors.sfxCategoryOtherBg,
        AdminColors.sfxCategoryOtherText,
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
