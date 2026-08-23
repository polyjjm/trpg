import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/constants/external_links.dart';
import '../../../core/platform/open_external_link.dart';
import '../../wallet/data/wallet_repository.dart';
import '../../wallet/pages/charge_page.dart';
import 'home_desktop_layout.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _coral = Color(0xFFE2703A);
const Color _amber = Color(0xFFF2B33D);

/// 데스크톱 폭에서 하단 탭바(_CatalogBottomNav) 대신 화면 맨 위에 놓는
/// 가로 내비게이션 바.
///
/// 하단 탭바는 엄지로 누르는 모바일 관용구다 — 1440px 브라우저에서 그걸
/// 그대로 쓰면 화면 아래쪽에 붙은 아이콘 네 개만 남고 위쪽 폭이 비어서
/// "모바일 앱을 늘려놓은" 인상이 된다. 탭 세 개(홈/내 서재/공지사항)는
/// 그대로 두고 위치만 올린다 — "설정"은 여기 없다, 오른쪽 아바타
/// 드롭다운([_AccountAvatarMenu])으로 접었다(모바일 하단 탭바는 폭이 좁아
/// 아바타 드롭다운이 안 맞아서 예전 그대로 "설정" 탭을 유지한다 — 그래서
/// catalog_shell_page.dart의 IndexedStack은 여전히 4칸이고 SettingsTab도
/// 그대로 남아 있다, 데스크톱에서만 그 칸으로 가는 버튼이 없어졌을 뿐이다).
///
/// 검색 입력창과 코인/충전 버튼, 아바타 드롭다운도 이 바의 오른쪽에 놓는다
/// — 예전엔 홈 탭 본문 맨 위에 있어서 배너 위에 떠 있는 것처럼 보였다.
class CatalogDesktopNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final bool hasUnreadNotice;

  /// 홈 탭(index == 0)일 때만 검색창을 보여준다 — 다른 탭에서 검색해도
  /// 결과가 홈 탭 안에서만 뜨기 때문에, 그 탭에 있는 동안은 자리를 비운다.
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchSubmitted;

  /// 로고를 눌렀을 때 — 홈 탭으로 돌아가고 검색을 접는다.
  final VoidCallback onLogoTap;

  /// 웹에서 author/admin 계정으로 로그인했을 때만 true — 아바타 드롭다운의
  /// "작가 도구로" 항목을 보여줄지 결정한다. CatalogShellPage가 로그인
  /// 시점에 이미 한 번 계산해 둔 값을 그대로 받는다(hasUnreadNotice와 같은
  /// "부모가 계산해서 내려준다" 관례 — 이 바 자체는 Firestore를 직접 읽지
  /// 않는다).
  final bool showAuthorModeLink;

  /// 아바타 드롭다운의 "로그아웃" — 실제 로그아웃 처리(AuthScope.signOut() +
  /// 로그인 화면으로 스택 비우기)는 CatalogShellPage가 한다, onLogoTap과
  /// 같은 이유(이 바는 액션을 직접 실행하지 않고 콜백만 위로 올린다).
  final VoidCallback onSignOut;

  static const double height = 64;

  const CatalogDesktopNavBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.hasUnreadNotice,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchSubmitted,
    required this.onLogoTap,
    required this.showAuthorModeLink,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1C))),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onLogoTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ForkingPathLogoMark(size: 40),
                  SizedBox(width: 12),
                  TeloWordmark(fontSize: 24),
                ],
              ),
            ),
          ),
          const SizedBox(width: 34),
          _NavLink(label: '홈', selected: index == 0, onTap: () => onChanged(0)),
          const SizedBox(width: 26),
          _NavLink(
            label: '내 서재',
            selected: index == 1,
            onTap: () => onChanged(1),
          ),
          const SizedBox(width: 26),
          _NavLink(
            label: '공지사항',
            selected: index == 2,
            showBadge: hasUnreadNotice,
            onTap: () => onChanged(2),
          ),
          const Spacer(),
          if (index == 0) ...[
            DesktopSearchField(
              controller: searchController,
              focusNode: searchFocusNode,
              onSubmitted: onSearchSubmitted,
            ),
            const SizedBox(width: 10),
          ],
          const CoinChargeButton(),
          const SizedBox(width: 14),
          _AccountAvatarMenu(
            showAuthorModeLink: showAuthorModeLink,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showBadge;

  const _NavLink({
    required this.label,
    required this.selected,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? _coral : Colors.transparent,
                    width: 1.5,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? _ivory : _ivory.withOpacity(0.55),
                ),
              ),
            ),
            if (showBadge)
              Positioned(
                right: -8,
                top: -1,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF5252),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 데스크톱 상단 바에 상시 노출되는 검색 입력창 — 모바일의 전체 화면 검색
/// 오버레이(_buildSearchOverlay)를 대체한다. 제출은 같은 _submitSearch로
/// 들어간다. 최근 검색어 목록은 드롭다운이 필요해 1차 반영에서는 생략했다
/// (오버레이 경로는 모바일에 그대로 남아 있다).
class DesktopSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final double width;

  const DesktopSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.width = 320,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 36,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: onSubmitted,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: '제목 또는 작가로 검색',
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.38),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: _ivory.withOpacity(0.60),
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 4,
            ),
          ),
        ),
      ),
    );
  }
}

/// 코인 잔액 + 충전 버튼.
///
/// 예전엔 home_tab.dart의 private `_buildChargeButton()`이었다 — 데스크톱
/// 상단 내비바와 모바일 헤더 줄이 같은 버튼을 써야 해서 public 위젯으로
/// 꺼냈다. 게스트(uid 없음)는 지갑이 없으니 '충전' 라벨만, 로그인 사용자는
/// users/{uid}/wallet/current 잔액을 실시간으로 보여준다.
class CoinChargeButton extends StatefulWidget {
  const CoinChargeButton({super.key});

