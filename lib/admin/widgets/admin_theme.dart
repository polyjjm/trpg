import 'package:flutter/material.dart';

/// story_editor_prototype.html의 CSS 색상 변수를 그대로 옮긴 팔레트.
/// lib/admin/ 안에서만 쓰는 공용 상수라, 파일마다 private 색상 상수를 반복하는
/// 게임 쪽 관례 대신 한 곳에 모아 둔다.
class AdminColors {
  AdminColors._();

  static const bg = Color(0xFF0E0E10);
  static const panel = Color(0xFF17171A);
  static const panel2 = Color(0xFF1E1E22);
  static const border = Color(0xFF2A2A2F);
  static const ivory = Color(0xFFE2D4BF);
  static const gold = Color(0xFFF0E68C);
  static const muted = Color(0xFF8A8A92);
  static const danger = Color(0xFFE0524B);
  static const accent = Color(0xFF4B8EE0);
  static const ok = Color(0xFF6FBF73);

  static const statusDraftBg = Color(0xFF3A3A2A);
  static const statusDraftText = Color(0xFFD8C98A);
  static const statusPublishedBg = Color(0xFF1F3D24);
  static const statusPublishedText = Color(0xFF7FD98A);
  static const statusPendingBg = Color(0xFF2A2E42);
  static const statusPendingText = Color(0xFF9DB3FF);
  static const statusPendingDeleteBg = Color(0xFF422A2A);
  static const statusPendingDeleteText = Color(0xFFFF9D9D);

  static const dirtyBannerBg = Color(0xFF3D2F1A);
  static const dirtyBannerBorder = Color(0xFF6B5324);
  static const dirtyBannerText = Color(0xFFE8C877);

  static const liveNoteBg = Color(0xFF1A2D3D);
  static const liveNoteBorder = Color(0xFF244A63);
  static const liveNoteText = Color(0xFF8FC7E8);

  static const approveBg = Color(0xFF1F3D24);
  static const approveText = Color(0xFF7FD98A);
  static const approveBorder = Color(0xFF2C5C34);
  static const rejectBg = Color(0xFF3D1F1F);
  static const rejectText = Color(0xFFFF9D9D);
  static const rejectBorder = Color(0xFF5C2C2C);
}
