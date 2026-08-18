import 'package:flutter/material.dart';

/// 인터랙티브/선형 리더가 공유하는 좌상단 뒤로가기 버튼 — StoryPackDetailPage의
/// _BackButton과 같은 스타일(반투명 검정 원 + 흰 화살표)이라 상세 화면에서
/// 리더로 들어왔다가 나갈 때 톤이 끊기지 않는다.
class ReaderBackButton extends StatelessWidget {
  const ReaderBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, left: 8),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.38)),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
