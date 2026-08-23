import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/asset_paths.dart';
import '../models/story_pack.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 홈 탭 최상단 — 책장 삽화(assets/images/bookshelf_bg.png) 배경 위에
/// "Telo" 워드마크 + 검색 아이콘, 그 아래 이어읽기 카드를 얹은 "떠 있는"
/// 둥근 카드. 화면 가장자리에 꽉 채우지 않고 나머지 콘텐츠(장르 행, 랭킹
/// 등)와 같은 좌우 여백([_horizontalMargin])을 두고, 위아래로도 페이지의
/// 평소 어두운 배경이 살짝 보이도록 둥글린 모서리로 감싼다 — 이 배경 삽화 +
/// 그라디언트만 프로젝트의 "플랫 컬러만 쓴다" 관례의 예외다(장식용 배경
/// 하나로 범위를 좁혀 뒀다).
///
/// 실제 삽화 파일은 나중에 교체될 래스터(PNG) placeholder다 — 지금은 책
/// 등이 늘어선 모양만 흉내 낸 단순한 색 블록 이미지를
/// assets/images/bookshelf_bg.png에 뒀다. 원래는 손으로 그린 SVG였는데,
/// 실사용 브라우저 한 대에서 이 SVG가 헤더 전체를 완전 검정으로 만드는
/// 버그가 재현됐다(하드웨어 가속 정상, 서비스워커 없음, 시크릿 모드에서도
/// 동일 — 확장 프로그램·캐시 문제는 배제됨). Claude의 격리된 테스트
/// 환경(dev 서버/프로덕션 빌드/강제 소프트웨어 GPU 렌더링)에서는 재현되지
/// 않았지만, 다른 원인들을 소거법으로 배제한 뒤 남은 가장 유력한 용의자가
/// SvgPicture.asset이라 래스터로 교체했다 — 그 SVG 렌더 경로
/// (flutter_svg/vector_graphics) 자체를 없애는 게 목적이라, 실제 삽화도
/// 나중에 SVG가 아니라 PNG/WebP 같은 래스터로 받는 걸 권장한다.
///
/// SVG→PNG 교체 후에도 실제 피해 기기에서 헤더가 여전히 완전 검정이라,
/// 구조적 용의자(RepaintBoundary, ClipRRect, 고정 크기 SizedBox, 이 위젯의
/// 최상위 SafeArea 자체까지)를 하나씩 걷어내며 재현을 시도했지만 전부
/// 원인이 아니었다(각각 되돌림 — 이 파일은 항상 정상 구조로 남아 있다).
/// LibraryHeader 서브트리 내부는 이제 전부 배제됐다는 뜻이라, 현재는 이
/// 위젯 밖 — main.dart가 CatalogShellPage로 넘어갈 때 쓰는
/// Navigator.pushReplacement(MaterialPageRoute(...))의 기본 페이지 전환
/// 애니메이션(FadeTransition/SlideTransition 등, Opacity 기반)이 원래
/// RepaintBoundary 주석이 지목했던 "라우트 전환 직후 첫 프레임" 시나리오에
/// 더 가까운 후보라 그쪽을 보는 중이다.
class LibraryHeader extends StatelessWidget {
  static const double height = 172;
  static const double _horizontalMargin = 22;

  final int cashBalance;
  final VoidCallback onSearchTap;
  final VoidCallback onCashTap;
  final bool showAuthorModeLink;
  final VoidCallback? onAuthorModeTap;

  /// 가장 최근에 읽던 팩(없으면 null — 카드 자체를 숨긴다).
  final StoryPack? continueReadingPack;
  final int continueReadingVisitedCount;
  final VoidCallback? onContinueReadingTap;

