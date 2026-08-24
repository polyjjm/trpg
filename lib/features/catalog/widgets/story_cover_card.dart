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

/// 모바일 가로 스크롤 행이 기존 카드 높이를 계산할 때 쓰는 비율.
const double storyCoverAspectRatio = 0.78;

/// 넓은 화면의 홈/검색/서재 그리드는 목업처럼 '왼쪽 표지 + 오른쪽 정보' 카드로
/// 보이게 한다. 모바일의 118px 카드에는 이 delegate가 쓰이지 않는다.
SliverGridDelegateWithMaxCrossAxisExtent storyCoverGridDelegate({
  double maxCrossAxisExtent = 420,
}) {
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxCrossAxisExtent,
    mainAxisSpacing: 16,
    crossAxisSpacing: 16,
    childAspectRatio: 2.05,
  );
}

const double storyGridWideBreakpoint = 600;

/// 홈/검색/내 서재가 공유하는 스토리 카드.
/// 205px 이상이면 왼쪽 표지 + 오른쪽 제목/설명/가격의 가로 카드,
/// 그보다 좁으면 기존 세로형 카드로 그린다.
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
        final horizontal = constraints.maxWidth >= 205;
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
              child: horizontal
                  ? _HorizontalStoryCard(
                      pack: pack,
                      genreStyle: genreStyle,
                      coverUrl: coverUrl,
                      owned: owned,
                      completed: completed,
                      progressFraction: progressFraction,
                      showGenreTag: showGenreTag,
                      showPriceRow: showPriceRow,
                    )
                  : _VerticalStoryCard(
                      pack: pack,
                      genreStyle: genreStyle,
                      coverUrl: coverUrl,
                      owned: owned,
                      completed: completed,
                      progressFraction: progressFraction,
                      showGenreTag: showGenreTag,
                      showPriceRow: showPriceRow,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _HorizontalStoryCard extends StatelessWidget {
  final StoryPack pack;
  final GenreStyle genreStyle;
  final String? coverUrl;
  final bool owned;
  final bool completed;
  final double? progressFraction;
  final bool showGenreTag;
  final bool showPriceRow;

  const _HorizontalStoryCard({
    required this.pack,
    required this.genreStyle,
    required this.coverUrl,
    required this.owned,
    required this.completed,
    required this.progressFraction,
    required this.showGenreTag,
    required this.showPriceRow,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 132,
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
            child: _CoverArea(
              pack: pack,
              genreStyle: genreStyle,
              coverUrl: coverUrl,
              completed: completed,
              progressFraction: progressFraction,
              showGenreTag: showGenreTag,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pack.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ivory,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      pack.format.label,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                if (pack.description.trim().isNotEmpty)
                  Text(
                    pack.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: _muted,
                    ),
                  )
                else
                  Text(
                    pack.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                const Spacer(),
                if (showPriceRow)
                  Row(
                    children: [
                      Text(
                        pack.isFree
                            ? '무료'
                            : (owned ? '보유중' : '${pack.effectivePrice}코인'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: owned
                              ? const Color(0xFF67B97A)
                              : (pack.isFree ? _orange : _ivory),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: _ivory.withOpacity(0.38),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VerticalStoryCard extends StatelessWidget {
  final StoryPack pack;
  final GenreStyle genreStyle;
  final String? coverUrl;
  final bool owned;
  final bool completed;
  final double? progressFraction;
  final bool showGenreTag;
  final bool showPriceRow;

  const _VerticalStoryCard({
    required this.pack,
    required this.genreStyle,
    required this.coverUrl,
    required this.owned,
    required this.completed,
    required this.progressFraction,
    required this.showGenreTag,
    required this.showPriceRow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: _CoverArea(
              pack: pack,
              genreStyle: genreStyle,
              coverUrl: coverUrl,
              completed: completed,
              progressFraction: progressFraction,
              showGenreTag: showGenreTag,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pack.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                ),
              ),
              if (showPriceRow) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pack.isFree
                            ? '무료'
                            : (owned ? '보유중' : '${pack.effectivePrice}코인'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
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
                        fontSize: 10,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverArea extends StatelessWidget {
  final StoryPack pack;
  final GenreStyle genreStyle;
  final String? coverUrl;
  final bool completed;
  final double? progressFraction;
  final bool showGenreTag;

  const _CoverArea({
    required this.pack,
    required this.genreStyle,
    required this.coverUrl,
    required this.completed,
    required this.progressFraction,
    required this.showGenreTag,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverUrl != null && coverUrl!.isNotEmpty)
          Image.network(
            coverUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _CoverPlaceholder(genreStyle: genreStyle),
          )
        else
          _CoverPlaceholder(genreStyle: genreStyle),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0x70000000), Colors.transparent],
              stops: [0.0, 0.55],
            ),
          ),
        ),
        Positioned(
          left: 9,
          top: 9,
          child: TypeBadge(format: pack.format, size: 23),
        ),
        if (showGenreTag)
          Positioned(
            right: 8,
            top: 8,
            child: _GenreTag(style: genreStyle),
          ),
        if (completed)
          const Positioned(right: 9, bottom: 9, child: _CompletedBadge()),
        if (!completed && progressFraction != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ProgressBar(fraction: progressFraction!),
          ),
      ],
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
