import 'package:flutter/material.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 스토리/조우 화면에서 공용으로 쓰는 사이드바(Drawer).
/// 이야기 진행 자체와는 무관한 내비게이션 액션(재시작·설정·로그아웃)을 모아둔다.
class AppDrawer extends StatelessWidget {
  final VoidCallback onLibrary;
  final VoidCallback onRestart;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;

  const AppDrawer({
    super.key,
    required this.onLibrary,
    required this.onRestart,
    required this.onSettings,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF151515),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Text(
                'Telo',
                style: TextStyle(
                  color: _ivory,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 8),
            _buildItem(
              icon: Icons.collections_bookmark_rounded,
              label: '라이브러리로',
              onTap: () {
                Navigator.pop(context);
                onLibrary();
              },
            ),
            _buildItem(
              icon: Icons.restart_alt_rounded,
              label: '처음부터 다시 시작',
              onTap: () {
                Navigator.pop(context);
                onRestart();
              },
            ),
            _buildItem(
              icon: Icons.settings_outlined,
              label: '설정',
              onTap: () {
                Navigator.pop(context);
                onSettings();
              },
            ),
            _buildItem(
              icon: Icons.logout_rounded,
              label: '로그아웃',
              onTap: () {
                Navigator.pop(context);
                onSignOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: _ivory.withOpacity(0.85)),
      title: Text(
        label,
        style: TextStyle(
          color: _ivory.withOpacity(0.92),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}