  @override
  State<CoinChargeButton> createState() => _CoinChargeButtonState();
}

class _CoinChargeButtonState extends State<CoinChargeButton> {
  // build()마다 새로 만들면 StreamBuilder가 매번 재구독해서 잔액이 깜빡인다 —
  // 리포지토리와 스트림은 State에 한 번만 잡아 둔다.
  final WalletRepository _walletRepository = WalletRepository();
  Stream<int>? _balanceStream;
  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AuthScope.of(context).userId;
    if (uid == _uid && (_balanceStream != null || uid == null)) return;
    _uid = uid;
    _balanceStream = uid == null ? null : _walletRepository.watchBalance(uid);
  }

  @override
  Widget build(BuildContext context) {
    final stream = _balanceStream;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChargePage()),
      ),
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
            const Icon(Icons.monetization_on_outlined, color: _amber, size: 16),
            const SizedBox(width: 5),
            if (stream == null)
              Text(
                '충전',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _ivory.withOpacity(0.9),
                ),
              )
            else
              StreamBuilder<int>(
                stream: stream,
                builder: (context, snapshot) {
                  final balance = snapshot.data;
                  return Text(
                    balance == null ? '충전' : '$balance',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _ivory.withOpacity(0.9),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 아바타 + 드롭다운 — 예전에 "설정" 탭(SettingsTab)에 있던 알림/계정/
/// 로그아웃을 여기로 접었다. admin 도구의 `AccountMenu`
/// (lib/admin/widgets/account_menu.dart)와 같은 상호작용 패턴(아바타를
/// 누르면 PopupMenuButton이 열린다)이지만, 이 파일의 이미 정해진 팔레트
/// (검정 배경 + _ivory/_coral/_amber)로 다시 칠했다 — AdminColors를
/// 끌어오지 않는다(이 화면은 lib/admin/을 아예 참조하지 않는다, 두 앱은
/// 완전히 별개로 빌드/배포된다).
///
/// "작가 도구로"는 새 창으로 연다(openExternalLink) — 독자 앱과 작가
/// 편집기(lib/main_admin.dart)는 서로 다른 진입점으로 따로 빌드/배포되는
/// 별도의 웹 앱이라 인앱 네비게이션이 불가능하다(admin 쪽의 "독자로 보기"/
/// "관리자 페이지로"와 정확히 같은 이유 — ExternalLinks 문서 참고). 예전
/// LibraryHeader(지금은 아무 데서도 안 쓰이는 죽은 코드)가 이 링크의
/// onTap을 콜백으로만 받고 실제 동작을 구현한 적이 없어서, 이게 이
/// 프로젝트에서 처음으로 실제 동작하는 구현이다.
///
/// 알림/계정은 아직 실제 기능이 없다 — SettingsTab이 하던 것과 똑같이
/// "아직 준비 중인 기능이에요" 스낵바 스텁을 그대로 유지한다(요청 사양,
/// 이 작업 범위 밖).
class _AccountAvatarMenu extends StatelessWidget {
  final bool showAuthorModeLink;
  final VoidCallback onSignOut;

  const _AccountAvatarMenu({
    required this.showAuthorModeLink,
    required this.onSignOut,
  });

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('아직 준비 중인 기능이에요.')));
  }

  @override
  Widget build(BuildContext context) {
    // CoinChargeButton과 같은 방식 — 이 바 자체는 상태를 안 들고, 필요한
    // 값을 그때그때 AuthScope/FirebaseAuth에서 직접 읽는다. 스트림 구독이
    // 없어서(email/displayName은 세션 중 바뀌지 않는다) didChangeDependencies
    // 가드 없이 build()에서 바로 읽어도 안전하다.
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final displayName = user?.displayName ?? '';
    // 이메일이 없으면 표시 이름으로 — sign_in_page.dart가 ensureProfile에
    // email/displayName을 넘길 때 쓰는 것과 같은 폴백 순서.
    final label = email.isNotEmpty ? email : displayName;
    final initial = label.isEmpty ? '?' : label.characters.first.toUpperCase();

    return PopupMenuButton<String>(
      tooltip: '',
      color: const Color(0xFF1A1A18),
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withOpacity(0.10)),
      ),
      onSelected: (value) {
        switch (value) {
          case 'authorTool':
            openExternalLink(ExternalLinks.authorToolUrl);
          case 'notifications':
            _showComingSoon(context);
          case 'account':
            _showComingSoon(context);
          case 'signout':
            onSignOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 40,
          child: Text(
            label.isEmpty ? '계정' : label,
            style: TextStyle(fontSize: 11.5, color: _ivory.withOpacity(0.6)),
          ),
        ),
        if (showAuthorModeLink)
          PopupMenuItem<String>(
            value: 'authorTool',
            height: 42,
            child: Row(
              children: [
                Text('작가 도구로', style: TextStyle(fontSize: 13, color: _ivory)),
                const SizedBox(width: 6),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: _ivory.withOpacity(0.5),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'notifications',
          height: 42,
          child: Text('알림', style: TextStyle(fontSize: 13, color: _ivory)),
        ),
        PopupMenuItem<String>(
          value: 'account',
          height: 42,
          child: Text('계정', style: TextStyle(fontSize: 13, color: _ivory)),
        ),
        PopupMenuItem<String>(
          value: 'signout',
          height: 42,
          child: Text('로그아웃', style: TextStyle(fontSize: 13, color: _ivory)),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _coral,
          ),
        ),
      ),
    );
  }
}
