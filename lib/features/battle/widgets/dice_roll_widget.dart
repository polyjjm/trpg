import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DiceRollWidget extends StatefulWidget {
  final int finalValue;
  final int maxValue;
  final Duration duration;
  final double size;
  final VoidCallback? onCompleted;

  const DiceRollWidget({
    super.key,
    required this.finalValue,
    this.maxValue = 20,
    this.duration = const Duration(milliseconds: 1200),
    this.size = 120,
    this.onCompleted,
  });

  @override
  State<DiceRollWidget> createState() => _DiceRollWidgetState();
}

class _DiceRollWidgetState extends State<DiceRollWidget>
    with TickerProviderStateMixin {
  late final AnimationController _rotateController;
  late final AnimationController _scaleController;
  late final AnimationController _shakeController;

  late final Animation<double> _rotationAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _shakeAnimation;

  final Random _random = Random();

  Timer? _timer;
  int _displayValue = 1;
  bool _isRolling = true;

  @override
  void initState() {
    super.initState();

    _displayValue = _random.nextInt(widget.maxValue) + 1;

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: pi * 2,
    ).animate(CurvedAnimation(
      parent: _rotateController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.08,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));

    _shakeAnimation = Tween<double>(
      begin: -6,
      end: 6,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));

    _startRolling();
  }

  void _startRolling() {
    _rotateController.repeat();
    _scaleController.repeat(reverse: true);
    _shakeController.repeat(reverse: true);

    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      setState(() {
        _displayValue = _random.nextInt(widget.maxValue) + 1;
      });
    });

    Future.delayed(widget.duration, () {
      if (!mounted) return;

      _timer?.cancel();
      _rotateController.stop();
      _scaleController.stop();
      _shakeController.stop();

      setState(() {
        _displayValue = widget.finalValue;
        _isRolling = false;
      });

      widget.onCompleted?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rotateController.dispose();
    _scaleController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Color _borderColor() {
    if (_displayValue == 1) return const Color(0xFF7A7A7A);
    if (_displayValue == widget.maxValue) return const Color(0xFFE2D4BF);
    return const Color(0xFFB8AA95);
  }

  @override
  Widget build(BuildContext context) {
    const Color ivory = Color(0xFFE2D4BF);
    const Color panel = Color(0xCC111111);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _rotateController,
        _scaleController,
        _shakeController,
      ]),
      builder: (context, child) {
        final rotation = _isRolling ? _rotationAnimation.value : 0.0;
        final scale = _isRolling ? _scaleAnimation.value : 1.0;
        final shakeX = _isRolling ? _shakeAnimation.value : 0.0;

        return Transform.translate(
          offset: Offset(shakeX, 0),
          child: Transform.scale(
            scale: scale,
            child: Transform.rotate(
              angle: rotation,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _borderColor(),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$_displayValue',
                  style: const TextStyle(
                    color: ivory,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}