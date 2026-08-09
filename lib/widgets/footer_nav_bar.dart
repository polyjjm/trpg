import 'package:flutter/material.dart';

import '../core/audio/audio_service.dart';
import '../core/audio/system_sfx.dart';
import '../features/panel/models/panel_menu_type.dart';
import '../features/panel/widgets/game_bottom_panel.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 스토리/조우 화면 하단에 항상 떠 있는 푸터 내비게이션 바.
/// 아이템/상태를 누르면 GameBottomPanel의 해당 뷰를 시트로 띄우고(내용은 그대로 재사용),
/// 홈을 누르면 열려 있는 시트를 닫는다.
class FooterNavBar extends StatefulWidget {
  const FooterNavBar({super.key});

  @override
  State<FooterNavBar> createState() => _FooterNavBarState();
}

class _FooterNavBarState extends State<FooterNavBar> {
  bool _panelOpen = false;

  void _openPanel(PanelMenuType menu) {
    if (_panelOpen) return;

    setState(() {
      _panelOpen = true;
    });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GameBottomPanel(initialMenu: menu),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _panelOpen = false;
      });
    });
  }

  void _goHome() {
    if (!_panelOpen) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.80),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildFooterItem(
              icon: Icons.home_rounded,
              label: '홈',
              onTap: _goHome,
            ),
            _buildFooterItem(
              icon: Icons.inventory_2_rounded,
              label: '아이템',
              onTap: () => _openPanel(PanelMenuType.inventory),
            ),
            _buildFooterItem(
              icon: Icons.favorite_rounded,
              label: '상태',
              onTap: () => _openPanel(PanelMenuType.status),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        AudioService.instance.playSfx(SystemSfx.buttonClick.assetPath);
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _ivory.withOpacity(0.88), size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: _ivory.withOpacity(0.82),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
