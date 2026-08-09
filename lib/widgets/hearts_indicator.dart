import 'package:flutter/material.dart';

/// 화면 한 구석에 작게 띄우는 하트 표시 위젯.
/// 스토리 화면과 텍스트 조우 화면에서 공용으로 사용한다.
class HeartsIndicator extends StatelessWidget {
  final int hearts;
  final int maxHearts;

  const HeartsIndicator({
    super.key,
    required this.hearts,
    required this.maxHearts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < maxHearts; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
              child: Icon(
                i < hearts
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: const Color(0xFFE0524B),
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}
