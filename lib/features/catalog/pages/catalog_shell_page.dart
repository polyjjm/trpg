import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../reader/shared/data/reader_prefs_repository.dart';
import '../data/notice_repository.dart';
import '../widgets/catalog_desktop_nav_bar.dart';
import '../widgets/home_desktop_layout.dart';
import 'home_tab.dart';
import 'my_library_tab.dart';
import 'notice_list_tab.dart';
import 'settings_tab.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 로그인 직후 항상 이 화면으로 들어온다 — 탭(홈/내 서재/공지사항/설정)을
/// 가진 라이브러리 셸. 각 탭은 IndexedStack으로 유지해 탭을 오갈 때 스크롤
/// 위치와 상태(검색어, 배너 로드 등)가 보존된다.
///
/// 내비게이션 위치는 폭으로 갈린다:
/// - 좁은 폭: 기존 하단 탭바([_CatalogBottomNav]). Material의 기본
///   NavigationBar 대신 직접 만든 것을 쓴다 — 이 앱은 커스텀 골드/아이보리
///   팔레트를 쓰고 Material3 colorScheme을 별도로 설정하지 않아서, 기본
///   NavigationBar를 그대로 쓰면 엉뚱한 기본 보라색 계열로 나온다.
/// - 데스크톱 폭([homeDesktopBreakpoint] 이상): 화면 맨 위의
///   [CatalogDesktopNavBar]. 검색창과 코인/충전 버튼도 여기로 올라간다.
///
/// 데스크톱 검색창은 이 셸이 소유한다([_searchController],
/// [_desktopQuery]) — 입력창은 상단 바에, 결과는 홈 탭 안에 있어서 둘을
/// 잇는 값이 두 위젯 위쪽에 있어야 한다. 홈 탭은 [_desktopQuery]를 구독만
/// 하고, 확정된 검색어를 자기 검색 경로에 그대로 흘려 넣는다.
class CatalogShellPage extends StatefulWidget {
  /// 웹에서 author/admin 계정으로 열었을 때만 true — 홈 탭에만 전달된다.
  final bool showAuthorModeLink;

  /// 홈 탭의 스토리팩 스트림이 첫 스냅샷(데이터든 에러든)을 내놓는 순간 한
  /// 번만 불린다 — MainPage가 이 콜백을 받아서야 부트스트랩 로딩 오버레이를
  /// 걷어낸다.
  final VoidCallback? onContentReady;

  const CatalogShellPage({super.key, this.showAuthorModeLink = false, this.onContentReady});

  @override
  State<CatalogShellPage> createState() => _CatalogShellPageState();
}

class _CatalogShellPageState extends State<CatalogShellPage> {
  int _index = 0;

  final NoticeRepository _noticeRepository = NoticeRepository();
  final ReaderPrefsRepository _readerPrefsRepository = ReaderPrefsRepository();
  late final Stream<DateTime?> _latestNoticeAtStream = _noticeRepository.watchLatestNoticeAt();

  // 데스크톱 상단 바 검색 — 입력 상태와 확정된 검색어를 셸이 들고 있는다.
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<String> _desktopQuery = ValueNotifier<String>('');

