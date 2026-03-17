import 'package:flutter/material.dart';

class Loading extends StatelessWidget {
  final String message;

  const Loading({
    super.key,
    this.message = '세상을 불러오는 중...',
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.58),
        child: Center(
          child: Container(
            width: 260,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.60),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.88),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 10,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white.withOpacity(0.10),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFF0E68C),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '잠시만 기다려 주세요',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.55),
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