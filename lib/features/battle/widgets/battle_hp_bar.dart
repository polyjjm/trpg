import 'package:flutter/material.dart';

class BattleHpBar extends StatefulWidget {
  final String label;
  final int currentHp;
  final int maxHp;

  const BattleHpBar({
    super.key,
    required this.label,
    required this.currentHp,
    required this.maxHp,
  });

  @override
  State<BattleHpBar> createState() => _BattleHpBarState();
}

class _BattleHpBarState extends State<BattleHpBar> {
  late double _oldRatio;

  @override
  void initState() {
    super.initState();
    _oldRatio = _calcRatio(widget.currentHp, widget.maxHp);
  }

  @override
  void didUpdateWidget(covariant BattleHpBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _oldRatio = _calcRatio(oldWidget.currentHp, oldWidget.maxHp);
  }

  double _calcRatio(int hp, int maxHp) {
    if (maxHp <= 0) return 0.0;
    return (hp / maxHp).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final newRatio = _calcRatio(widget.currentHp, widget.maxHp);

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${widget.currentHp} / ${widget.maxHp}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _oldRatio, end: newRatio),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.greenAccent,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}