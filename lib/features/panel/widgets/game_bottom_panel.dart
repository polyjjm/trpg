import 'package:flutter/material.dart';
import '../models/panel_menu_type.dart';

class GameBottomPanel extends StatefulWidget {
  const GameBottomPanel({super.key});

  @override
  State<GameBottomPanel> createState() => _GameBottomPanelState();
}

class _GameBottomPanelState extends State<GameBottomPanel> {
  PanelMenuType currentMenu = PanelMenuType.menu;

  void changeMenu(PanelMenuType type) {
    setState(() {
      currentMenu = type;
    });
  }

  String getTitle() {
    switch (currentMenu) {
      case PanelMenuType.menu:
        return '메뉴';
      case PanelMenuType.status:
        return '상태';
      case PanelMenuType.equipment:
        return '장비';
      case PanelMenuType.inventory:
        return '인벤토리';
    }
  }

  Widget buildContent() {
    switch (currentMenu) {
      case PanelMenuType.menu:
        return _buildMenuView();
      case PanelMenuType.status:
        return _buildStatusView();
      case PanelMenuType.equipment:
        return _buildEquipmentView();
      case PanelMenuType.inventory:
        return _buildInventoryView();
    }
  }

  Widget _buildMenuView() {
    return Column(
      children: [
        _buildMenuButton(
          title: '상태창',
          onTap: () => changeMenu(PanelMenuType.status),
        ),
        const SizedBox(height: 12),
        _buildMenuButton(
          title: '장비창',
          onTap: () => changeMenu(PanelMenuType.equipment),
        ),
        const SizedBox(height: 12),
        _buildMenuButton(
          title: '인벤토리',
          onTap: () => changeMenu(PanelMenuType.inventory),
        ),
      ],
    );
  }

  Widget _buildMenuButton({
    required String title,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2A2A2A),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white12),
          ),
        ),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusView() {
    return _buildCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('현재 HP: 100 / 100', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 8),
          Text('공격력: 10', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 8),
          Text('방어력: 5', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildEquipmentView() {
    return _buildCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('무기: 녹슨 칼 (12 / 20)', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 10),
          Text('방어구: 낡은 옷 (8 / 15)', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildInventoryView() {
    return _buildCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('붕대 x2', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 8),
          Text('통조림 x1', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 8),
          Text('해열제 x1', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.68,
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (currentMenu != PanelMenuType.menu)
                  IconButton(
                    onPressed: () => changeMenu(PanelMenuType.menu),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                Text(
                  getTitle(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}