import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DiceJudgeResult {
  final int firstRoll;
  final int? secondRoll;
  final int total;
  final bool doubleChanceTriggered;

  const DiceJudgeResult({
    required this.firstRoll,
    required this.total,
    this.secondRoll,
    this.doubleChanceTriggered = false,
  });
}

class DiceJudgeModal extends StatefulWidget {
  final String actionLabel;
  final bool enableDoubleChance;
  final FutureOr<bool> Function(int firstRoll)? shouldTriggerDoubleChance;

  const DiceJudgeModal({
    super.key,
    required this.actionLabel,
    this.enableDoubleChance = true,
    this.shouldTriggerDoubleChance,
  });

  @override
  State<DiceJudgeModal> createState() => _DiceJudgeModalState();
}

class _DiceJudgeModalState extends State<DiceJudgeModal>
    with TickerProviderStateMixin {
  final Random _random = Random();

  late final AnimationController _overlayController;
  late final AnimationController _dropController;
  late final AnimationController _bounceController;

  late final Animation<double> _overlayOpacity;
  late final Animation<Offset> _dropAnimation;
  late final Animation<double> _rotationAnimation;
  late final Animation<double> _bounceAnimation;

  int _displayValue = 1;
  String _message = '주사위를 던지는 중...';

  int? _firstRoll;
  int? _secondRoll;
  bool _doubleChanceTriggered = false;
  bool _isRolling = true;

  Timer? _rollingTimer;

  @override
  void initState() {
    super.initState();

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _overlayOpacity = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOut,
    );

    _dropAnimation = Tween<Offset>(
      begin: const Offset(0, -1.8),
      end: const Offset(0, 0),
    ).animate(
      CurvedAnimation(
        parent: _dropController,
        curve: Curves.easeInCubic,
      ),
    );

    _rotationAnimation = Tween<double>(
      begin: -0.35,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _dropController,
        curve: Curves.easeOutCubic,
      ),
    );

    _bounceAnimation = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeOut,
      ),
    );

    _startFlow();
  }

  Future<void> _startFlow() async {
    await _overlayController.forward();

    final firstRoll = await _playSingleRoll(
      rollingMessage: '${widget.actionLabel} 판정 중...',
      fixedMessage: '주사위 결과 확정',
    );

    _firstRoll = firstRoll;

    bool triggerDouble = false;
    if (widget.enableDoubleChance) {
      if (widget.shouldTriggerDoubleChance != null) {
        triggerDouble = await widget.shouldTriggerDoubleChance!(firstRoll);
      } else {
        triggerDouble = firstRoll == 6;
      }
    }

    if (triggerDouble && mounted) {
      _doubleChanceTriggered = true;
      setState(() {
        _message = '더블찬스 발동. 한 번 더 던진다.';
      });

      await Future.delayed(const Duration(milliseconds: 700));

      final secondRoll = await _playSingleRoll(
        rollingMessage: '추가 주사위 판정 중...',
        fixedMessage: '추가 주사위 확정',
      );

      _secondRoll = secondRoll;
    }

    if (!mounted) return;

    final total = (_firstRoll ?? 0) + (_secondRoll ?? 0);

    setState(() {
      _isRolling = false;
      if (_doubleChanceTriggered) {
        _message =
        '1차 ${_firstRoll ?? 0} + 2차 ${_secondRoll ?? 0} = 총합 $total';
      } else {
        _message = '최종 결과: $total';
      }
    });

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    Navigator.pop(
      context,
      DiceJudgeResult(
        firstRoll: _firstRoll ?? 0,
        secondRoll: _secondRoll,
        total: total,
        doubleChanceTriggered: _doubleChanceTriggered,
      ),
    );
  }

  Future<int> _playSingleRoll({
    required String rollingMessage,
    required String fixedMessage,
  }) async {
    _rollingTimer?.cancel();

    setState(() {
      _message = rollingMessage;
      _displayValue = _random.nextInt(6) + 1;
    });

    _dropController.reset();
    _bounceController.reset();

    _rollingTimer = Timer.periodic(const Duration(milliseconds: 70), (timer) {
      if (!mounted) return;
      setState(() {
        _displayValue = _random.nextInt(6) + 1;
      });
    });

    await _dropController.forward();
    _rollingTimer?.cancel();

    final fixedValue = _random.nextInt(6) + 1;

    setState(() {
      _displayValue = fixedValue;
      _message = fixedMessage;
    });

    await _bounceController.forward();
    await _bounceController.reverse();

    return fixedValue;
  }

  @override
  void dispose() {
    _rollingTimer?.cancel();
    _overlayController.dispose();
    _dropController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ivory = Color(0xFFE2D4BF);

    return FadeTransition(
      opacity: _overlayOpacity,
      child: Material(
        color: Colors.black.withOpacity(0.72),
        child: Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xEE111111),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF6F655A),
                width: 1.2,
              ),
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
                Text(
                  '${widget.actionLabel} 판정',
                  style: const TextStyle(
                    color: ivory,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),

                SizedBox(
                  height: 210,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        bottom: 18,
                        child: Container(
                          width: 92,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _dropController,
                          _bounceController,
                        ]),
                        builder: (context, child) {
                          final scale = _isRolling ? 1.0 : _bounceAnimation.value;
                          return SlideTransition(
                            position: _dropAnimation,
                            child: Transform.rotate(
                              angle: _rotationAnimation.value,
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: 92,
                          height: 92,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFB7AA96),
                              width: 2,
                            ),
                          ),
                          child: Text(
                            '$_displayValue',
                            style: const TextStyle(
                              color: ivory,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xAA0E0E0E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF564E45),
                    ),
                  ),
                  child: Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ivory,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}