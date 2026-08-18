import 'package:flutter/material.dart';

import 'admin_theme.dart';

enum InfoBannerStyle { dirty, live }

/// `.dirty-banner` / `.live-note` — 노드 편집 화면 위쪽에 뜨는 상태 안내 배너.
class InfoBanner extends StatelessWidget {
  final String text;
  final InfoBannerStyle style;

  const InfoBanner({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final bg = style == InfoBannerStyle.dirty
        ? AdminColors.dirtyBannerBg
        : AdminColors.liveNoteBg;
    final border = style == InfoBannerStyle.dirty
        ? AdminColors.dirtyBannerBorder
        : AdminColors.liveNoteBorder;
    final text0 = style == InfoBannerStyle.dirty
        ? AdminColors.dirtyBannerText
        : AdminColors.liveNoteText;

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
