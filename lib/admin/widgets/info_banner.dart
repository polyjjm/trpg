import 'package:flutter/material.dart';

import 'admin_theme.dart';

enum InfoBannerStyle { dirty, live, rejected }

/// `.dirty-banner` / `.live-note` / 반려 안내 — 노드 편집 화면 위쪽에 뜨는
/// 상태 안내 배너. rejected는 approvals_tab.dart에서 admin이 남긴
/// rejectionReason을 작가에게 보여줄 때 쓴다(node_editor.dart 참고).
class InfoBanner extends StatelessWidget {
  final String text;
  final InfoBannerStyle style;

  const InfoBanner({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final bg = switch (style) {
      InfoBannerStyle.dirty => AdminColors.dirtyBannerBg,
      InfoBannerStyle.live => AdminColors.liveNoteBg,
      InfoBannerStyle.rejected => AdminColors.rejectBg,
    };
    final border = switch (style) {
      InfoBannerStyle.dirty => AdminColors.dirtyBannerBorder,
      InfoBannerStyle.live => AdminColors.liveNoteBorder,
      InfoBannerStyle.rejected => AdminColors.rejectBorder,
    };
    final text0 = switch (style) {
      InfoBannerStyle.dirty => AdminColors.dirtyBannerText,
      InfoBannerStyle.live => AdminColors.liveNoteText,
      InfoBannerStyle.rejected => AdminColors.rejectText,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: text0, height: 1.4),
      ),
    );
  }
}
