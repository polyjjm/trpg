import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ads/ad_ids.dart';
import '../../../core/auth/auth_scope.dart';
import '../../../core/constants/external_links.dart';
import '../../../core/platform/open_external_link.dart';
import '../../../core/state/game_state_scope.dart';
import '../../wallet/data/wallet_repository.dart';
import '../../wallet/pages/charge_page.dart';
import '../data/genre_repository.dart';
import '../data/home_banner_repository.dart';
import '../data/pack_bundle_repository.dart';
import '../data/ranking_repository.dart';
import '../data/story_pack_repository.dart';
import '../models/genre.dart';
import '../models/home_banner.dart';
import '../models/pack_bundle.dart';
import '../models/ranking_snapshot.dart';
import '../models/story_pack.dart';
import '../widgets/bundle_card.dart';
import '../widgets/hero_banner_section.dart';
import '../widgets/library_header.dart';
import '../widgets/ranking_section.dart';
import '../widgets/shelf_ledge_divider.dart';
import '../widgets/story_cover_card.dart';
import 'story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _coral = Color(0xFFFF6B4A);
const Color _amber = Color(0xFFFFB35C);

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

  /// 스토리팩 스트림이 첫 스냅샷(데이터든 에러든)을 내놓는 순간 한 번만
  /// 호출된다 — MainPage의 부트스트랩 로딩 오버레이를 걷어내는 신호로 쓴다.
  final VoidCallback? onContentReady;

  const HomeTab({super.key, this.showAuthorModeLink = false, this.onContentReady});

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

  /// widget.onContentReady를 딱 한 번만 부르기 위한 가드.
  bool _reportedContentReady = false;

  final StoryPackRepository _packRepository = StoryPackRepository();
  late final Stream<List<StoryPack>> _packsStream = _packRepository.watchVisiblePacks();

  final GenreRepository _genreRepository = GenreRepository();
  late final Stream<List<Genre>> _genresStream = _genreRepository.watchActiveGenres();

  final HomeBannerRepository _bannerRepository = HomeBannerRepository();
  late final Stream<List<HomeBanner>> _bannersStream = _bannerRepository.watchActiveBanners();

  final PackBundleRepository _bundleRepository = PackBundleRepository();
  late final Stream<List<PackBundle>> _bundlesStream = _bundleRepository.watchActiveBundles();

  final WalletRepository _walletRepository = WalletRepository();

  final RankingRepository _rankingRepository = RankingRepository();
  late final Future<RankingSnapshotPair> _rankingFuture = _rankingRepository.fetchLatest();

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadRecentSearches();
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

  /// 로고 탭 / 검색 결과 뒤로가기 / 기기 뒤로가기, 셋 다 여기로 모인다 —
  /// 검색 오버레이를 닫고 _query를 비워 _buildBrowseSections로 돌아간다.
  void _goHome() {
    if (!_searchOverlayOpen && _query.isEmpty) return;
    setState(() {
      _searchOverlayOpen = false;
      _query = '';
    });
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  /// MainPage의 부트스트랩 로딩 오버레이는 이 콜백이 불릴 때까지 계속
  /// 떠 있는다 — _packsStream이 첫 스냅샷(데이터든 에러든)을 내놓는 순간
  /// 딱 한 번만 부른다. addPostFrameCallback으로 미루는 이유는 이 메서드가
  /// StreamBuilder의 builder(=이 위젯의 build 도중) 안에서 호출되는데,
  /// widget.onContentReady가 상위(MainPage)의 setState를 곧바로 실행하면
  /// "build 도중 setState" 오류가 나기 때문이다.
  void _maybeReportContentReady(AsyncSnapshot<List<StoryPack>> snapshot) {
    if (_reportedContentReady) return;
    if (snapshot.connectionState == ConnectionState.waiting) return;
    _reportedContentReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onContentReady?.call());
  }

  void _openChargePage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChargePage()),
    );
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
    // google_mobile_ads는 Flutter Web을 지원하지 않는다 — 웹에서 BannerAd.load()를
    // 부르면 이 메서드 채널에 대한 네이티브 구현 자체가 없어서(광고 요청 실패가
    // 아니라 플랫폼 미지원) MissingPluginException이 던져진다. 배너는 광고
    // 기능일 뿐 스토리팩 로딩과는 완전히 무관하니, 이 예외가 화면 어디에도
    // 영향을 주지 않게 하는 가장 확실한 방법은 애초에 웹에서 요청 자체를 안
    // 보내는 것이다 — 모바일에서만 배너를 요청한다.
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
    // onAdFailedToLoad는 네이티브 SDK가 실제로 응답한 뒤(네트워크 실패,
    // 노출할 광고 없음 등)에만 불린다 — load() 자체가 던지는 예외(예: 플러그인
    // 미구현, 채널 오류)는 그 콜백에 닿지 않고 Future 실패로만 나타나므로,
    // await 없이 fire-and-forget으로 던져 두더라도 반드시 catchError로 받아
    // 삼켜야 uncaught exception으로 새 나가 다른 화면(스토리팩 목록 등)에
    // 영향을 주는 일이 없다.
    bannerAd.load().catchError((Object error, StackTrace stackTrace) {
      debugPrint('배너 광고 로드 실패(예외): $error');
      _bannerAd = null;
    });
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
    // doc/home_*_mockup.html 기준, full-bleed).
    // ⚠️ 책장 일러스트 배경(assets/images/bookshelf_bg.png)은 완전히
    // 제거했다 — 실사용 기기에서 그 이미지 자리 전체가 검게 나오는 문제가
    // 있었고, 원인을 못 찾아 아예 헤더를 로고 + 충전 버튼 + 검색 아이콘만
    // 있는 플랫 배경으로 단순화했다(다시 넣으려면 이 주석 위치에 복원).
    // 검색 오버레이가 열려 있거나 검색 결과가 떠 있는 동안은 기기/브라우저
    // 뒤로가기를 가로채 _goHome()으로 보낸다 — 그렇지 않으면 뒤로가기가 이
    // 탭을 벗어나거나(라우트가 하나뿐이라 사실상 아무 반응도 안 함) 검색
    // 결과가 화면에 남은 채로 사용자가 나가는 길을 못 찾게 된다.
    final searchActive = _searchOverlayOpen || _query.isNotEmpty;

    return PopScope(
      canPop: !searchActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goHome();
      },
      child: Scaffold(
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
                          _buildLogo(),
                          const Spacer(),
                          _buildChargeButton(),
                          const SizedBox(width: 8),
                          _buildIconCircleButton(
                            icon: Icons.search_rounded,
                            onTap: _openSearchOverlay,
                          ),
                        ],
                      ),
                    ),
                    _buildBannerAd(),
                    Expanded(
                      child: StreamBuilder<List<StoryPack>>(
                        stream: _packsStream,
                        builder: (context, snapshot) {
                          _maybeReportContentReady(snapshot);
                          if (snapshot.hasError) {
                            // 화면에는 "불러오지 못했어요"만 보이고 진짜 원인(권한 거부,
                            // 색인 누락, 필드 타입 불일치 등)은 사라져 버리지 않게, 실제
                            // Firestore 예외를 콘솔에 그대로 남긴다.
                            debugPrint(
                              '스토리팩 스트림 에러: ${snapshot.error}\n${snapshot.stackTrace}',
                            );
                            return Center(
                              child: Text(
                                '스토리팩 목록을 불러오지 못했어요',
                                style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
                              ),
                            );
                          }

                          final packs = snapshot.data ?? const <StoryPack>[];
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
                            return _buildBrowseSections(packs);
                          }
                          return _buildSearchResults(trimmedQuery, filteredPacks);
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
      ),
    );
  }

  /// TELO 워드마크 — 코랄→앰버 그라데이션 텍스트 + 갈라지는 길(forking
  /// path) 로고 마크. 별도 에셋 없이 CustomPainter로 그려서 SVG 파일을
  /// 프로젝트에 추가하지 않아도 바로 동작한다. 탭하면 _goHome()으로 검색을
  /// 접고 브라우즈 화면으로 돌아간다 — 하단 탭바의 "홈"과 같은 화면(이 탭
  /// 자체)이라 별도 탭 전환은 필요 없다.
  Widget _buildLogo() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _goHome,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CustomPaint(painter: _ForkingPathLogoPainter()),
          ),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_coral, _amber],
            ).createShader(bounds),
            child: const Text(
              'TELO',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Colors.white, // ShaderMask가 이 색 위에 그라데이션을 입힌다
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChargeButton() {
    final uid = AuthScope.of(context).userId;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _openChargePage,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monetization_on_outlined, color: _amber, size: 16),
            const SizedBox(width: 5),
            // 게스트(uid 없음)는 지갑 자체가 없으니 그냥 "충전" 라벨로 둔다 —
            // 로그인 사용자만 users/{uid}/wallet/current 잔액을 실시간으로
            // 보여준다(ChargePage와 같은 WalletRepository 스트림).
            if (uid == null)
              Text(
                '충전',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory.withOpacity(0.9)),
              )
            else
              StreamBuilder<int>(
                stream: _walletRepository.watchBalance(uid),
                builder: (context, snapshot) {
                  final balance = snapshot.data;
                  return Text(
                    balance == null ? '충전' : '$balance',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory.withOpacity(0.9)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconCircleButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _ivory.withOpacity(0.85), size: 20),
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
                // ⚠️ 진단용 — 이 FutureBuilder는 원래 rankingSnapshot.hasError를
                // 전혀 확인하지 않고 곧바로 .data ?? RankingSnapshotPair.empty로
                // 넘어갔다(배너/번들 섹션과 달리 에러를 콘솔에 남기지도 않았다).
                // "랭킹 섹션이 안 보인다"는 신고가 실제로는 (a) 위 위젯이 아예
                // 안 그려지는 배선 문제인지, (b) 조용히 삼켜진 에러 때문인지,
                // (c) rankingSnapshots 문서가 오늘 날짜로 아직 없어서 정상적인
                // 빈 상태("아직 집계된 데이터가 없어요")로 그려진 건지 구분하기
                // 위한 로그다.
                debugPrint(
                  '[랭킹] FutureBuilder — connectionState=${rankingSnapshot.connectionState}, '
                  'hasError=${rankingSnapshot.hasError}, hasData=${rankingSnapshot.hasData}',
                );
                if (rankingSnapshot.hasError) {
                  debugPrint('[랭킹] _rankingFuture 에러: ${rankingSnapshot.error}\n${rankingSnapshot.stackTrace}');
                }
                final ranking = rankingSnapshot.data ?? RankingSnapshotPair.empty;
                debugPrint(
                  '[랭킹] 렌더링에 쓸 snapshot — today ${ranking.todayPackIds.length}개, '
                  'yesterday ${ranking.yesterdayPackIds.length}개'
                  '${rankingSnapshot.hasData ? '' : ' (실데이터 아님 — RankingSnapshotPair.empty 폴백)'}',
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= storyGridWideBreakpoint;

                    // 배너는 목업대로 화면 폭의 60%(좁은 화면에서는 88%)로
                    // 줄이고 가운데 정렬한다 — width: double.infinity로 꽉
                    // 채우던 걸 FractionallySizedBox로 감쌌다.
                    final bannerWidget = Center(
                      child: FractionallySizedBox(
                        widthFactor: isWide ? 0.6 : 0.88,
                        child: bannerSnapshot.hasError
                            ? const _HeroBannerErrorNotice()
                            : HeroBannerSection(
                          banners: banners,
                          allPacks: packs,
                          aspectRatio: isWide ? 21 / 6 : 16 / 6,
                          showArrowsOnHoverOnly: isWide,
                        ),
                      ),
                    );
                    final rankingWidget = Container(
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
                        // ⚠️ 진단용 — 배너 다시 켜서, 헤더(base64 빨간
                        // 사각형)랑 배너(Image.network)가 동시에 있을 때도
                        // 헤더가 계속 보이는지 재확인.
                        bannerWidget,
                        const SizedBox(height: 24),
                        rankingWidget,
                        const SizedBox(height: 24),
                        _buildBundleSection(packs),
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
  /// 섹션. 랭킹 섹션 바로 아래, 장르 행들 위에 얹는다. 스트림 에러는
  /// 히어로 배너와 같은 이유로 조용히 삼키지 않고 콘솔에 남긴다.
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
            const SizedBox(height: 10),
            const ShelfLedgeDivider(),
            const SizedBox(height: 22),
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
    // 카드 폭(118)에서 공용 비율(storyCoverAspectRatio)로 이미지 높이를
    // 역산한다 — 예전엔 여기 높이만 210으로 따로 하드코딩돼 있어서 그리드/
    // 검색 결과랑 비율이 달라 보였다. 텍스트(제목 한 줄 + 가격 줄) 높이는
    // StoryCoverCard 내부 고정값 기준으로 대략 44 정도 더해준다.
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

  /// 데스크톱 목업(home_desktop_mockup.html)의 장르 행 — 6열 그리드로 한
  /// 화면에 더 많이 보여준다. 가로 스크롤 행과 같은 StoryCoverCard를 그대로
  /// 쓰고, 그리드 배치도 내 서재(my_library_tab.dart)와 storyCoverGridDelegate
  /// 하나를 공유한다 — 두 화면이 각자 숫자를 들고 있다가 어긋났던 문제의
  /// 재발을 막는다. 검색 결과와 똑같이 장르 태그 뱃지도 보여준다(showGenreTag
  /// 기본값 true) — 예전엔 여기만 꺼놨는데, 그러면 검색 결과 카드보다
  /// 밋밋해 보여서 통일했다.
  Widget _buildGenreGrid(List<StoryPack> packs) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: packs.length,
      gridDelegate: storyCoverGridDelegate(),
      itemBuilder: (context, index) => StoryCoverCard(pack: packs[index]),
    );
  }

  /// 검색 결과 그리드 — 홈 장르 그리드·내 서재와 완전히 같은 카드 크기를
  /// 쓰도록 storyCoverGridDelegate()를 그대로 재사용한다. 예전엔 여기만
  /// childAspectRatio가 0.62로 달라서, 카드 폭(maxCrossAxisExtent)을
  /// 맞춰도 세로 비율이 달라 보이는 문제가 있었다.
  Widget _buildPackGrid(List<StoryPack> packs) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: packs.length,
      gridDelegate: storyCoverGridDelegate(),
      itemBuilder: (context, index) => StoryCoverCard(pack: packs[index]),
    );
  }

  /// 검색 결과 화면 — 뒤로 화살표 + "'검색어' 검색 결과" 헤더를 그리드/빈
  /// 결과 위에 얹는다. 로고 탭·기기 뒤로가기와 달리 이건 화면에 항상 보이는
  /// 명시적인 버튼이라, 검색 오버레이를 아예 안 거치고 곧장 여기로 들어온
  /// 사용자도 브라우즈 화면으로 돌아가는 길을 놓치지 않는다.
  Widget _buildSearchResults(String query, List<StoryPack> filteredPacks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _goHome,
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
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ivory),
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

