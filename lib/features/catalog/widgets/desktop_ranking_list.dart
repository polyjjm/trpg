import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../models/genre_style.dart';
import '../models/ranking_snapshot.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE7E2DA);
const Color _muted = Color(0xFF85817B);
const Color _rankRest = Color(0xFF696660);
const Color _orange = Color(0xFFF47A2A);
const Color _up = Color(0xFF86C55A);
const Color _down = Color(0xFFE77965);
const Color _newText = Color(0xFFFFA45F);

const List<Color> _medalColors = [
  Color(0xFFFFC94D),
  Color(0xFFD3D6DB),
  Color(0xFFD79A66),
];

/// 데스크톱 홈 오른쪽의 실시간 랭킹 패널.
class DesktopRankingList extends StatelessWidget {
  final RankingSnapshotPair snapshot;
  final List<StoryPack> allPacks;
  final List<Genre> genres;
  final int maxRows;

  const DesktopRankingList({
    super.key,
    required this.snapshot,
    required this.allPacks,
    required this.genres,
    this.maxRows = 5,
  });

  StoryPack? _findPack(String id) {
    for (final pack in allPacks) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  String _genreLabel(StoryPack pack) {
    final slug = pack.primaryGenre;
    if (slug.isEmpty) return '기타';
    for (final genre in genres) {
      if (genre.slug == slug) return genre.name;
    }
    return slug;
  }

  String _formatLabel(StoryPack pack) =>
      pack.format == StoryPackFormat.interactive ? '인터랙티브' : '일반소설';

  @override
  Widget build(BuildContext context) {
    final rows = <_RankRowData>[];
    for (var i = 0; i < snapshot.todayPackIds.length; i++) {
      if (rows.length >= maxRows) break;
      final pack = _findPack(snapshot.todayPackIds[i]);
      if (pack == null) continue;
      final prevIndex = snapshot.yesterdayPackIds.indexOf(pack.id);
      rows.add(
        _RankRowData(
          pack: pack,
          rank: i + 1,
          previousRank: prevIndex == -1 ? null : prevIndex + 1,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151515), Color(0xFF0D0D0D)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '실시간 랭킹',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                ),
              ),
              const Spacer(),
              Text(
                'NOW',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: _orange.withOpacity(0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18, horizontal: 2),
              child: Text(
                '아직 집계된 데이터가 없어요',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
            )
          else
            for (final row in rows)
              _RankRow(
                data: row,
                genreLabel: _genreLabel(row.pack),
                formatLabel: _formatLabel(row.pack),
              ),
        ],
      ),
    );
  }
}

class _RankRowData {
  final StoryPack pack;
  final int rank;
  final int? previousRank;

  const _RankRowData({
    required this.pack,
    required this.rank,
    required this.previousRank,
  });
}

class _RankRow extends StatelessWidget {
  final _RankRowData data;
  final String genreLabel;
  final String formatLabel;

  const _RankRow({
    required this.data,
    required this.genreLabel,
    required this.formatLabel,
  });

  @override
  Widget build(BuildContext context) {
    final pack = data.pack;
    final coverUrl = pack.coverImageUrl;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.045)),
          ),
        ),
        child: Row(
          children: [
            _RankNumber(rank: data.rank),
            const SizedBox(width: 11),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 56,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _CoverFallback(genreSlug: pack.primaryGenre),
                      )
                    : _CoverFallback(genreSlug: pack.primaryGenre),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pack.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _ivory,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$genreLabel · $formatLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RankChangeIndicator(
              rank: data.rank,
              previousRank: data.previousRank,
            ),
          ],
        ),
      ),
    );
  }
}

/// 목업처럼 1~3위가 한눈에 들어오도록 숫자 자체를 독립적인 메달 오브제로
/// 만든다. 4위부터는 장식을 줄여 정보 밀도를 유지한다.
class _RankNumber extends StatelessWidget {
  final int rank;

  const _RankNumber({required this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank > 3) {
      return SizedBox(
        width: 42,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _rankRest,
          ),
        ),
      );
    }

    final color = _medalColors[rank - 1];
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.07),
        border: Border.all(color: color.withOpacity(0.65), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(rank == 1 ? 0.16 : 0.08),
            blurRadius: rank == 1 ? 14 : 8,
          ),
        ],
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}

class _RankChangeIndicator extends StatelessWidget {
  final int rank;
  final int? previousRank;

  const _RankChangeIndicator({
    required this.rank,
    required this.previousRank,
  });

  @override
  Widget build(BuildContext context) {
    final previousRank = this.previousRank;
    if (previousRank == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(
            fontSize: 10,
            color: _newText,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    if (rank < previousRank) {
      return const Icon(Icons.arrow_upward_rounded, size: 15, color: _up);
    }
    if (rank > previousRank) {
      return const Icon(Icons.arrow_downward_rounded, size: 15, color: _down);
    }
    return const Icon(Icons.remove_rounded, size: 15, color: _muted);
  }
}

class _CoverFallback extends StatelessWidget {
  final String genreSlug;

  const _CoverFallback({required this.genreSlug});

  @override
  Widget build(BuildContext context) {
    final style = genreStyleFor(genreSlug);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF47A2A), Color(0xFFB54818)],
        ),
      ),
      child: Center(
        child: Icon(style.icon, color: Colors.white, size: 18),
      ),
    );
  }
}
