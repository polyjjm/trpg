import 'package:flutter/material.dart';

/// 동전 던지기 결과를 보여주는 원형 표시자.
/// 던지는 동안 headsShown이 빠르게 바뀌면 AnimatedSwitcher가 앞/뒤 라벨을 전환하며
/// 뒤집히는 듯한 효과를 낸다.
class CoinFlipDisplay extends StatelessWidget {
  final bool isFlipping;
  final bool headsShown;

  const CoinFlipDisplay({
    super.key,
    required this.isFlipping,
    required this.headsShown,
  });

  @override
  Widget build(BuildContext context) {
    final label = headsShown ? '앞' : '뒤';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Container(
        key: ValueKey(label),
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFF2D98B), Color(0xFFC9A24B)],
          ),
          border: Border.all(
            color: isFlipping ? Colors.white38 : Colors.white70,
            width: 3,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Color(0xFF3B2A12),
          ),
        ),
      ),
    );
  }
}
