import 'package:flutter/material.dart';

import '../../../core/state/game_state_scope.dart';
import '../../../core/state/reading_progress.dart';
import '../models/genre_style.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';
import 'type_badge.dart';

const Color _ivory = Color(0xFFE7E2DA);
const Color _muted = Color(0xFF8E8A84);
const Color _orange = Color(0xFFF47A2A);

/// 이야기 카드 공용 비율. 데스크톱에서는 카드 자체를 예전보다 크게 잡아
/// 콘텐츠가 1~2개여도 너무 작게 흩어져 보이지 않게 한다.
const double storyCoverAspectRatio = 0.78;

SliverGridDelegateWithMaxCrossAxisExtent storyCoverGridDelegate({
  double maxCrossAxisExtent = 260,
}) {
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxCrossAxisExtent,
    mainAxisSpacing: 16,
    crossAxisSpacing: 16,
    childAspectRatio: storyCoverAspectRatio,
  );
}

const double storyGridWideBreakpoint = 600;

/// 홈/검색/내 서재가 공유하는 스토리 카드.
/// 넓은 카드에서는 표지 아래에 설명까지 보여 주고, 좁은 모바일 카드에서는
/// 설명을 자동으로 감춰 기존의 컴팩트한 밀도를 유지한다.
class StoryCoverCard extends StatelessWidget {
  final StoryPack pack;
  final bool showGenreTag;
  final bool showPriceRow;
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
    final coverUrl = pack.coverImageUrl;
    final owned = GameStateScope.of(context).ownsPack(pack.id);
    final completed = progress?.completed ?? false;
    final progressFraction = (progress != null && pack.publishedNodeCount > 0)
        ? (progress!.visitedNodeCount / pack.publishedNodeCount).clamp(0.0, 1.0)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final roomy = constraints.maxWidth >= 205;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
            ),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF151515), Color(0xFF0D0D0D)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: roomy ? 7 : 8,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (coverUrl != null && coverUrl.isNotEmpty)
                            Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _CoverPlaceholder(genreStyle: genreStyle),
                            )
                          else
                            _CoverPlaceholder(genreStyle: genreStyle),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Color(0x80000000), Colors.transparent],
                                stops: [0.0, 0.55],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: TypeBadge(format: pack.format, size: 24),
                          ),
                          if (showGenreTag)
                            Positioned(
                              right: 10,
                              top: 10,
                              child: _GenreTag(style: genreStyle),
                            ),
                          if (completed)
                            const Positioned(
                              right: 10,
                              bottom: 10,
                              child: _CompletedBadge(),
                            ),
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
                  Expanded(
                    flex: roomy ? 5 : 4,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        roomy ? 14 : 10,
                        roomy ? 12 : 8,
                        roomy ? 14 : 10,
                        roomy ? 12 : 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: roomy ? 15 : 13.5,
                              fontWeight: FontWeight.w800,
                              color: _ivory,
                            ),
                          ),
                          if (roomy && pack.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              pack.description.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                color: _muted,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (showPriceRow)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    pack.isFree
                                        ? '무료'
                                        : (owned
                                              ? '보유중'
                                              : '${pack.effectivePrice}코인'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: owned
                                          ? const Color(0xFF67B97A)
                                          : (pack.isFree ? _orange : _ivory),
                                    ),
                                  ),
                                ),
                                Text(
                                  pack.format.label,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  final GenreStyle genreStyle;

  const _CoverPlaceholder({required this.genreStyle});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF47A2A), Color(0xFF9E3716)],
        ),
      ),
      child: Center(
        child: Icon(
          genreStyle.icon,
          color: Colors.white.withOpacity(0.92),
          size: 38,
        ),
      ),
    );
  }
}

class _GenreTag extends StatelessWidget {
  final GenreStyle style;

  const _GenreTag({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        style.label,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
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
      height: 4,
      color: Colors.black.withOpacity(0.45),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        alignment: Alignment.centerLeft,
        child: const ColoredBox(color: _orange),
      ),
    );
  }
}

class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF67B97A),
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
    );
  }
}
