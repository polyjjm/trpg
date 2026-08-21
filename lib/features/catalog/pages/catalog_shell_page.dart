import 'package:flutter/material.dart';

import 'home_tab.dart';
import 'my_library_tab.dart';
import 'notice_list_tab.dart';
import 'settings_tab.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 로그인 직후 항상 이 화면으로 들어온다 — 하단 탭(홈/내 서재/공지사항/설정)을 가진
/// 라이브러리 셸. 각 탭은 IndexedStack으로 유지해 탭을 오갈 때 스크롤 위치와
/// 상태(검색어, 배너 로드 등)가 보존된다.
///
/// 하단 탭바는 Material의 기본 NavigationBar 대신 직접 만든 것을 쓴다 —
/// 이 앱은 커스텀 골드/아이보리 팔레트를 쓰고 Material3 colorScheme을 별도로
/// 설정하지 않아서, 기본 NavigationBar를 그대로 쓰면 엉뚱한 기본 보라색
/// 계열로 나온다. 게임 화면들의 FooterNavBar와 같은 시각 언어(검정 배경,
/// 아이보리/골드 아이콘)를 그대로 따른다.
class CatalogShellPage extends StatefulWidget {
  /// 웹에서 author/admin 계정으로 열었을 때만 true — 홈 탭에만 전달된다.
  final bool showAuthorModeLink;

  const CatalogShellPage({super.key, this.showAuthorModeLink = false});

  @override
  State<CatalogShellPage> createState() => _CatalogShellPageState();
}

class _CatalogShellPageState extends State<CatalogShellPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: IndexedStack(
        index: _index,
        children: [
          HomeTab(showAuthorModeLink: widget.showAuthorModeLink),
          const MyLibraryTab(),
          const NoticeListTab(),
          const SettingsTab(),
        ],
      ),
      bottomNavigationBar: _CatalogBottomNav(
        index: _index,
        onChanged: (index) => setState(() => _index = index),
      ),
    );
  }
}

class _CatalogBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _CatalogBottomNav({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.10))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavItem(icon: Icons.home_rounded, label: '홈', selected: index == 0, onTap: () => onChanged(0)),
            _NavItem(icon: Icons.bookmark_rounded, label: '내 서재', selected: index == 1, onTap: () => onChanged(1)),
            _NavItem(icon: Icons.campaign_rounded, label: '공지사항', selected: index == 2, onTap: () => onChanged(2)),
            _NavItem(icon: Icons.settings_rounded, label: '설정', selected: index == 3, onTap: () => onChanged(3)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _gold : _ivory.withOpacity(0.55);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
