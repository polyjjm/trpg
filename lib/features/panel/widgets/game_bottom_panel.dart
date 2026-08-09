import 'package:flutter/material.dart';
import '../../../core/constants/asset_paths.dart';
import '../../../core/state/game_state.dart';
import '../../../core/state/game_state_scope.dart';
import '../../battle/inventory/data/item_catalog.dart';
import '../../battle/inventory/models/item_effect_type.dart';
import '../../battle/inventory/models/item_model.dart';
import '../models/panel_menu_type.dart';

const Color _panelIvory = Color(0xFFE2D4BF);
const Color _hpColor = Color(0xFFE0524B);
const Color _attackColor = Color(0xFFF2A93B);
const Color _defenseColor = Color(0xFF6C93B0);
const Color _buffColor = Color(0xFF6FB08A);
const Color _escapeColor = Color(0xFF9B7FC7);

IconData _iconForEffect(ItemEffectType effectType) {
  switch (effectType) {
    case ItemEffectType.heal:
      return Icons.healing_rounded;
    case ItemEffectType.damage:
      return Icons.local_fire_department_rounded;
    case ItemEffectType.buff:
      return Icons.shield_moon_rounded;
    case ItemEffectType.escapeBoost:
      return Icons.directions_run_rounded;
  }
}

Color _colorForEffect(ItemEffectType effectType) {
  switch (effectType) {
    case ItemEffectType.heal:
      return _hpColor;
    case ItemEffectType.damage:
      return _attackColor;
    case ItemEffectType.buff:
      return _buffColor;
    case ItemEffectType.escapeBoost:
      return _escapeColor;
  }
}

class GameBottomPanel extends StatefulWidget {
  final PanelMenuType initialMenu;

  const GameBottomPanel({super.key, this.initialMenu = PanelMenuType.menu});

  @override
  State<GameBottomPanel> createState() => _GameBottomPanelState();
}

class _GameBottomPanelState extends State<GameBottomPanel> {
  late PanelMenuType currentMenu = widget.initialMenu;

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildMenuCard(
            label: '상태',
            imagePath: UiPaths.statusIcon,
            onTap: () => changeMenu(PanelMenuType.status),
          ),
          _buildMenuCard(
            label: '장비',
            imagePath: UiPaths.equipmentIcon,
            onTap: () => changeMenu(PanelMenuType.equipment),
          ),
          _buildMenuCard(
            label: '인벤토리',
            imagePath: UiPaths.inventoryIcon,
            onTap: () => changeMenu(PanelMenuType.inventory),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard({
    required String label,
    required String imagePath,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🔥 핵심: 아이콘 크게
            Image.asset(
              imagePath,
              width: 110,
              height: 110,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 10),

            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusView() {
    final gameState = GameStateScope.of(context);
    final attack = gameState.playerAttack;
    final defense = gameState.playerDefense;
    final hearts = gameState.hearts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatHeartsCard(hearts: hearts, maxHearts: GameState.maxHearts),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatMiniCard(
                icon: Icons.bolt_rounded,
                color: _attackColor,
                label: '공격력',
                value: '$attack',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatMiniCard(
                icon: Icons.shield_rounded,
                color: _defenseColor,
                label: '방어력',
                value: '$defense',
              ),
            ),
          ],
        ),
      ],
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
    final gameState = GameStateScope.of(context);

    final items = <_InventoryItemPreview?>[];
    gameState.inventory.forEach((itemId, count) {
      final ItemModel? item = itemCatalog[itemId];
      if (item == null || count <= 0) return;

      items.add(
        _InventoryItemPreview(
          icon: _iconForEffect(item.effectType),
          color: _colorForEffect(item.effectType),
          name: item.name,
          description: item.description,
          count: count,
        ),
      );
    });

    const slotCount = 12;
    while (items.length < slotCount) {
      items.add(null);
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return _InventorySlotTile(item: items[index]);
      },
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

class _StatIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _StatIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _StatHeartsCard extends StatelessWidget {
  final int hearts;
  final int maxHearts;

  const _StatHeartsCard({required this.hearts, required this.maxHearts});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hpColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hpColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const _StatIconBadge(icon: Icons.favorite_rounded, color: _hpColor),
          const SizedBox(width: 12),
          const Text(
            '하트',
            style: TextStyle(
              color: _panelIvory,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          for (var i = 0; i < maxHearts; i++)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                i < hearts ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _hpColor,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatMiniCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatMiniCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          _StatIconBadge(icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _panelIvory.withOpacity(0.75),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _panelIvory,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryItemPreview {
  final IconData icon;
  final Color color;
  final String name;
  final String description;
  final int count;

  const _InventoryItemPreview({
    required this.icon,
    required this.color,
    required this.name,
    required this.description,
    required this.count,
  });
}

class _InventorySlotTile extends StatelessWidget {
  final _InventoryItemPreview? item;

  const _InventorySlotTile({this.item});

  void _showDetail(BuildContext context) {
    final item = this.item;
    if (item == null) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => _ItemDetailDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = this.item;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: item != null
              ? item.color.withOpacity(0.10)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item != null
                ? item.color.withOpacity(0.45)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: item == null
            ? null
            : Stack(
                children: [
                  Center(
                    child: Icon(item.icon, color: item.color, size: 28),
                  ),
                  if (item.count > 1)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'x${item.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ItemDetailDialog extends StatelessWidget {
  final _InventoryItemPreview item;

  const _ItemDetailDialog({required this.item});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xEE111111),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF6F655A), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: item.color.withOpacity(0.5)),
              ),
              child: Icon(item.icon, color: item.color, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              item.name,
              style: const TextStyle(
                color: _panelIvory,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _panelIvory.withOpacity(0.78),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                '닫기',
                style: TextStyle(color: _panelIvory),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
