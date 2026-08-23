import 'package:flutter/material.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 하단 탭의 "설정" — 지금은 모바일 폭에서만 쓰인다. 데스크톱은 같은
/// 세 항목(알림/계정/로그아웃)을 상단 바 오른쪽의 아바타 드롭다운
/// (catalog_desktop_nav_bar.dart의 `_AccountAvatarMenu`, 로그아웃은 실제로
/// 동작한다)으로 옮겼고, 그 화면에는 이 탭으로 가는 버튼 자체가 없다 — 이
/// 위젯은 catalog_shell_page.dart의 IndexedStack에서 모바일 하단 탭바가
/// 여전히 이 칸(index 3)을 쓰기 때문에 남아 있을 뿐이다. 알림/계정은
/// 아직 자리만 잡아둔 placeholder고, 로그아웃도 여기서는 스텁 그대로다
/// (모바일 쪽 실제 로그아웃 구현은 이 작업 범위 밖).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('아직 준비 중인 기능이에요.')));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '설정',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                ),
              ),
              const SizedBox(height: 20),
              _SettingsRow(
                icon: Icons.notifications_outlined,
                label: '알림',
                onTap: () => _showComingSoon(context),
              ),
              _SettingsRow(
                icon: Icons.person_outline_rounded,
                label: '계정',
                onTap: () => _showComingSoon(context),
              ),
              _SettingsRow(
                icon: Icons.logout_rounded,
                label: '로그아웃',
                onTap: () => _showComingSoon(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: _ivory.withOpacity(0.85), size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14.5, color: _ivory),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: _ivory.withOpacity(0.35),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
