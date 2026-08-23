import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ads/ad_ids.dart';
import '../data/genre_repository.dart';
import '../data/home_banner_repository.dart';
import '../data/home_event_repository.dart';
import '../data/pack_bundle_repository.dart';
import '../data/ranking_repository.dart';
import '../data/story_pack_repository.dart';
import '../models/genre.dart';
import '../models/home_banner.dart';
import '../models/home_event.dart';
import '../models/pack_bundle.dart';
import '../models/ranking_snapshot.dart';
import '../models/story_pack.dart';
import '../widgets/bundle_card.dart';
import '../widgets/catalog_desktop_nav_bar.dart';
import '../widgets/desktop_ranking_list.dart';
import '../widgets/hero_banner_section.dart';
import '../widgets/home_desktop_layout.dart';
import '../widgets/home_event_dialog.dart';
import '../widgets/ranking_section.dart';
import '../widgets/shelf_ledge_divider.dart';
import '../widgets/story_cover_card.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 최근 검색어를 저장하는 SharedPreferences 키 — 계정이 아니라 기기에
/// 묶인 단순한 로컬 목록이다.
const String _recentSearchesPrefsKey = 'home_recent_searches';
const int _maxRecentSearches = 10;

/// 하단 탭의 "홈" — 이야기 팩을 둘러보고 검색하는 화면. 히어로 배너 +
/// 실시간 랭킹 + 번들 상품 + 장르별 진열 행. 공지사항은 별도 탭이다.
///
/// 데스크톱 폭([homeDesktopBreakpoint] 이상)에서 달라지는 것:
/// - 로고 / 탭 / 검색창 / 충전 버튼은 전부 셸의 [CatalogDesktopNavBar]가
///   갖는다. 이 화면은 본문만 그린다(예전엔 검색·충전이 본문 맨 위에 있어서
///   배너 위에 떠 있는 것처럼 보였다).
/// - 배너 + 번들 상품(왼쪽) / 랭킹(오른쪽 320px) 2단 — [HomeTopSections].
/// - 랭킹은 [DesktopRankingList](한 줄 목록). 모바일은 기존
///   [RankingSection](TOP3 카드 + 목록) 그대로다.
class HomeTab extends StatefulWidget {
  /// 웹에서 author/admin 계정으로 열었을 때만 true.
  final bool showAuthorModeLink;

  /// 스토리팩 스트림이 첫 스냅샷(데이터든 에러든)을 내놓는 순간 한 번만
  /// 호출된다 — MainPage의 부트스트랩 로딩 오버레이를 걷어내는 신호.
  final VoidCallback? onContentReady;

  /// 데스크톱 상단 바의 검색창이 확정한 검색어. 셸이 소유하고 이 화면은
  /// 구독만 한다 — null이면(모바일) 이 화면 안의 검색 오버레이를 쓴다.
  final ValueNotifier<String>? externalQuery;

  const HomeTab({
    super.key,
    this.showAuthorModeLink = false,
    this.onContentReady,
    this.externalQuery,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';

  bool _searchOverlayOpen = false;
  List<String> _recentSearches = [];

  bool _reportedContentReady = false;

  final StoryPackRepository _packRepository = StoryPackRepository();
  late final Stream<List<StoryPack>> _packsStream = _packRepository.watchVisiblePacks();

  final GenreRepository _genreRepository = GenreRepository();
  late final Stream<List<Genre>> _genresStream = _genreRepository.watchActiveGenres();

  final HomeBannerRepository _bannerRepository = HomeBannerRepository();
  late final Stream<List<HomeBanner>> _bannersStream = _bannerRepository.watchActiveBanners();

  final PackBundleRepository _bundleRepository = PackBundleRepository();
  late final Stream<List<PackBundle>> _bundlesStream = _bundleRepository.watchActiveBundles();

  final RankingRepository _rankingRepository = RankingRepository();
  late final Future<RankingSnapshotPair> _rankingFuture = _rankingRepository.fetchLatest();

  final HomeEventRepository _eventRepository = HomeEventRepository();
  late final Stream<List<HomeEvent>> _eventsStream = _eventRepository.watchActiveEvents();

  // 이벤트 팝업은 홈 탭이 열릴 때 딱 한 번만 띄운다("오늘 이미 봤는지"는
  // HomeEventDismissalStore가 따로 판단) — 두 스트림(팩 목록, 활성 이벤트
  // 목록)이 둘 다 첫 데이터를 내놓은 뒤에만 트리거한다. linkedPackId를
  // 실제 StoryPack으로 찾으려면 팩 목록이 먼저 준비돼 있어야 하고, 어느
  // 쪽이 먼저 도착하든 상관없이 나중에 도착하는 쪽에서 조건이 채워지면
  // 바로 띄워야 하므로, 두 스트림의 builder 양쪽에서 같은 트리거 메서드를
  // 부른다.
  bool _homeEventPopupTriggered = false;
  List<StoryPack> _latestPacks = const <StoryPack>[];
  List<HomeEvent>? _latestEvents;

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadRecentSearches();
    widget.externalQuery?.addListener(_handleExternalQuery);
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalQuery != widget.externalQuery) {
      oldWidget.externalQuery?.removeListener(_handleExternalQuery);
      widget.externalQuery?.addListener(_handleExternalQuery);
    }
  }

