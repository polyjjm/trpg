import 'package:flutter/material.dart';

/// 각 장르 행 아래 놓는 3px짜리 웜톤 가로 바 — 헤더의 책장 삽화가 세운
/// "서가" 시각 테마를 장르 행 사이에도 은은하게 이어준다.
class ShelfLedgeDivider extends StatelessWidget {
  const ShelfLedgeDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6B4A2E).withOpacity(0.0),
            const Color(0xFF6B4A2E).withOpacity(0.55),
            const Color(0xFF6B4A2E).withOpacity(0.0),
          ],
        ),
      ),
    );
  }
}
