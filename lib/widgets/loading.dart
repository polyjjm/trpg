import 'package:flutter/material.dart';

class Loading extends StatelessWidget {
  final String message;

  const Loading({
    super.key,
    this.message = '이야기를 불러오는 중...',
  });

  @override
  Widget build(BuildContext context) {
    // 배경이 이미 어두운 그라디언트(또는 화면 자체)라, 예전처럼 화면 전체를
    // 한 번 더 검게 덮지 않는다 — 카드 하나만 살짝 띄운다(더 가벼운 톤).
    return Positioned.fill(
      child: Center(
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A14).withOpacity(0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFF0E68C).withOpacity(0.18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFFE2D4BF).withOpacity(0.92),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 8,
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
                  color: const Color(0xFFE2D4BF).withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}