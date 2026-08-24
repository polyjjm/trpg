import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/ui_paths.dart';

/// 홈 상단을 데스크톱 2열로 쪼갤지 판단하는 폭 기준.
const double homeDesktopBreakpoint = 1100;

/// 데스크톱 랭킹 컬럼 폭.
const double homeRankingColumnWidth = 520;

/// 데스크톱 히어로 배너 비율 — 기존보다 세로 공간을 더 줘서 단순 배너가
/// 아니라 실제 메인 피처 영역처럼 보이게 한다.
const double homeDesktopBannerAspect = 2.55;

/// 홈 상단 세 섹션의 배치.
///
/// - 데스크톱: 첫 줄에 히어로 + 랭킹, 둘째 줄에 번들 상품을 전체 폭으로 둔다.
///   번들이 여러 개일 때 가로 카드 캐러셀이 자연스럽게 늘어나고, 한 개만
///   있어도 랭킹 아래 좁은 왼쪽 컬럼에 갇혀 보이지 않는다.
/// - 좁은 폭: 배너 → 랭킹 → 번들 순서로 세로 배치.
class HomeTopSections extends StatelessWidget {
  final Widget banner;
  final Widget ranking;
  final Widget bundles;
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
          Center(child: FractionallySizedBox(widthFactor: 0.94, child: banner)),
          const SizedBox(height: 22),
          ranking,
          const SizedBox(height: 22),
          bundles,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: banner),
            const SizedBox(width: 24),
            SizedBox(width: homeRankingColumnWidth, child: ranking),
          ],
        ),
        const SizedBox(height: 22),
        bundles,
      ],
    );
  }
}

/// TELO 로고 마크.
class ForkingPathLogoMark extends StatelessWidget {
  final double size;

  const ForkingPathLogoMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(UiPaths.logo, width: size, height: size);
  }
}

/// 대문자 'TELO' 워드마크.
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
