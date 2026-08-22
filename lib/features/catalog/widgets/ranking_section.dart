import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../models/ranking_snapshot.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _muted = Color(0xFF83817A);
const Color _rankTop3 = Color(0xFFF0997B);
const Color _rankRest = Color(0xFF5F5E5A);
const Color _rowDivider = Color(0xFF2C2C2A);
const Color _up = Color(0xFF97C459);
const Color _down = Color(0xFFF09595);
const Color _newBg = Color(0xFF854F0B);
const Color _newText = Color(0xFFFAEEDA);

/// 홈 탭 "실시간 랭킹" 섹션 — rankingSnapshots의 오늘 packIds 순서를 순위로,
/// 어제 packIds와의 인덱스 비교로 순위 변동(▲/▼/-/NEW)을 계산해 세로 목록으로
/// 보여준다(doc/home_*_mockup.html 참고). 타입 배지 원은 안 쓰고 부제줄에
/// 텍스트로 "장르 · 타입"만 보여준다 — 다른 곳(StoryPackCard 등)과 다른
/// 표현이 이 섹션만의 의도된 디자인이다.
class RankingSection extends StatelessWidget {
  final RankingSnapshotPair snapshot;
  final List<StoryPack> allPacks;
  final List<Genre> genres;

  const RankingSection({
    super.key,
    required this.snapshot,
    required this.allPacks,
    required this.genres,
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
    final rows = <_RankingRowData>[];
    for (var i = 0; i < snapshot.todayPackIds.length; i++) {
      final pack = _findPack(snapshot.todayPackIds[i]);
      if (pack == null) continue; // 랭킹엔 있지만 지금은 안 보이는 팩(비공개 전환 등) — 건너뛴다.

      final rank = i + 1;
      final prevIndex = snapshot.yesterdayPackIds.indexOf(pack.id);
      rows.add(
        _RankingRowData(
          pack: pack,
          rank: rank,
          previousRank: prevIndex == -1 ? null : prevIndex + 1,
        ),
      );
    }

    final top3 = rows.take(3).toList();
    final rest = rows.skip(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '실시간 랭킹',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ivory),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
        // 조용히 통째로 사라지면 "이 섹션이 원래 없다"와 "데이터가 아직
        // 없다"를 구분할 수 없다 — 스냅샷 함수가 아직 한 번도 안 돌았거나
        // (예: 배포 직후) 결과가 진짜로 비어 있을 때 명시적으로 알려준다.
          Text(
            '아직 집계된 데이터가 없어요',
            style: TextStyle(fontSize: 13, color: _muted),
          )
        else ...[
          // TOP 3 — 메달 컬러로 구분된 카드형 하이라이트. 4위 이하의 담백한
          // 리스트와 시각적으로 확실히 나뉘도록 커버 이미지를 훨씬 크게
          // 쓰고, 순위 자체를 숫자가 아니라 메달 배지 색으로 먼저 읽히게 한다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < top3.length; i++) ...[
                if (i != 0) const SizedBox(width: 12),
                SizedBox(
                  width: 150, // 원하는 카드 폭으로 조정 가능
                  child: _TopRankCard(
                    data: top3[i],
                    genreLabel: _genreLabel(top3[i].pack),
                    formatLabel: _formatLabel(top3[i].pack),
                  ),
                ),
              ],
            ],
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 18),
            // 카드 구역과 리스트 구역 사이의 얇은 구분선 — 컨테이너 배경이
            // 이미 섹션 전체를 감싸고 있으니, 안에서는 색 대비 대신 이
            // 정도의 hairline 하나면 충분하다.
            const Divider(height: 1, thickness: 1, color: _rowDivider),
            const SizedBox(height: 6),
            for (var i = 0; i < rest.length; i++)
              _RankingRow(
                data: rest[i],
                genreLabel: _genreLabel(rest[i].pack),
                formatLabel: _formatLabel(rest[i].pack),
                showDivider: i != rest.length - 1,
              ),
          ],
        ],
      ],
    );
  }
}

/// TOP 3 전용 카드 — 금/은/동 톤 배지 + 큰 커버로, 목록(rest)과 다른
/// "하이라이트" 톤을 준다. 순위 변동 표시는 여기서도 그대로 보여준다(내려간
/// 1위도 있을 수 있으니).
class _TopRankCard extends StatelessWidget {
  final _RankingRowData data;
  final String genreLabel;
  final String formatLabel;

  const _TopRankCard({
    required this.data,
    required this.genreLabel,
    required this.formatLabel,
  });

  static const List<Color> _medalColors = [
    Color(0xFFFFC94D), // 1위 · 골드
    Color(0xFFD3D6DB), // 2위 · 실버
    Color(0xFFD79A66), // 3위 · 브론즈
  ];

  @override
  Widget build(BuildContext context) {
    final pack = data.pack;
    final medalColor = _medalColors[(data.rank - 1).clamp(0, 2)];
    final coverUrl = pack.coverImageUrl;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverUrl != null && coverUrl.isNotEmpty
                        ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _RankingCoverFallback(),
                    )
                        : const _RankingCoverFallback(),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: medalColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4, offset: const Offset(0, 1)),
                      ],
                    ),
                    child: Text(
                      '${data.rank}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF2A2A28)),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: _RankChangeIndicator(rank: data.rank, previousRank: data.previousRank),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pack.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ivory),
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
    );
  }
}

class _RankingRowData {
  final StoryPack pack;
  final int rank;
  final int? previousRank;

  const _RankingRowData({required this.pack, required this.rank, required this.previousRank});
}

class _RankingRow extends StatelessWidget {
  final _RankingRowData data;
  final String genreLabel;
  final String formatLabel;
  final bool showDivider;

  const _RankingRow({
    required this.data,
    required this.genreLabel,
    required this.formatLabel,
    required this.showDivider,
  });

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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: showDivider ? const Border(bottom: BorderSide(color: _rowDivider)) : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '${data.rank}',
                style: TextStyle(
                  fontSize: isTop3 ? 18 : 15,
                  fontWeight: isTop3 ? FontWeight.w600 : FontWeight.normal,
                  color: isTop3 ? _rankTop3 : _rankRest,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 40,
                height: 40 * 4 / 3,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _RankingCoverFallback(),
                )
                    : const _RankingCoverFallback(),
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

class _RankingCoverFallback extends StatelessWidget {
  const _RankingCoverFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFFF6B4A), Color(0xFFFFB648)]),
      ),
    );
  }
}