  /// 데스크톱 상단 바에서 검색어가 확정되면 이 화면의 _query에 반영한다 —
  /// 그 뒤 흐름(브라우즈 → 검색 결과 전환, 최근 검색어 적립)은 모바일과
  /// 완전히 같은 경로를 탄다.
  void _handleExternalQuery() {
    final query = widget.externalQuery?.value ?? '';
    if (query == _query) return;
    _submitSearch(query);
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // `?? const []`이면 이후 첫 검색에서 _recentSearches.remove(...)가
      // "Unsupported operation: remove"로 터진다 — const 리스트는 불변이다.
      final saved = prefs.getStringList(_recentSearchesPrefsKey);
      final growable = saved == null ? <String>[] : List<String>.of(saved);
      if (mounted) setState(() => _recentSearches = growable);
    } catch (_) {
      // 저장소 접근이 막힌 환경이어도 검색 자체는 계속 동작해야 한다.
    }
  }

  Future<void> _persistRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentSearchesPrefsKey, _recentSearches);
    } catch (_) {
      // 이번 세션 안에서는 여전히 동작하니 저장 실패만 조용히 넘어간다.
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

  /// 로고 탭 / 검색 결과 뒤로가기 / 기기 뒤로가기, 셋 다 여기로 모인다.
  void goHome() {
    if (!_searchOverlayOpen && _query.isEmpty) return;
    setState(() {
      _searchOverlayOpen = false;
      _query = '';
    });
    _searchController.clear();
    _searchFocusNode.unfocus();
    widget.externalQuery?.value = '';
  }

  void _maybeReportContentReady(AsyncSnapshot<List<StoryPack>> snapshot) {
    if (_reportedContentReady) return;
    if (snapshot.connectionState == ConnectionState.waiting) return;
    _reportedContentReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onContentReady?.call());
  }

  /// [_latestPacks]/[_latestEvents]가 둘 다 채워진 뒤 딱 한 번만 실행된다 —
  /// 실제로 "봤는지" 판단(하루 한 번/다시 보지 않기)은
  /// showHomeEventPopupIfNeeded 안에서 한다. 여러 이벤트가 동시에 활성
  /// 상태여도 _eventsStream이 이미 sortOrder 순으로 걸러 주므로 첫 번째만
  /// 쓴다(HomeEventRepository.watchActiveEvents 참고).
  void _maybeTriggerHomeEventPopup() {
    if (_homeEventPopupTriggered) return;
    if (!_reportedContentReady) return;
    final events = _latestEvents;
    if (events == null) return;
    _homeEventPopupTriggered = true;

    final event = events.isEmpty ? null : events.first;
    if (event == null) return;
    final packs = _latestPacks;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(showHomeEventPopupIfNeeded(context: context, event: event, allPacks: packs));
    });
  }

  /// 검색어를 확정한다 — 모바일 오버레이의 엔터/최근 검색어 탭, 데스크톱
  /// 상단 바의 엔터가 모두 이 경로를 탄다.
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
    // google_mobile_ads는 Flutter Web을 지원하지 않는다 — 웹에서
    // BannerAd.load()를 부르면 MissingPluginException이 던져진다. 모바일에서만
    // 배너를 요청한다.
    if (kIsWeb) return;

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
    // load() 자체가 던지는 예외(플러그인 미구현, 채널 오류)는
    // onAdFailedToLoad에 닿지 않고 Future 실패로만 나타나므로 반드시
    // catchError로 삼켜야 다른 화면에 영향을 주지 않는다.
    bannerAd.load().catchError((Object error, StackTrace stackTrace) {
      debugPrint('배너 광고 로드 실패(예외): $error');
      _bannerAd = null;
    });
  }

  @override
  void dispose() {
    widget.externalQuery?.removeListener(_handleExternalQuery);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // CatalogShellPage가 유일한 Scaffold를 갖고, 각 탭은 body 콘텐츠만
    // 반환한다 — 탭마다 Scaffold를 중첩하지 않는다.
    final searchActive = _searchOverlayOpen || _query.isNotEmpty;
    final isDesktop = MediaQuery.sizeOf(context).width >= homeDesktopBreakpoint;

    // 22px은 모바일 기준값이라 1440px 화면에서는 콘텐츠가 화면 끝에 붙어
    // 보인다.
    final horizontalPadding = isDesktop ? 40.0 : 22.0;

    return PopScope(
      canPop: !searchActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        goHome();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, isDesktop ? 28 : 16, horizontalPadding, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 데스크톱에서는 로고/검색/충전이 전부 상단 내비바로
                    // 올라갔다 — 여기엔 아무 헤더 줄도 두지 않는다.
                    if (!isDesktop) _buildMobileTopRow(),
                    _buildBannerAd(),
                    Expanded(
                      child: StreamBuilder<List<StoryPack>>(
                        stream: _packsStream,
                        builder: (context, snapshot) {
                          _maybeReportContentReady(snapshot);
                          if (snapshot.hasError) {
                            // 화면엔 "불러오지 못했어요"만 보이고 진짜 원인이
                            // 사라지지 않게 실제 예외를 콘솔에 남긴다.
                            debugPrint('스토리팩 스트림 에러: ${snapshot.error}\n${snapshot.stackTrace}');
                            return Center(
                              child: Text(
                                '스토리팩 목록을 불러오지 못했어요',
                                style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
                              ),
                            );
                          }

                          final packs = snapshot.data ?? const <StoryPack>[];
                          _latestPacks = packs;
                          _maybeTriggerHomeEventPopup();
                          final trimmedQuery = _query.trim();
                          final query = trimmedQuery.toLowerCase();
                          final filteredPacks = query.isEmpty
                              ? packs
                              : packs
                                  .where((pack) =>
                                      pack.title.toLowerCase().contains(query) ||
                                      pack.authorName.toLowerCase().contains(query))
                                  .toList();

                          if (query.isEmpty) {
                            return _buildBrowseSections(packs, isDesktop: isDesktop);
                          }
                          return _buildSearchResults(trimmedQuery, filteredPacks);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 데스크톱은 상단 바 입력창이 검색을 맡으므로 오버레이를 트리에
            // 넣지 않는다(닫힌 상태로 남겨두면 포커스를 가져갈 수 있다).
            if (!isDesktop) Positioned.fill(child: _buildSearchOverlay()),
            // 화면에 아무 것도 안 그리는 구독 전용 위젯 — _eventsStream의
            // 첫 데이터를 _latestEvents에 담아 _maybeTriggerHomeEventPopup을
            // 부른다(실제 팝업은 showHomeEventPopupIfNeeded가 별도
            // showDialog로 띄운다).
            StreamBuilder<List<HomeEvent>>(
              stream: _eventsStream,
              builder: (context, snapshot) {
                _latestEvents = snapshot.data;
                _maybeTriggerHomeEventPopup();
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 모바일 헤더 줄 — 로고 + 충전 버튼 + 검색 아이콘(오버레이를 연다).
  Widget _buildMobileTopRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: goHome,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ForkingPathLogoMark(size: 40),
                SizedBox(width: 12),
                TeloWordmark(fontSize: 24),
              ],
            ),
          ),
          const Spacer(),
          const CoinChargeButton(),
          const SizedBox(width: 8),
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

  /// 모바일 전용 전체 화면 검색 — 위에 입력, 아래에 최근 검색어.
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

  /// 검색 중이 아닐 때 보여주는 섹션들 — 상단 세 섹션의 배치는
  /// [HomeTopSections]가, 장르 행은 전체 폭이 맡는다.
  ///
  /// genres 컬렉션(sortOrder 순)을 기준으로 행을 만들고, 팩이 속한 모든 장르
  /// 행에 그 팩이 나타난다. 장르가 하나도 없는 팩은 "기타" 행으로 모은다.
  /// 팩이 하나도 없는 장르 행은 통째로 숨긴다.
  Widget _buildBrowseSections(List<StoryPack> packs, {required bool isDesktop}) {
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
              // 규칙/색인 미배포 같은 실제 쿼리 실패가 화면에서도 콘솔에서도
              // 안 보이게 되는 걸 막는다.
              debugPrint('홈 배너 목록 불러오기 실패: ${bannerSnapshot.error}');
            }
            final banners = bannerSnapshot.data ?? const <HomeBanner>[];

            return FutureBuilder<RankingSnapshotPair>(
              future: _rankingFuture,
              builder: (context, rankingSnapshot) {
                if (rankingSnapshot.hasError) {
                  debugPrint('[랭킹] _rankingFuture 에러: ${rankingSnapshot.error}\n${rankingSnapshot.stackTrace}');
                }
                final ranking = rankingSnapshot.data ?? RankingSnapshotPair.empty;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= storyGridWideBreakpoint;

                    // ⚠️ 배너를 FractionallySizedBox나 max-width로 좁히지
                    // 않는다 — 폭은 HomeTopSections가 정한다. 데스크톱에서
                    // 배너만 좁히면 바로 아래 번들 상품 행과 오른쪽 끝이
                    // 어긋나 배너 옆에 검은 빈 칸이 생긴다. "작아 보이게"는
                    // 비율(homeDesktopBannerAspect)로만 한다.
                    final bannerWidget = bannerSnapshot.hasError
                        ? const _HeroBannerErrorNotice()
                        : HeroBannerSection(
                            banners: banners,
                            allPacks: packs,
                            aspectRatio: isDesktop ? homeDesktopBannerAspect : 16 / 6,
                            showArrowsOnHoverOnly: isWide,
                          );

                    final rankingWidget = isDesktop
                        ? DesktopRankingList(
                            snapshot: ranking,
                            allPacks: packs,
                            genres: genres,
                          )
                        : Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: RankingSection(
                              snapshot: ranking,
                              allPacks: packs,
                              genres: genres,
                            ),
                          );

                    final genreRows = _buildGenreRows(packs, genres, isWide: isWide);

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      children: [
                        HomeTopSections(
                          isDesktop: isDesktop,
                          banner: bannerWidget,
                          ranking: rankingWidget,
                          bundles: _buildBundleSection(packs),
                        ),
                        const SizedBox(height: 24),
                        const ShelfLedgeDivider(),
                        const SizedBox(height: 22),
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

  /// "번들 상품" — active 번들이 하나라도 있을 때만 나타나는 가로 스크롤
  /// 섹션.
  Widget _buildBundleSection(List<StoryPack> packs) {
    return StreamBuilder<List<PackBundle>>(
      stream: _bundlesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('번들 목록 불러오기 실패: ${snapshot.error}');
          return const SizedBox.shrink();
        }
        final bundles = snapshot.data ?? const <PackBundle>[];
        if (bundles.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('번들 상품'),
            const SizedBox(height: 10),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bundles.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    BundleCard(bundle: bundles[index], allPacks: packs),
              ),
            ),
          ],
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
    // 카드 폭에서 공용 비율(storyCoverAspectRatio)로 이미지 높이를 역산한다.
    const cardWidth = 118.0;
    const textAreaHeight = 44.0;
    final cardHeight = cardWidth / storyCoverAspectRatio + textAreaHeight;

    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: packs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => SizedBox(
          width: cardWidth,
          child: StoryCoverCard(pack: packs[index]),
        ),
      ),
    );
  }

  /// 넓은 폭의 장르 행 — storyCoverGridDelegate()가 maxCrossAxisExtent(150)로
  /// 열 개수를 정하므로 1440px에서는 9열쯤으로 떨어진다. 내 서재와 같은
  /// delegate를 공유해 카드 크기가 앱 전체에서 하나로 통일된다.
  Widget _buildGenreGrid(List<StoryPack> packs) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: packs.length,
      gridDelegate: storyCoverGridDelegate(),
      itemBuilder: (context, index) => StoryCoverCard(pack: packs[index]),
    );
  }

  Widget _buildPackGrid(List<StoryPack> packs) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: packs.length,
      gridDelegate: storyCoverGridDelegate(),
      itemBuilder: (context, index) => StoryCoverCard(pack: packs[index]),
    );
  }

  Widget _buildSearchResults(String query, List<StoryPack> filteredPacks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: goHome,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_back_rounded, color: _ivory.withOpacity(0.85), size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "'$query' 검색 결과",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ivory),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filteredPacks.isEmpty ? _buildEmptyResult() : _buildPackGrid(filteredPacks),
        ),
      ],
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
/// 그냥 없는 것과 구분되게 보여준다.
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