  const LibraryHeader({
    super.key,
    required this.cashBalance,
    required this.onSearchTap,
    required this.onCashTap,
    required this.showAuthorModeLink,
    required this.onAuthorModeTap,
    required this.continueReadingPack,
    required this.continueReadingVisitedCount,
    required this.onContinueReadingTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_horizontalMargin, 12, _horizontalMargin, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: BoxConstraints.tightFor(height: height, width: double.infinity),
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // [진단: 순색 채우기 테스트] 실제 프로덕션 코드 경로 그대로,
                  // 이 헤더 슬롯이 지금 상태로도 아무 색이든 보여줄 수 있는지
                  // 확인하려고 배경을 임시로 밝은 노랑 하나로 채웠다 — 이미지/
                  // 그라디언트 레이어를 Stack에서 완전히 뺐다(원래 코드는
                  // 바로 아래 주석 처리). 노랑이 보이면 이 슬롯 자체는
                  // 정상이고 원인은 Image.asset/그라디언트 레이어 쪽이라는
                  // 뜻, 그래도 검정이면 이 슬롯에 그리기 자체가 전혀 안 되고
                  // 있다는 뜻(레이어 합성이 아니라 페인트/래스터화 단계
                  // 자체의 문제).
                  const ColoredBox(color: Color(0xFFFFFF00)),
                  // const ColoredBox(color: Color(0xFF4A3221)),
                  // Image.asset(
                  //   UiPaths.bookshelfBackground,
                  //   fit: BoxFit.cover,
                  //   alignment: Alignment.topCenter,
                  // ),
                  // const DecoratedBox(
                  //   decoration: BoxDecoration(
                  //     gradient: LinearGradient(
                  //       begin: Alignment.topCenter,
                  //       end: Alignment.bottomCenter,
                  //       colors: [Colors.transparent, Color(0xBF000000)],
                  //       stops: [0.3, 1.0],
                  //     ),
                  //   ),
                  // ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _TopRow(
                          cashBalance: cashBalance,
                          onSearchTap: onSearchTap,
                          onCashTap: onCashTap,
                          showAuthorModeLink: showAuthorModeLink,
                          onAuthorModeTap: onAuthorModeTap,
                        ),
                        if (continueReadingPack != null)
                          _ContinueReadingCard(
                            pack: continueReadingPack!,
                            visitedCount: continueReadingVisitedCount,
                            onTap: onContinueReadingTap,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  final int cashBalance;
  final VoidCallback onSearchTap;
  final VoidCallback onCashTap;
  final bool showAuthorModeLink;
  final VoidCallback? onAuthorModeTap;

  const _TopRow({
    required this.cashBalance,
    required this.onSearchTap,
    required this.onCashTap,
    required this.showAuthorModeLink,
    required this.onAuthorModeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(UiPaths.logo, width: 24, height: 24),
            const SizedBox(width: 8),
            // 배경 삽화 위에 얹히는 워드마크라 그림자는 유지한다(가독성용) —
            // 나머지 UI의 TeloWordmark(home_desktop_layout.dart)는 어두운
            // 단색 배경 위라 그림자가 없다.
            Text(
              'TELO',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: 22 * 0.18,
                color: _ivory,
                shadows: const [
                  Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 4),
                ],
              ),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onSearchTap,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.32),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: const Icon(Icons.search_rounded, color: _ivory, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            _CashChip(cashBalance: cashBalance, onTap: onCashTap),
          ],
        ),
        if (showAuthorModeLink) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: onAuthorModeTap,
            child: Text(
              '작가 모드로 전환',
              style: TextStyle(fontSize: 11, color: _ivory.withOpacity(0.55)),
            ),
          ),
        ],
      ],
    );
  }
}

class _CashChip extends StatelessWidget {
  final int cashBalance;
  final VoidCallback onTap;

  const _CashChip({required this.cashBalance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.32),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withOpacity(0.40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on_rounded, color: _gold, size: 16),
            const SizedBox(width: 4),
            Text(
              '$cashBalance',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(14)),
              child: const Text(
                '충전',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 헤더 하단에 얹는 "이어읽기" 카드 — 반투명 다크 패널 위에 표지 썸네일 +
/// 제목 + 진행 상황.
class _ContinueReadingCard extends StatelessWidget {
  final StoryPack pack;
  final int visitedCount;
  final VoidCallback? onTap;

  const _ContinueReadingCard({
    required this.pack,
    required this.visitedCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = pack.coverImageUrl;
    final progressLabel = pack.publishedNodeCount > 0
        ? '$visitedCount / ${pack.publishedNodeCount}화 읽는 중'
        : '이어읽기';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.48),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 58,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _CoverFallback(),
                      )
                    : const _CoverFallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '이어읽기',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _gold.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pack.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ivory),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    progressLabel,
                    style: TextStyle(fontSize: 11.5, color: _ivory.withOpacity(0.65)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _ivory.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFFE2703A)),
      child: Icon(Icons.menu_book_rounded, color: Colors.white70, size: 20),
    );
  }
}
