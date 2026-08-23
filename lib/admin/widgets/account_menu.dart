import 'package:flutter/material.dart';

import '../../core/constants/external_links.dart';
import '../../core/platform/open_external_link.dart';
import 'admin_theme.dart';

/// 라이트/다크 토글 — admin_theme.dart 상단 doc에 적어 둔 대로, 지금은
/// MaterialApp.themeMode만 바꾼다(기본 Material 위젯에만 반영, AdminColors로
/// 직접 칠한 화면 대부분은 아직 반응하지 않는다).
///
/// 원래 author_tool_page.dart에만 있던 private 위젯이었다 —
/// admin_dashboard_page.dart의 상단 바도 같은 토글을 쓰게 되면서 공용
/// 위젯으로 옮겼다.
class ThemeModeToggle extends StatelessWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AdminTheme.mode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return InkWell(
          onTap: () => AdminTheme.toggle(),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              // 다크 모드일 때 "라이트로 바꾸는 버튼"이므로 해 아이콘이 맞다.
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 18,
              color: AdminColors.muted,
            ),
          ),
        );
      },
    );
  }
}

/// 아바타 + 드롭다운 — 이메일, 작가 도구로(선택)/독자로 보기/관리자
/// 페이지(선택)/로그아웃이 이 안에 들어간다.
///
/// 원래 author_tool_page.dart에만 있던 private `_AccountMenu`였다 —
/// admin_dashboard_page.dart의 상단 바가 예전 텍스트 링크 3개짜리 스타일
/// 대신 같은 아바타 드롭다운을 쓰게 되면서 공용 위젯으로 옮기고, 화면마다
/// 다른 두 가지를 옵션으로 열어 뒀다:
/// - [onBackToAuthorTool]: 작가 도구 화면 자체에서는 필요 없는 항목(자기
///   자신으로 돌아가는 링크는 의미가 없다)이라 null이면 그냥 안 보인다.
///   관리자 대시보드에서는 `Navigator.pop`으로 제자리 이동한다 — 독자로
///   보기/관리자 페이지처럼 새 창을 여는 게 아니라서 옆에 open_in_new
///   아이콘을 안 붙인다.
/// - [showAdminLink]: "관리자 페이지" 항목을 이 화면에서 보여줄지. [isAdmin]
///   (실제 권한)과는 별개 값이다 — 관리자 대시보드 화면 자체에서는 이미 그
///   페이지에 있으므로 [isAdmin]이 true여도 이 값을 false로 줘서 자기
///   자신을 가리키는 항목을 숨긴다.
class AccountMenu extends StatelessWidget {
  final String email;
  final bool isAdmin;

  /// "관리자 페이지" 항목을 보여줄지 — [isAdmin]과 별개(위 클래스 문서 참고).
  final bool showAdminLink;

  /// [isAdmin]과 [showAdminLink]가 둘 다 true일 때만 쓰인다.
  final VoidCallback? onOpenAdminDashboard;

  /// null이면 "작가 도구로" 항목 자체가 안 보인다.
  final VoidCallback? onBackToAuthorTool;

  final VoidCallback onSignOut;

  const AccountMenu({
    super.key,
    required this.email,
    required this.isAdmin,
    this.showAdminLink = true,
    this.onOpenAdminDashboard,
    this.onBackToAuthorTool,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final initial = email.isEmpty ? '?' : email.characters.first.toUpperCase();
    final showAdmin = isAdmin && showAdminLink && onOpenAdminDashboard != null;
    final showBackToAuthorTool = onBackToAuthorTool != null;

    return PopupMenuButton<String>(
      tooltip: '',
      color: AdminColors.panel2,
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AdminColors.border),
      ),
      onSelected: (value) {
        switch (value) {
          case 'authorTool':
            onBackToAuthorTool?.call();
          case 'reader':
            openExternalLink(ExternalLinks.readerAppUrl);
          case 'admin':
            onOpenAdminDashboard?.call();
          case 'signout':
            onSignOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 40,
          child: Text(
            email,
            style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
          ),
        ),
        if (showBackToAuthorTool)
          PopupMenuItem<String>(
            value: 'authorTool',
            height: 42,
            child: Text(
              '작가 도구로',
              style: TextStyle(fontSize: 13, color: AdminColors.ivory),
            ),
          ),
        PopupMenuItem<String>(
          value: 'reader',
          height: 42,
          child: Row(
            children: [
              Text(
                '독자로 보기',
                style: TextStyle(fontSize: 13, color: AdminColors.ivory),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: AdminColors.muted,
              ),
            ],
          ),
        ),
        if (showAdmin)
          PopupMenuItem<String>(
            value: 'admin',
            height: 42,
            child: Row(
              children: [
                Text(
                  '관리자 페이지',
                  style: TextStyle(fontSize: 13, color: AdminColors.ivory),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: AdminColors.muted,
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'signout',
          height: 42,
          child: Text(
            '로그아웃',
            style: TextStyle(fontSize: 13, color: AdminColors.ivory),
          ),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 5, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AdminColors.badgeBg,
                shape: BoxShape.circle,
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.gold,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Icon(Icons.expand_more_rounded, size: 16, color: AdminColors.muted),
          ],
        ),
      ),
    );
  }
}
