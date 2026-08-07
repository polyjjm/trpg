import 'dart:math';

import 'package:flutter/material.dart';
import '../models/battle_card.dart';

class BattleCardWidget extends StatefulWidget {
  final BattleCard card;
  final bool isFlipped;
  final VoidCallback? onTap;
  final bool dimmed;
  final double width;

  const BattleCardWidget({
    super.key,
    required this.card,
    required this.isFlipped,
    required this.width,
    this.onTap,
    this.dimmed = false,
  });

  @override
  State<BattleCardWidget> createState() => _BattleCardWidgetState();
}

class _BattleCardWidgetState extends State<BattleCardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.isFlipped ? 1 : 0,
    );

    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(covariant BattleCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isFlipped != oldWidget.isFlipped) {
      if (widget.isFlipped) {
        _flipController.forward();
      } else {
        _flipController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 1.68;

    return GestureDetector(
      onTap: widget.onTap,
      child: Opacity(
        opacity: widget.dimmed ? 0.3 : 1.0,
        child: SizedBox(
          width: widget.width,
          height: height,
          child: AnimatedBuilder(
            animation: _flipAnimation,
            builder: (context, child) {
              // 0~pi 회전. 절반을 넘어가면 뒷면 대신 앞면 이미지를 보여준다.
              final angle = _flipAnimation.value * pi;
              final showFront = angle > pi / 2;

              Widget face = Image.asset(
                showFront ? widget.card.frontImagePath : widget.card.backImagePath,
                fit: BoxFit.contain,
              );

              if (showFront) {
                // 절반을 넘어간 뒤에는 이미지가 좌우 반전되어 보이므로 다시 뒤집어 바로잡는다.
                face = Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi),
                  child: face,
                );
              }

              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(angle),
                child: face,
              );
            },
          ),
        ),
      ),
    );
  }
}
