import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 앱 어디서든 같은 모양으로 뜨는 로딩 카드 — 로고 마크 · 문구 · 진행 바.
/// web/index.html의 초기 스플래시가 이 카드와 같은 값으로 그려져 있어서,
/// 엔진이 뜨는 순간에도 화면이 바뀐 것처럼 보이지 않는다.
class Loading extends StatelessWidget {
  final String message;

  const Loading({
    super.key,
    this.message = '이야기를 불러오는 중...',
  });

  @override
  Widget build(BuildContext context) {
    // 배경이 이미 어두운 그라디언트(또는 화면 자체)라, 화면 전체를 한 번 더
    // 검게 덮지 않는다 — 카드 하나만 살짝 띄운다.
    return Positioned.fill(
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A14).withOpacity(0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFF2B33D).withOpacity(0.20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/images/telo_logo.svg',
                width: 56,
                height: 56,
              ),
              const SizedBox(height: 20),
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
