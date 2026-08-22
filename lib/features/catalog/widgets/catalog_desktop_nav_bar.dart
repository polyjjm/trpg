import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../wallet/data/wallet_repository.dart';
import '../../wallet/pages/charge_page.dart';
import 'home_desktop_layout.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _coral = Color(0xFFFF6B4A);
const Color _amber = Color(0xFFFFB35C);

/// 데스크톱 폭에서 하단 탭바(_CatalogBottomNav) 대신 화면 맨 위에 놓는
/// 가로 내비게이션 바.
///
/// 하단 탭바는 엄지로 누르는 모바일 관용구다 — 1440px 브라우저에서 그걸
/// 그대로 쓰면 화면 아래쪽에 붙은 아이콘 네 개만 남고 위쪽 폭이 비어서
/// "모바일 앱을 늘려놓은" 인상이 된다. 탭 네 개(홈/내 서재/공지사항/설정)는
/// 그대로 두고 위치만 올린다.
///
/// 검색 입력창과 코인/충전 버튼도 이 바의 오른쪽에 놓는다 — 예전엔 홈 탭
/// 본문 맨 위에 있어서 배너 위에 떠 있는 것처럼 보였다.
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
                children: [
                  ForkingPathLogoMark(size: 26),
                  SizedBox(width: 9),
                  TeloWordmark(fontSize: 22),
                ],
              ),
            ),
          ),
          const SizedBox(width: 34),
          _NavLink(label: '홈', selected: index == 0, onTap: () => onChanged(0)),
          const SizedBox(width: 26),
          _NavLink(label: '내 서재', selected: index == 1, onTap: () => onChanged(1)),
          const SizedBox(width: 26),
          _NavLink(
            label: '공지사항',
            selected: index == 2,
            showBadge: hasUnreadNotice,
            onTap: () => onChanged(2),
          ),
          const SizedBox(width: 26),
          _NavLink(label: '설정', selected: index == 3, onTap: () => onChanged(3)),
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
                  decoration: const BoxDecoration(color: Color(0xFFFF5252), shape: BoxShape.circle),
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
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: _ivory.withOpacity(0.60), size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory.withOpacity(0.9)),
              )
            else
              StreamBuilder<int>(
                stream: stream,
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
}