/// TELO 로고 마크 — 갈라지는 길(forking path) 아이콘을 코랄→앰버 그라데이션
/// 스트로크로 그린다. 브랜치형 인터랙티브 픽션이라는 제품 정체성을 그대로
/// 반영한 형태라, 별도 SVG 에셋 없이 CustomPainter로 구현했다.
class _ForkingPathLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_coral, _amber],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.19, h * 0.19)
      ..lineTo(w * 0.19, h * 0.47)
      ..cubicTo(w * 0.19, h * 0.62, w * 0.34, h * 0.62, w * 0.34, h * 0.62)
      ..cubicTo(w * 0.5, h * 0.62, w * 0.5, h * 0.47, w * 0.66, h * 0.47)
      ..cubicTo(w * 0.81, h * 0.47, w * 0.81, h * 0.62, w * 0.81, h * 0.62)
      ..moveTo(w * 0.34, h * 0.62)
      ..lineTo(w * 0.34, h * 0.84)
      ..moveTo(w * 0.66, h * 0.47)
      ..lineTo(w * 0.66, h * 0.28);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..shader = const LinearGradient(colors: [_coral, _amber]).createShader(rect);
    canvas.drawCircle(Offset(w * 0.19, h * 0.14), size.width * 0.08, dotPaint);
    canvas.drawCircle(Offset(w * 0.66, h * 0.22), size.width * 0.08, dotPaint);
    canvas.drawCircle(Offset(w * 0.34, h * 0.9), size.width * 0.08, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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