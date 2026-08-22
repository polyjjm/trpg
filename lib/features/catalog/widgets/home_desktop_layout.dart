import 'package:flutter/material.dart';

/// 홈 상단을 2단(배너+번들 | 랭킹)으로 쪼갤지 판단하는 폭 기준.
///
/// story_cover_card.dart의 [storyGridWideBreakpoint](600)와는 목적이 다르다 —
/// 그건 "장르 행을 가로 스크롤 대신 그리드로 그릴지"의 기준이고, 이건
/// "화면이 데스크톱 브라우저만큼 넓은지"의 기준이다.
const double homeDesktopBreakpoint = 1100;

/// 데스크톱 랭킹 컬럼 폭.
const double homeRankingColumnWidth = 400;

/// 데스크톱 히어로 배너 비율 — 모바일(16/6)이나 예전 데스크톱(21/6)보다
/// 납작하다.
///
/// ⚠️ 배너를 max-width로 좁히면 안 된다. 바로 아래 번들 상품 행과 오른쪽
/// 끝이 어긋나서 배너 옆에 검은 빈 칸이 생긴다 — 폭은 컬럼에 맡기고
/// "작아 보이게" 하는 건 비율로만 한다.
const double homeDesktopBannerAspect = 28 / 6;

/// 홈 상단 세 섹션의 배치.
///
/// - 데스크톱: 왼쪽 컬럼에 배너 + 번들 상품, 오른쪽 320px 컬럼에 랭킹.
///   두 컬럼 높이가 서로 비슷하게 떨어져서 어느 쪽에도 빈 공간이 남지 않는다.
/// - 좁은 폭: 기존 순서(배너 → 랭킹 → 번들) 그대로 세로로 쌓는다.
///
/// ⚠️ [banner]는 FractionallySizedBox로 감싸지 않은 "맨 배너"를 넘겨야 한다 —
/// 폭 조절은 이 위젯이 한다.
class HomeTopSections extends StatelessWidget {
  final Widget banner;
  final Widget ranking;
  final Widget bundles;

  /// 호출부(HomeTab)가 이미 계산한 값을 그대로 받는다 — 랭킹 위젯 자체가
  /// 데스크톱/모바일에서 다르기 때문에(컴팩트 목록 vs RankingSection) 이
  /// 위젯이 따로 폭을 재면 두 판단이 어긋날 수 있다.
  final bool isDesktop;

  const HomeTopSections({
    super.key,
    required this.banner,
    required this.ranking,
    required this.bundles,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: FractionallySizedBox(widthFactor: 0.88, child: banner)),
          const SizedBox(height: 24),
          ranking,
          const SizedBox(height: 24),
          bundles,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              banner,
              const SizedBox(height: 26),
              bundles,
            ],
          ),
        ),
        const SizedBox(width: 28),
        SizedBox(width: homeRankingColumnWidth, child: ranking),
      ],
    );
  }
}

/// TELO 로고 마크 — 갈라지는 길(forking path) 아이콘을 코랄→앰버 그라데이션
/// 스트로크로 그린다.
///
/// home_tab.dart 안에 private으로 있던 `_ForkingPathLogoPainter`를 그대로
/// 옮긴 것이다. 데스크톱 상단 내비게이션도 같은 마크를 써야 하므로 public
/// 위젯으로 꺼냈다 — home_tab.dart 쪽 private 사본은 지우고 이걸 쓴다.
///
/// assets/images/telo_logo.svg(주황 사각 타일 안에 흰 분기 글리프)와는 다른
/// 도형이다. 실제 앱이 그리는 건 이 스트로크 마크 쪽이다.
class ForkingPathLogoMark extends StatelessWidget {
  final double size;

  const ForkingPathLogoMark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ForkingPathLogoPainter()),
    );
  }
}

/// 코랄→앰버 그라데이션이 입혀진 'TELO' 워드마크.
class TeloWordmark extends StatelessWidget {
  final double fontSize;

  const TeloWordmark({super.key, this.fontSize = 22});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) =>
          const LinearGradient(colors: [Color(0xFFFF6B4A), Color(0xFFFFB35C)])
              .createShader(bounds),
      child: Text(
        'TELO',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Colors.white, // ShaderMask가 이 색 위에 그라데이션을 입힌다
        ),
      ),
    );
  }
}

class _ForkingPathLogoPainter extends CustomPainter {
  static const Color _coral = Color(0xFFFF6B4A);
  static const Color _amber = Color(0xFFFFB35C);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_coral, _amber],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.19, h * 0.19)
      ..lineTo(w * 0.19, h * 0.47)
      ..cubicTo(w * 0.19, h * 0.62, w * 0.34, h * 0.62, w * 0.34, h * 0.62)
      ..cubicTo(w * 0.5, h * 0.62, w * 0.5, h * 0.47, w * 0.66, h * 0.47)
      ..cubicTo(w * 0.81, h * 0.47, w * 0.81, h * 0.62, w * 0.81, h * 0.62)
      ..moveTo(w * 0.34, h * 0.62)
      ..lineTo(w * 0.34, h * 0.84)
      ..moveTo(w * 0.66, h * 0.47)
      ..lineTo(w * 0.66, h * 0.28);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..shader = const LinearGradient(colors: [_coral, _amber]).createShader(rect);
    canvas.drawCircle(Offset(w * 0.19, h * 0.14), size.width * 0.08, dotPaint);
    canvas.drawCircle(Offset(w * 0.66, h * 0.22), size.width * 0.08, dotPaint);
    canvas.drawCircle(Offset(w * 0.34, h * 0.9), size.width * 0.08, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
