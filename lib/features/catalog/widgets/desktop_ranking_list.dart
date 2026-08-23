import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../models/genre_style.dart';
import '../models/ranking_snapshot.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _muted = Color(0xFF83817A);
const Color _rankRest = Color(0xFF5F5E5A);
const Color _up = Color(0xFF97C459);
const Color _down = Color(0xFFF09595);
const Color _newBg = Color(0xFF854F0B);
const Color _newText = Color(0xFFFAEEDA);

/// 1~3위 숫자 색 — RankingSection의 TOP3 메달 배지와 같은 값.
const List<Color> _medalColors = [
  Color(0xFFFFC94D),
  Color(0xFFD3D6DB),
  Color(0xFFD79A66),
];

/// 데스크톱 홈의 오른쪽 컬럼에 들어가는 컴팩트 랭킹 목록.
///
/// 모바일의 [RankingSection]과 데이터는 같지만 표현이 다르다 — TOP3를 큰
/// 카드로 띄우지 않고 1위부터 한 줄씩 같은 모양으로 쌓는다. 이유는 두 가지다:
///
/// 1. 320px 사이드바에서 3/4 비율 카드 3장을 나란히 놓으면 카드 하나가 92px
///    남짓으로 쪼그라들어 제목이 거의 안 읽힌다.
/// 2. rankingSnapshots에 팩이 1~2개만 있을 때(집계 초기, 실제로 그런 상태였다)
///    3열 카드 행에 카드가 하나만 놓여 옆이 통째로 비어 보인다. 한 줄 목록은
///    항목 수가 몇 개든 위에서부터 자연스럽게 채워진다.
///
/// TOP3 구분은 숫자 색(금/은/동) + 굵기로만 준다.
class DesktopRankingList extends StatelessWidget {
  final RankingSnapshotPair snapshot;
  final List<StoryPack> allPacks;
  final List<Genre> genres;

  /// 보여줄 최대 줄 수 — 왼쪽 컬럼(배너 + 번들 상품) 높이와 대충 맞는 값.
  /// 데이터가 이보다 적으면 있는 만큼만 그린다.
  final int maxRows;

  const DesktopRankingList({
    super.key,
    required this.snapshot,
    required this.allPacks,
    required this.genres,
    this.maxRows = 7,
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

  /// RankingSection과 같은 규칙 — 이 섹션만 '선형'을 '일반소설'로 부른다.
  String _formatLabel(StoryPack pack) =>
      pack.format == StoryPackFormat.interactive ? '인터랙티브' : '일반소설';

  @override
  Widget build(BuildContext context) {
    final rows = <_RankRowData>[];
    for (var i = 0; i < snapshot.todayPackIds.length; i++) {
      if (rows.length >= maxRows) break;
      final pack = _findPack(snapshot.todayPackIds[i]);
      if (pack == null) continue; // 랭킹엔 있지만 지금은 안 보이는 팩 — 건너뛴다.
      final prevIndex = snapshot.yesterdayPackIds.indexOf(pack.id);
      rows.add(_RankRowData(
        pack: pack,
        rank: i + 1,
        previousRank: prevIndex == -1 ? null : prevIndex + 1,
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              '실시간 랭킹',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ivory),
            ),
          ),
          if (rows.isEmpty)
            // 조용히 사라지면 "이 섹션이 원래 없다"와 "데이터가 아직 없다"를
            // 구분할 수 없다 — RankingSection과 같은 문구를 쓴다.
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Text('아직 집계된 데이터가 없어요', style: TextStyle(fontSize: 13, color: _muted)),
            )
          else
            for (final row in rows) _RankRow(
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

  const _RankRowData({required this.pack, required this.rank, required this.previousRank});
}

class _RankRow extends StatelessWidget {
  final _RankRowData data;
  final String genreLabel;
  final String formatLabel;

  const _RankRow({required this.data, required this.genreLabel, required this.formatLabel});

  @override
  Widget build(BuildContext context) {
    final pack = data.pack;
    final isTop3 = data.rank <= 3;
    final coverUrl = pack.coverImageUrl;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '${data.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isTop3 ? FontWeight.w700 : FontWeight.normal,
                  color: isTop3 ? _medalColors[data.rank - 1] : _rankRest,
                ),
              ),
            ),
            const SizedBox(width: 11),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 34,
                height: 45,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _CoverFallback(genreSlug: pack.primaryGenre),
                      )
                    : _CoverFallback(genreSlug: pack.primaryGenre),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pack.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: _ivory),
                  ),
                  const SizedBox(height: 2),
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
            _RankChangeIndicator(rank: data.rank, previousRank: data.previousRank),
          ],
        ),
      ),
    );
  }
}

class _RankChangeIndicator extends StatelessWidget {
  final int rank;
  final int? previousRank;

  const _RankChangeIndicator({required this.rank, required this.previousRank});

  @override
  Widget build(BuildContext context) {
    final previousRank = this.previousRank;
    if (previousRank == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: _newBg, borderRadius: BorderRadius.circular(8)),
        child: const Text('NEW', style: TextStyle(fontSize: 10, color: _newText, fontWeight: FontWeight.w700)),
      );
    }
    if (rank < previousRank) {
      return const Icon(Icons.arrow_upward_rounded, size: 13, color: _up);
    }
    if (rank > previousRank) {
      return const Icon(Icons.arrow_downward_rounded, size: 13, color: _down);
    }
    return const Icon(Icons.remove_rounded, size: 13, color: _muted);
  }
}

/// 표지가 없거나 로드에 실패했을 때 — StoryCoverCard의 _CoverPlaceholder와
/// 같은 조합(브랜드 그라디언트 + 장르 아이콘).
class _CoverFallback extends StatelessWidget {
  final String genreSlug;

  const _CoverFallback({required this.genreSlug});

  @override
  Widget build(BuildContext context) {
    final style = genreStyleFor(genreSlug);
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFE2703A)),
      child: Center(
        child: Icon(style.icon, color: Colors.white.withOpacity(0.92), size: 16),
      ),
    );
  }
}