  // AuthScope.of(context)는 initState에서 부르면 안 되는 타이밍이라(아직
  // InheritedWidget 의존성 등록 전) — StoryPackDetailPage의 _resolvedProgress와
  // 같은 가드 패턴으로 didChangeDependencies에서 딱 한 번만 uid를 정한다.
  bool _resolvedAuth = false;
  String? _uid;
  Stream<DateTime?> _lastNoticeReadAtStream = Stream<DateTime?>.value(null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedAuth) return;
    _resolvedAuth = true;
    _uid = AuthScope.of(context).userId;
    final uid = _uid;
    if (uid != null) {
      _lastNoticeReadAtStream = _readerPrefsRepository.watch(uid).map((prefs) => prefs.lastNoticeReadAt);
    }
    // 게스트(uid == null)는 서버에 읽음 상태를 남길 계정이 없다 — 공지가
    // 하나라도 있으면 항상 안 읽음으로 취급한다.
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _desktopQuery.dispose();
    super.dispose();
  }

  /// 공지사항 탭(인덱스 2)으로 전환하는 순간 lastNoticeReadAt을 갱신한다.
  /// 이 탭은 IndexedStack 안에 항상 마운트돼 있어서 NoticeListTab의
  /// initState/didChangeDependencies로는 "실제로 열었을 때"를 알 수 없다
  /// — 인덱스가 바뀌는 이 지점이 유일하게 정확한 "탭을 열었다" 신호다.
  void _handleNavChanged(int index) {
    setState(() => _index = index);
    final uid = _uid;
    if (index == 2 && uid != null) {
      _readerPrefsRepository.markNoticesRead(uid);
    }
  }

  /// 상단 바 로고 탭 — 홈 탭으로 돌아가고 검색을 접는다.
  void _handleLogoTap() {
    _searchController.clear();
    _desktopQuery.value = '';
    if (_index != 0) _handleNavChanged(0);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= homeDesktopBreakpoint;

    final tabs = IndexedStack(
      index: _index,
      children: [
        HomeTab(
          showAuthorModeLink: widget.showAuthorModeLink,
          onContentReady: widget.onContentReady,
          externalQuery: isDesktop ? _desktopQuery : null,
        ),
        const MyLibraryTab(),
        NoticeListTab(),
        const SettingsTab(),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: isDesktop
          ? _UnreadNoticeBuilder(
              latestNoticeAtStream: _latestNoticeAtStream,
              lastNoticeReadAtStream: _lastNoticeReadAtStream,
              builder: (context, hasUnreadNotice) => Column(
                children: [
                  CatalogDesktopNavBar(
                    index: _index,
                    onChanged: _handleNavChanged,
                    hasUnreadNotice: hasUnreadNotice,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onSearchSubmitted: (query) => _desktopQuery.value = query,
                    onLogoTap: _handleLogoTap,
                  ),
                  Expanded(child: tabs),
                ],
              ),
            )
          : tabs,
      bottomNavigationBar: isDesktop
          ? null
          : _UnreadNoticeBuilder(
              latestNoticeAtStream: _latestNoticeAtStream,
              lastNoticeReadAtStream: _lastNoticeReadAtStream,
              builder: (context, hasUnreadNotice) => _CatalogBottomNav(
                index: _index,
                onChanged: _handleNavChanged,
                hasUnreadNotice: hasUnreadNotice,
              ),
            ),
    );
  }
}

/// "안 읽은 공지가 있는지"를 계산해 넘겨주는 래퍼 — 최신 공지 시각과 마지막
/// 읽음 시각, 두 스트림을 겹쳐 봐야 알 수 있다. 하단 탭바와 데스크톱 상단
/// 내비바가 같은 판단을 써야 하므로 위젯으로 뽑았다(예전엔
/// bottomNavigationBar 안에 이중 StreamBuilder로 인라인되어 있었다).
class _UnreadNoticeBuilder extends StatelessWidget {
  final Stream<DateTime?> latestNoticeAtStream;
  final Stream<DateTime?> lastNoticeReadAtStream;
  final Widget Function(BuildContext context, bool hasUnreadNotice) builder;

  const _UnreadNoticeBuilder({
    required this.latestNoticeAtStream,
    required this.lastNoticeReadAtStream,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime?>(
      stream: latestNoticeAtStream,
      builder: (context, latestSnapshot) {
        return StreamBuilder<DateTime?>(
          stream: lastNoticeReadAtStream,
          builder: (context, readSnapshot) {
            final latest = latestSnapshot.data;
            final lastRead = readSnapshot.data;
            final hasUnreadNotice = latest != null && (lastRead == null || latest.isAfter(lastRead));
            return builder(context, hasUnreadNotice);
          },
        );
      },
    );
  }
}

class _CatalogBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final bool hasUnreadNotice;

  const _CatalogBottomNav({
    required this.index,
    required this.onChanged,
    required this.hasUnreadNotice,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.10))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavItem(icon: Icons.home_rounded, label: '홈', selected: index == 0, onTap: () => onChanged(0)),
            _NavItem(icon: Icons.bookmark_rounded, label: '내 서재', selected: index == 1, onTap: () => onChanged(1)),
            _NavItem(
              icon: Icons.campaign_rounded,
              label: '공지사항',
              selected: index == 2,
              onTap: () => onChanged(2),
              showBadge: hasUnreadNotice,
            ),
            _NavItem(icon: Icons.settings_rounded, label: '설정', selected: index == 3, onTap: () => onChanged(3)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showBadge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? _gold : _ivory.withOpacity(0.55);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 22),
                if (showBadge)
                  Positioned(
                    right: -3,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF141414), width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
