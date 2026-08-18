import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/ads/ad_ids.dart';
import '../../../core/constants/asset_paths.dart';
import '../../../core/constants/external_links.dart';
import '../../../core/platform/open_external_link.dart';
import '../../../core/state/game_state_scope.dart';
import '../../wallet/pages/charge_page.dart';
import '../data/story_pack_repository.dart';
import '../models/genre_style.dart';
import '../models/story_pack.dart';
import '../widgets/story_pack_card.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 하단 탭의 "홈" — 이야기 팩을 둘러보고 검색하는 화면. 공지사항은
/// 별도 탭(NoticeListTab)으로 옮겨갔다. 팩을 고르면 상세 화면으로 넘어간다.
class HomeTab extends StatefulWidget {
  /// 웹에서 author/admin 계정으로 열었을 때만 true — 나머지 계정(reader가
  /// 대부분)은 이 링크 자체가 존재하지 않는 것처럼 화면에서 완전히 빠진다.
  final bool showAuthorModeLink;

  const HomeTab({super.key, this.showAuthorModeLink = false});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  final StoryPackRepository _packRepository = StoryPackRepository();
  late final Stream<List<StoryPack>> _packsStream = _packRepository.watchVisiblePacks();

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    final bannerAd = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _isBannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('배너 광고 로드 실패: $error');
          ad.dispose();
          _bannerAd = null;
        },
      ),
    );

    _bannerAd = bannerAd;
    bannerAd.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cashBalance = GameStateScope.of(context).cashBalance;

    // CatalogShellPage가 유일한 Scaffold(+ 하단 탭바)를 갖고, 각 탭은 그
    // body 콘텐츠만 반환한다 — 탭마다 Scaffold를 중첩하지 않는다.
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, cashBalance),
              const SizedBox(height: 18),
              _buildBannerAd(),
              _buildSearchField(),
              const SizedBox(height: 24),
              Expanded(
                child: StreamBuilder<List<StoryPack>>(
                  stream: _packsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '스토리팩 목록을 불러오지 못했어요',
                          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
                        ),
                      );
                    }

                    final packs = snapshot.data ?? const <StoryPack>[];
                    final query = _query.trim().toLowerCase();
                    final filteredPacks = query.isEmpty
                        ? packs
                        : packs
                            .where((pack) =>
                                pack.title.toLowerCase().contains(query) ||
                                pack.authorName.toLowerCase().contains(query))
                            .toList();

                    if (query.isEmpty) {
                      return _buildBrowseSections(packs);
                    }
                    return filteredPacks.isEmpty ? _buildEmptyResult() : _buildSearchResults(filteredPacks);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int cashBalance) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.14),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withOpacity(0.40)),
              ),
              child: SvgPicture.asset(UiPaths.logo),
            ),
            const SizedBox(width: 10),
            const Text(
              'TELO',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.0,
                color: _ivory,
              ),
            ),
            const Spacer(),
            _buildCashChip(context, cashBalance),
          ],
        ),
        if (widget.showAuthorModeLink) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => openExternalLink(ExternalLinks.authorToolUrl),
            child: Text(
              '작가 모드로 전환',
              style: TextStyle(fontSize: 11, color: _ivory.withOpacity(0.38)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCashChip(BuildContext context, int cashBalance) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChargePage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withOpacity(0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on_rounded, color: _gold, size: 16),
            const SizedBox(width: 4),
            Text(
              '$cashBalance',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _ivory,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '충전',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerAd() {
    final bannerAd = _bannerAd;
    if (!_isBannerLoaded || bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: SizedBox(
          width: bannerAd.size.width.toDouble(),
          height: bannerAd.size.height.toDouble(),
          child: AdWidget(ad: bannerAd),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '제목 또는 작가로 검색',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: _ivory.withOpacity(0.60), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: _ivory,
        letterSpacing: 0.3,
      ),
    );
  }

  /// 검색 중이 아닐 때 보여주는 섹션들. 형식(인터랙티브/소설)으로 먼저 나누고,
  /// 그 안에서 장르별로 가로 스크롤 행을 만든다 — 형식/장르 둘 다 실제 데이터
  /// 기준이라 "인기"/"신작" 같은 근거 없는 구분과는 다르다. 팩이 하나도 없는
  /// 형식 섹션은 통째로 숨긴다.
  Widget _buildBrowseSections(List<StoryPack> packs) {
    if (packs.isEmpty) {
      return Center(
        child: Text(
          '아직 연재 중인 스토리가 없어요',
          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
        ),
      );
    }

    final interactivePacks = packs.where((pack) => pack.format == StoryPackFormat.interactive).toList();
    final linearPacks = packs.where((pack) => pack.format == StoryPackFormat.linear).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        if (interactivePacks.isNotEmpty) ..._buildTypeSection('인터랙티브', interactivePacks),
        if (interactivePacks.isNotEmpty && linearPacks.isNotEmpty) const SizedBox(height: 28),
        if (linearPacks.isNotEmpty) ..._buildTypeSection('소설', linearPacks),
      ],
    );
  }

  /// 형식 섹션 하나(제목 + 장르별 가로 스크롤 행들). 장르는 별도
  /// genres 컬렉션을 읽지 않고 팩에 실제로 등장하는 순서대로 나열한다.
  List<Widget> _buildTypeSection(String title, List<StoryPack> packs) {
    final genreGroups = <String, List<StoryPack>>{};
    for (final pack in packs) {
      genreGroups.putIfAbsent(pack.primaryGenre, () => []).add(pack);
    }

    final entries = genreGroups.entries.toList();
    return [
      _buildSectionTitle(title),
      for (var i = 0; i < entries.length; i++) ...[
        const SizedBox(height: 18),
        _buildGenreLabel(entries[i].key),
        const SizedBox(height: 10),
        _buildHorizontalPackRow(entries[i].value),
      ],
    ];
  }

  Widget _buildGenreLabel(String genreSlug) {
    return Text(
      genreStyleFor(genreSlug).label,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory.withOpacity(0.72)),
    );
  }

  Widget _buildHorizontalPackRow(List<StoryPack> packs) {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: packs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) => SizedBox(
          width: 148,
          child: StoryPackCard(pack: packs[index]),
        ),
      ),
    );
  }

  Widget _buildSearchResults(List<StoryPack> packs) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: packs.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 18,
        crossAxisSpacing: 16,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (context, index) => StoryPackCard(pack: packs[index]),
    );
  }

  Widget _buildEmptyResult() {
    return Center(
      child: Text(
        '검색 결과가 없습니다',
        style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
      ),
    );
  }
}
