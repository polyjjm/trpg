import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ads/ad_ids.dart';
import '../../../core/constants/asset_paths.dart';
import '../../../core/constants/external_links.dart';
import '../../../core/platform/open_external_link.dart';
import '../../../core/state/game_state_scope.dart';
import '../../wallet/pages/charge_page.dart';
import '../data/genre_repository.dart';
import '../data/home_banner_repository.dart';
import '../data/ranking_repository.dart';
import '../data/story_pack_repository.dart';
import '../models/genre.dart';
import '../models/home_banner.dart';
import '../models/ranking_snapshot.dart';
import '../models/story_pack.dart';
import '../widgets/hero_banner_section.dart';
import '../widgets/library_header.dart';
import '../widgets/ranking_section.dart';
import '../widgets/shelf_ledge_divider.dart';
import '../widgets/story_cover_card.dart';
import 'story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 최근 검색어를 저장하는 SharedPreferences 키 — 계정이 아니라 기기에
/// 묶인 단순한 로컬 목록이다(요구사항 그대로: "simple local list").
const String _recentSearchesPrefsKey = 'home_recent_searches';
const int _maxRecentSearches = 10;

/// 하단 탭의 "홈" — 이야기 팩을 둘러보고 검색하는 화면. 위쪽은 책장 삽화
/// 헤더(LibraryHeader, 워드마크 + 이어읽기 카드), 그 아래는 평소의 플랫
/// 다크 배경으로 돌아가 히어로 배너(이미지 전용, admin이 관리하는
/// homeBanners) + 실시간 랭킹 + 장르별 진열 행이 이어진다. 공지사항은 별도
/// 탭(NoticeListTab)으로 옮겨갔다. 팩을 고르면 상세 화면으로 넘어간다.
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
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';

  /// 검색은 헤더 아이콘을 누르면 열리는 전체 화면 오버레이다(예전엔 그
  /// 자리에 가로로 좁은 바만 펼쳐졌다) — 오버레이가 닫히면(검색 제출/최근
  /// 검색어 선택/닫기 버튼) 그제서야 _query가 반영되어 브라우즈 화면이
  /// 검색 결과로 바뀐다.
  bool _searchOverlayOpen = false;
  List<String> _recentSearches = [];

  final StoryPackRepository _packRepository = StoryPackRepository();
  late final Stream<List<StoryPack>> _packsStream = _packRepository.watchVisiblePacks();

  final GenreRepository _genreRepository = GenreRepository();
  late final Stream<List<Genre>> _genresStream = _genreRepository.watchActiveGenres();

  final HomeBannerRepository _bannerRepository = HomeBannerRepository();
  late final Stream<List<HomeBanner>> _bannersStream = _bannerRepository.watchActiveBanners();

  final RankingRepository _rankingRepository = RankingRepository();
  late final Future<RankingSnapshotPair> _rankingFuture = _rankingRepository.fetchLatest();

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadRecentSearches();
    // 헤더 삽화(SvgPicture.asset)가 첫 프레임에 아직 로딩 중이라 빈 프레임이
    // 잠깐 보이는 걸 막기 위해 미리 디코딩해 svg.cache에 채워 둔다 —
    // LibraryHeader가 실제로 build될 때는 이미 캐시에 있으니 동기적으로 그려진다.
    unawaited(SvgAssetLoader(UiPaths.bookshelfBackground).loadBytes(null));
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // `?? const []`이면(처음 켰을 때, 저장된 값이 없을 때) 이후 첫 검색에서
      // _recentSearches.remove(...)가 "Unsupported operation: remove"로
      // 터진다 — const 리스트는 불변이라서다. growable로 명시해서 새로
      // 만든다(getStringList가 돌려주는 값 자체가 growable인지도 플랫폼마다
      // 보장이 안 돼서, 안전하게 List.of로 한 번 더 감싼다).
      final saved = prefs.getStringList(_recentSearchesPrefsKey);
      final growable = saved == null ? <String>[] : List<String>.of(saved);
      if (mounted) setState(() => _recentSearches = growable);
    } catch (_) {
      // 저장소 접근이 막힌 환경이어도 검색 자체는 계속 동작해야 한다 —
      // 최근 검색어만 비어 있는 채로 조용히 넘어간다.
    }
  }

  Future<void> _persistRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentSearchesPrefsKey, _recentSearches);
    } catch (_) {
      // 이번 세션 안에서는 여전히 동작하니, 저장 실패만 조용히 넘어간다.
    }
  }

  void _openSearchOverlay() {
    setState(() => _searchOverlayOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocusNode.requestFocus());
  }

  void _closeSearchOverlay() {
    setState(() => _searchOverlayOpen = false);
    _searchFocusNode.unfocus();
  }

  /// 검색어를 확정한다 — 텍스트 필드에서 엔터를 치거나, 최근 검색어 목록의
  /// 항목을 탭했을 때 둘 다 이 경로를 탄다("탭하면 그 검색어로 다시
  /// 검색한다"). 오버레이를 닫고 브라우즈 화면을 검색 결과로 바꾼 뒤, 빈
  /// 검색어가 아니면 최근 검색어 맨 앞에 올린다(이미 있던 항목이면 중복
  /// 대신 앞으로 옮긴다).
  void _submitSearch(String rawQuery) {
    final query = rawQuery.trim();
    _searchController.text = query;
    setState(() {
      _query = query;
      _searchOverlayOpen = false;
    });
    _searchFocusNode.unfocus();
    if (query.isEmpty) return;

    setState(() {
      _recentSearches.remove(query);
      _recentSearches.insert(0, query);
      if (_recentSearches.length > _maxRecentSearches) {
        _recentSearches = _recentSearches.sublist(0, _maxRecentSearches);
      }
    });
    unawaited(_persistRecentSearches());
  }

  void _removeRecentSearch(String query) {
    setState(() => _recentSearches.remove(query));
    unawaited(_persistRecentSearches());
  }

  void _clearRecentSearches() {
    setState(() => _recentSearches = []);
    unawaited(_persistRecentSearches());
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
    _searchFocusNode.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // CatalogShellPage가 유일한 Scaffold(+ 하단 탭바)를 갖고, 각 탭은 그
    // body 콘텐츠만 반환한다 — 탭마다 Scaffold를 중첩하지 않는다.
    //
    // 콘텐츠 최대 폭 캡은 없다 — 브라우저 실제 폭 그대로 꽉 채운다(목업
    // doc/home_*_mockup.html 기준, full-bleed). 헤더(LibraryHeader)만
    // 자체 여백/둥근 모서리를 그대로 유지한다 — 그건 캡과 무관하게 헤더
    // 자체의 스타일 선택이다.
    // ⚠️ LibraryHeader(책장 일러스트 헤더)를 완전히 제거했다 — 실사용
    // 기기 한 대에서 그 컴포넌트가 있던 자리 전체가 어떤 내용을 넣든
    // (진짜 일러스트든, 단색 테스트 박스든) 검게 나오는 문제가 있었고,
    // 구조/에셋 양쪽을 다 소거법으로 확인했지만 원인을 못 찾았다. 헤더
    // 자체를 없애고 검색 아이콘만 아주 작게 남긴다 — 이어읽기 카드도
    // 같이 없앤다(다시 넣으려면 이 주석 위치에 복원).
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: Row(
                      children: [
                        const Text(
                          'Telo',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: _ivory,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _openSearchOverlay,
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.search_rounded, color: _ivory.withOpacity(0.85), size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildBannerAd(),
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
                        return filteredPacks.isEmpty
                            ? _buildEmptyResult()
                            : _buildSearchResults(filteredPacks);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 헤더 바로 아래(이 Stack이 곧 헤더 아래 영역)에서 아래로
          // 슬라이드해 펼쳐지는 검색 오버레이 — 닫혀 있을 때도
          // 트리에는 남아 있지만 화면 위로 밀려나 있고
          // IgnorePointer로 탭도 안 먹는다.
          Positioned.fill(child: _buildSearchOverlay()),
        ],
      ),
    );
  }

  void _openPack(BuildContext context, StoryPack pack) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
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

  /// 헤더 바로 아래 영역을 덮는 전체 화면 검색 — 위에 텍스트 입력, 아래에
  /// "최근 검색어" 목록(비어 있으면 안내 문구). 검색 결과 자체는 이 오버레이
  /// 안이 아니라 오버레이가 닫힌 뒤 뒤쪽 브라우즈 화면에 나온다(제출/최근
  /// 검색어 탭 → _submitSearch가 오버레이를 닫고 _query를 반영).
  Widget _buildSearchOverlay() {
    return AnimatedSlide(
      offset: _searchOverlayOpen ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !_searchOverlayOpen,
        child: ColoredBox(
          color: const Color(0xFF0D0D0C),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchField(),
                  const SizedBox(height: 24),
                  if (_recentSearches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '최근 검색어가 없어요',
                        style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.5)),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Text(
                          '최근 검색어',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory.withOpacity(0.85)),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _clearRecentSearches,
                          child: Text(
                            '전체 삭제',
                            style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.5)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _recentSearches.length,
                        itemBuilder: (context, index) {
                          final query = _recentSearches[index];
                          return _RecentSearchRow(
                            query: query,
                            onTap: () => _submitSearch(query),
                            onRemove: () => _removeRecentSearch(query),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
        focusNode: _searchFocusNode,
        textInputAction: TextInputAction.search,
        onSubmitted: _submitSearch,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '제목 또는 작가로 검색',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: _ivory.withOpacity(0.60), size: 20),
          suffixIcon: IconButton(
            onPressed: _closeSearchOverlay,
            icon: Icon(Icons.close_rounded, color: _ivory.withOpacity(0.60), size: 20),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        ),
      ),
    );
  }

  /// 검색 중이 아닐 때 보여주는 섹션들 — 히어로 배너(있으면) + 실시간 랭킹 +
  /// 장르별 진열 행, 이 순서로 세로로 쌓인다(모바일/데스크톱 둘 다 같은
  /// 순서 — 예전엔 데스크톱에서 랭킹이 배너 옆 오른쪽 사이드바였는데, 그
  /// 2fr/1fr 분할을 걷어내고 랭킹도 장르 행처럼 전체 폭을 쓰는 독립 섹션으로
  /// 바꿨다). genres 컬렉션(sortOrder 순)을 기준으로 행을 만들고, 팩이 속한
  /// 모든 장르 행에 그 팩이 나타난다 — 대표 장르 하나만 보여주던 예전과
  /// 달리, 장르 우선 탐색이라 다장르 팩도 각 장르 행에서 다 찾을 수 있어야
  /// 한다. 장르가 하나도 없는 팩은 "기타" 행으로 모은다. 팩이 하나도 없는
  /// 장르 행은 통째로 숨긴다.
  ///
  /// 장르 행 내부 레이아웃(가로 스크롤 vs 6열 그리드)만 폭 600px 기준으로
  /// 갈린다(storyGridWideBreakpoint, 내 서재와 공유하는 값) —
  /// doc/home_*_mockup.html 참고.
  Widget _buildBrowseSections(List<StoryPack> packs) {
    if (packs.isEmpty) {
      return Center(
        child: Text(
          '아직 연재 중인 스토리가 없어요',
          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
        ),
      );
    }

    return StreamBuilder<List<Genre>>(
      stream: _genresStream,
      builder: (context, genreSnapshot) {
        final genres = genreSnapshot.data ?? const <Genre>[];

        return StreamBuilder<List<HomeBanner>>(
          stream: _bannersStream,
          builder: (context, bannerSnapshot) {
            if (bannerSnapshot.hasError) {
              // 조용히 삼키고 "배너 없음"과 구분 안 되게 두면 안 된다 —
              // pack_comments_section.dart/pack_reviews_section.dart와 같은
              // 이유로, 규칙/색인 미배포 같은 실제 쿼리 실패가 화면에서도
              // 콘솔에서도 안 보이게 되는 걸 막는다.
              debugPrint('홈 배너 목록 불러오기 실패: ${bannerSnapshot.error}');
            }
            final banners = bannerSnapshot.data ?? const <HomeBanner>[];

            return FutureBuilder<RankingSnapshotPair>(
              future: _rankingFuture,
              builder: (context, rankingSnapshot) {
                final ranking = rankingSnapshot.data ?? RankingSnapshotPair.empty;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= storyGridWideBreakpoint;

                    // width: double.infinity로 명시해서, Column의
                    // crossAxisAlignment.start 아래에서도 장르 행/랭킹과
                    // 같은 폭으로 정확히 늘어나게 한다.
                    final bannerWidget = SizedBox(
                      width: double.infinity,
                      child: bannerSnapshot.hasError
                          ? const _HeroBannerErrorNotice()
                          : HeroBannerSection(
                        banners: banners,
                        allPacks: packs,
                        aspectRatio: isWide ? 21 / 6 : 16 / 6,
                        showArrowsOnHoverOnly: isWide,
                      ),
                    );
                    final rankingWidget = RankingSection(
                      snapshot: ranking,
                      allPacks: packs,
                      genres: genres,
                    );
                    final genreRows = _buildGenreRows(packs, genres, isWide: isWide);

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      children: [
                        bannerWidget,
                        const SizedBox(height: 24),
                        rankingWidget,
                        const SizedBox(height: 24),
                        ...genreRows,
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  List<Widget> _buildGenreRows(List<StoryPack> packs, List<Genre> genres, {required bool isWide}) {
    final rows = <Widget>[];
    final assignedPackIds = <String>{};
    var isFirstRow = true;

    for (final genre in genres) {
      final packsInGenre = packs.where((pack) => pack.genres.contains(genre.slug)).toList();
      if (packsInGenre.isEmpty) continue;
      assignedPackIds.addAll(packsInGenre.map((p) => p.id));

      if (!isFirstRow) rows.add(const SizedBox(height: 22));
      isFirstRow = false;
      rows.addAll(_buildGenreRow(genre.name, packsInGenre, isWide));
    }

    final unassigned = packs.where((pack) => !assignedPackIds.contains(pack.id)).toList();
    if (unassigned.isNotEmpty) {
      if (!isFirstRow) rows.add(const SizedBox(height: 22));
      rows.addAll(_buildGenreRow('기타', unassigned, isWide));
    }

    return rows;
  }

  List<Widget> _buildGenreRow(String title, List<StoryPack> packs, bool isWide) {
    return [
      _buildSectionTitle(title),
      const SizedBox(height: 10),
      isWide ? _buildGenreGrid(packs) : _buildHorizontalPackRow(packs),
      const SizedBox(height: 10),
      const ShelfLedgeDivider(),
    ];
  }

  /// font-voice(세리프) 폰트가 아직 번들되어 있지 않아, 헤더 워드마크와
  /// 같은 굵기/자간 조합으로 "같은 서체 목소리"를 흉내낸다 — 세리프 폰트가
  /// 생기면 fontFamily만 바꾸면 된다.
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: _ivory,
        letterSpacing: 0.4,
      ),
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
          child: StoryCoverCard(pack: packs[index], showGenreTag: false),
        ),
      ),
    );
  }

  /// 데스크톱 목업(home_desktop_mockup.html)의 장르 행 — 6열 그리드로 한
  /// 화면에 더 많이 보여준다. 가로 스크롤 행과 같은 StoryCoverCard를 그대로
  /// 쓰고, 그리드 배치도 내 서재(my_library_tab.dart)와 storyCoverGridDelegate
  /// 하나를 공유한다 — 두 화면이 각자 숫자를 들고 있다가 어긋났던 문제의
  /// 재발을 막는다. showGenreTag만 끄고 showPriceRow는 기본값(true) 그대로
  /// 둔다 — 내 서재도 이제 같은 기본값을 쓰므로 두 화면의 카드가 텍스트
  /// 줄 수까지 완전히 같다.
  Widget _buildGenreGrid(List<StoryPack> packs) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: packs.length,
      gridDelegate: storyCoverGridDelegate(crossAxisCount: 6),
      itemBuilder: (context, index) => StoryCoverCard(pack: packs[index], showGenreTag: false),
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
      itemBuilder: (context, index) => StoryCoverCard(pack: packs[index]),
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

class _RecentSearchRow extends StatelessWidget {
  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentSearchRow({required this.query, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 16, color: _ivory.withOpacity(0.45)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.9)),
              ),
            ),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: _ivory.withOpacity(0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 히어로 배너 쿼리가 실패했을 때(규칙/색인 미배포 등)의 표시 — 배너가
/// 그냥 없는 것과 구분되게 눈에 띄는 자리에 보여준다. 장식용 섹션이라
/// PackCommentsSection처럼 "다시 시도" 버튼까지는 두지 않는다(다음 홈 진입
/// 때 새 구독이 다시 시도한다).
class _HeroBannerErrorNotice extends StatelessWidget {
  const _HeroBannerErrorNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent.withOpacity(0.85)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '배너를 불러오지 못했어요.',
              style: TextStyle(fontSize: 12.5, color: Colors.redAccent.withOpacity(0.85)),
            ),
          ),
        ],
      ),
    );
  }
}