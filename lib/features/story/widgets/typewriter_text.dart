import 'dart:async';
import 'package:flutter/material.dart';

class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;
  final VoidCallback? onComplete;

  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 40),
    this.onComplete,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _visibleText = '';
  int _index = 0;
  Timer? _timer;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(widget.speed, (timer) {
      if (_index < widget.text.length) {
        setState(() {
          _visibleText += widget.text[_index];
          _index++;
        });
      } else {
        _finishTyping();
      }
    });
  }

  void _finishTyping() {
    _timer?.cancel();
    if (!_isCompleted) {
      _isCompleted = true;
      widget.onComplete?.call();
    }
  }

  // 👉 탭하면 즉시 전체 표시
  void _skipTyping() {
    if (_isCompleted) return;

    _timer?.cancel();

    setState(() {
      _visibleText = widget.text;
      _index = widget.text.length;
    });

    _finishTyping();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _skipTyping,
      child: Text(
        _visibleText,
        style: widget.style ??
            const TextStyle(
              fontSize: 18,
              height: 1.6,
              color: Colors.white,
            ),
      ),
    );
  }
}