import 'package:flutter/material.dart';

import '../../../core/state/reading_progress.dart';
import '../models/genre_style.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';
import 'type_badge.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 홈 탭의 넓은 화면 장르 그리드와 내 서재 그리드가 공유하는 배치 —
/// crossAxisCount만 호출부에서 고르고 나머지(간격, childAspectRatio)는
/// 항상 같다. 두 화면이 각자 숫자를 따로 들고 있으면 나중에 한쪽만
/// 바뀌어 또 어긋날 수 있어서, 아예 이 함수 하나로 못 박아 둔다.
SliverGridDelegateWithFixedCrossAxisCount storyCoverGridDelegate({
  required int crossAxisCount,
}) {
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: crossAxisCount,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 3 / 4,
  );
}

/// 그리드 crossAxisCount를 고를 때 쓰는 폭 기준(600px) — 홈 탭 레이아웃
/// 분기(모바일/데스크톱)와 같은 값을 내 서재도 그대로 쓴다.
const double storyGridWideBreakpoint = 600;

/// 이 프로젝트 어디서든 이야기 팩 표지를 보여주는 유일한 카드 위젯 —
/// 홈 탭의 장르별 진열 행/그리드, 검색 결과 그리드, 내 서재 그리드가 전부
/// 이 위젯 하나를 공유한다. 예전엔 홈이 StoryPackCard를, 내 서재가 별도의
/// _LibraryGridCard를 따로 구현해서 둘이 childAspectRatio를 맞춰 놓아도
/// 내부 구성(텍스트 줄 수 등)이 달라 표지 비율이 미묘하게 어긋났다 — 위젯
/// 자체를 하나로 합쳐서 그럴 일이 구조적으로 없게 한다.
///
/// 작가가 표지를 안 골랐거나 로드에 실패하면 브랜드 그라디언트 위에 장르
/// 아이콘을 얹은 placeholder로 대체한다.
class StoryCoverCard extends StatelessWidget {
  final StoryPack pack;

  /// 장르별 진열 행처럼 행 제목 자체가 이미 장르를 말해주는 자리, 또는 내
  /// 서재처럼 "내가 가진 것"만 모여 장르 구분이 덜 중요한 자리에서는 꺼
  /// 둔다 — 검색 결과 그리드는 장르가 뒤섞여 나오니 기본값 true.
  final bool showGenreTag;

  /// 제목 아래 가격/형식 줄 — 홈 탭(장르 행·검색 결과)에서는 보여주고,
  /// 내 서재에서는 끈다(가격은 항상 "무료"라 반복 정보고, 그 자리를 진행률
  /// 바/완료 배지가 대신 쓴다).
  final bool showPriceRow;

  /// 내 서재 전용 — 있으면 완료 체크 배지(오른쪽 위) 또는 진행률 바(표지
  /// 하단)를 표지 위에 얹는다. 홈 탭 카드들은 항상 null.
  final ReadingProgress? progress;

  const StoryCoverCard({
    super.key,
    required this.pack,
    this.showGenreTag = true,
    this.showPriceRow = true,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final genreStyle = genreStyleFor(pack.primaryGenre);
    final coverImageUrl = pack.coverImageUrl;
    final completed = progress?.completed ?? false;
    final progressFraction = (progress != null && pack.publishedNodeCount > 0)
        ? (progress!.visitedNodeCount / pack.publishedNodeCount).clamp(0.0, 1.0)
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverImageUrl != null && coverImageUrl.isNotEmpty)
                    Image.network(
                      coverImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _CoverPlaceholder(genreStyle: genreStyle),
                    )
                  else
                    _CoverPlaceholder(genreStyle: genreStyle),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: TypeBadge(format: pack.format, size: 24),
                  ),
                  if (showGenreTag)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _GenreTag(style: genreStyle),
                    ),
                  if (completed)
                    const Positioned(right: 8, top: 8, child: _CompletedBadge()),
                  if (!completed && progressFraction != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ProgressBar(fraction: progressFraction),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pack.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ivory,
            ),
          ),
          if (showPriceRow) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pack.isFree ? '무료' : '₩${pack.price}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.62)),
                  ),
                ),
                Text(
                  pack.format.label,
                  style: TextStyle(fontSize: 10.5, color: _ivory.withOpacity(0.40), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 표지 이미지가 없거나(coverImageUrl == null) 로드에 실패했을 때 쓰는
/// fallback — 브랜드 그라디언트 위에 장르 아이콘.
class _CoverPlaceholder extends StatelessWidget {
  final GenreStyle genreStyle;

  const _CoverPlaceholder({required this.genreStyle});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6B4A), Color(0xFFFFB648)],
            ),
          ),
        ),
        Center(
          child: Icon(genreStyle.icon, color: Colors.white.withOpacity(0.92), size: 40),
        ),
      ],
    );
  }
}

class _GenreTag extends StatelessWidget {
  final GenreStyle style;

  const _GenreTag({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double fraction;

  const _ProgressBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      color: Colors.black.withOpacity(0.45),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        alignment: Alignment.centerLeft,
        child: Container(color: const Color(0xFFF0E68C)),
      ),
    );
  }
}

class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3FA66B)),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
    );
  }
}
