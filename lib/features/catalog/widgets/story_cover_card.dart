import 'package:flutter/material.dart';

import '../../../core/state/game_state_scope.dart';
import '../../../core/state/reading_progress.dart';
import '../models/genre_style.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';
import 'type_badge.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 홈 탭의 넓은 화면 장르 그리드와 내 서재 그리드가 공유하는 배치.
///
/// ⚠️ 예전엔 crossAxisCount(열 개수)를 호출부가 직접 골랐는데, 그러면 두
/// 화면이 서로 다른 열 개수를 넘기는 순간(예: 홈 8열, 내 서재 6열) 화면
/// 폭이 같아도 카드 크기가 달라진다 — 실제로 그렇게 어긋난 적이 있었다.
/// maxCrossAxisExtent(카드 한 장의 최대 폭)로 바꾸면 호출부가 열 개수를
/// 몰라도 되고, 화면 폭이 얼마든 카드 폭 자체가 고정되니 두 화면이 항상
/// 같은 크기로 나온다 — 검색 결과 그리드(_buildPackGrid)와도 동일한 값을
/// 써서 앱 전체에서 카드 크기가 하나로 통일된다.
/// 이야기 팩 표지 카드의 가로:세로 비율(width/height) — 그리드(홈 장르
/// 그리드, 검색 결과, 내 서재)와 가로 스크롤 행(_buildHorizontalPackRow)이
/// 전부 이 상수 하나를 참조한다. 예전엔 가로 스크롤 행만 카드 높이를
/// 210으로 따로 하드코딩해놔서, 그리드 쪽 childAspectRatio를 아무리
/// 맞춰도 좁은 화면(모바일 폭)에서는 여전히 비율이 달라 보이는 문제가
/// 있었다 — 이제 폭이 주어지면 높이는 항상 `width / storyCoverAspectRatio`
/// 로 계산해서 어느 레이아웃을 타든 같은 비율이 나온다.
const double storyCoverAspectRatio = 0.6;

SliverGridDelegateWithMaxCrossAxisExtent storyCoverGridDelegate({
  double maxCrossAxisExtent = 150,
}) {
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxCrossAxisExtent,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: storyCoverAspectRatio,
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

  /// 제목 아래 가격/형식 줄 — 모든 화면에서 켜 둔다(showPriceRow: false를
  /// 준 화면이 하나만 있어도 그 화면만 카드 텍스트가 한 줄 줄어서 표지
  /// 비율이 미묘하게 어긋났던 적이 있다 — 클래스 상단 doc 참고). 가격
  /// 텍스트 자체는 [GameState.ownsPack]을 구독해서, 이미 보유한 유료
  /// 팩이면 가격 대신 "보유중"을 보여준다(무료 팩은 그대로 "무료") — 그래서
  /// 이 줄을 끄지 않고도 구매 여부가 자연스럽게 드러난다.
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
    // GameStateScope.of(context)를 build() 안에서 부르면 이 위젯이
    // GameState의 InheritedNotifier 구독자로 등록된다 — 구매 직후
    // markPackOwned()가 notifyListeners()를 부르는 순간, 이미 화면에 떠
    // 있는 카드들도(홈 탭 장르 행/그리드, 검색 결과) 별도 스트림 없이
    // 자동으로 다시 그려진다.
    final owned = GameStateScope.of(context).ownsPack(pack.id);
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
                    pack.isFree
                        ? '무료'
                        : (owned ? '보유중' : '${pack.effectivePrice}코인'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: owned ? FontWeight.w700 : FontWeight.normal,
                      color: owned ? const Color(0xFF3FA66B) : _ivory.withOpacity(0.62),
                    ),
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