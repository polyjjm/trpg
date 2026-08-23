import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/ui_paths.dart';

/// 홈 상단을 2단(배너+번들 | 랭킹)으로 쪼갤지 판단하는 폭 기준.
///
/// story_cover_card.dart의 [storyGridWideBreakpoint](600)와는 목적이 다르다 —
/// 그건 "장르 행을 가로 스크롤 대신 그리드로 그릴지"의 기준이고, 이건
/// "화면이 데스크톱 브라우저만큼 넓은지"의 기준이다.
const double homeDesktopBreakpoint = 1100;

/// 데스크톱 랭킹 컬럼 폭.
const double homeRankingColumnWidth = 560;

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

/// TELO 로고 마크 — "책갈피 T"(주황 가로획 + 앰버 세로 리본, 밑단이 책갈피
/// 모양 V로 파인 시그니처). assets/images/telo_logo.svg(배경 없는 마크)를
/// 그대로 그린다 — 예전엔 이 자리에서 갈라지는 길(forking path) 모양을
/// CustomPainter로 직접 그렸지만, 실제 로고 에셋이 들어오면서 그 스트로크
/// 마크는 폐기했다.
///
/// home_tab.dart 안에 private으로 있던 사본을 옮긴 자리라, 데스크톱 상단
/// 내비게이션도 같은 마크를 써야 하므로 public 위젯으로 꺼내 둔 것이다 —
/// home_tab.dart 쪽 private 사본은 지우고 이걸 쓴다.
class ForkingPathLogoMark extends StatelessWidget {
  final double size;

  const ForkingPathLogoMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(UiPaths.logo, width: size, height: size);
  }
}

/// 대문자 'TELO' 워드마크 — Space Grotesk, 단색(브랜드 색 그라데이션 쓰지
/// 않는다).
class TeloWordmark extends StatelessWidget {
  final double fontSize;

  const TeloWordmark({super.key, this.fontSize = 30});

  @override
  Widget build(BuildContext context) {
    return Text(
      'TELO',
      style: GoogleFonts.spaceGrotesk(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        letterSpacing: fontSize * 0.18,
        color: const Color(0xFFF5EEE2),
      ),
    );
  }
}
