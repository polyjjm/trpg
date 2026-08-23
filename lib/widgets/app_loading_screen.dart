import 'package:flutter/material.dart';

import 'loading.dart';

/// 앱 부트스트랩(Firebase/인증 확인)부터 홈 탭의 첫 스토리팩 데이터가 도착할
/// 때까지, 화면 전체를 덮는 로딩 화면 — 배경/카드/진행 바가 어디서 쓰이든
/// 완전히 같다(web/index.html의 #app-loading, 로그인 화면의 진행 오버레이).
///
/// [MainPage]가 이 위젯을 프로세스 시작부터 실제 콘텐츠가 준비될 때까지
/// 단 하나의 인스턴스로 계속 마운트해 둔다(라우트 전환 없이 Stack 오버레이로
/// 얹고 opacity만 내린다) — 두 단계를 각자 새 인스턴스로 그리면
/// LinearProgressIndicator의 내부 애니메이션이 매번 처음부터 다시 시작돼
/// 눈에 띄는 깜빡임처럼 보이기 때문에, 인스턴스 자체를 재사용해 그 문제를
/// 원천적으로 없앤다.
class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF241C10),
                  Color(0xFF16110A),
                  Colors.black,
                ],
                stops: [0.0, 0.46, 1.0],
              ),
            ),
          ),
        ),
        Loading(message: '이야기를 불러오는 중...'),
      ],
    );
  }
}
