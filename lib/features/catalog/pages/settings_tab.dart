import 'package:flutter/material.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 하단 탭의 "설정" — 지금은 자리만 잡아둔 구조적 placeholder다(관리자
/// 대시보드의 신고 처리/결제 항목과 같은 취급). 실제 알림/계정 관리, 로그아웃
/// 로직은 아직 없다.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('아직 준비 중인 기능이에요.')),
    );
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
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ivory),
              ),
              const SizedBox(height: 20),
              _SettingsRow(icon: Icons.notifications_outlined, label: '알림', onTap: () => _showComingSoon(context)),
              _SettingsRow(icon: Icons.person_outline_rounded, label: '계정', onTap: () => _showComingSoon(context)),
              _SettingsRow(icon: Icons.logout_rounded, label: '로그아웃', onTap: () => _showComingSoon(context)),
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

  const _SettingsRow({required this.icon, required this.label, required this.onTap});

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
              child: Text(label, style: const TextStyle(fontSize: 14.5, color: _ivory)),
            ),
            Icon(Icons.chevron_right_rounded, color: _ivory.withOpacity(0.35), size: 20),
          ],
        ),
      ),
    );
  }
}
