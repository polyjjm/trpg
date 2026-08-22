import 'dart:async';

import 'package:flutter/material.dart';

import '../models/home_banner.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 홈 탭 히어로 배너 — admin이 "홈 배너 관리"에서 만든 homeBanners를
/// sortOrder 순으로 자동 넘김(일시정지 가능) 이미지 카드로 보여준다. 텍스트/
/// 배경색 오버레이 없이 이미지 하나로 꽉 채운다(doc/home_*_mockup.html 참고
/// — "배너 이미지" placeholder 자리 그대로). 연결된 스토리팩(linkedPackId)의
/// 표지는 별도로 다시 불러오지 않고, HomeTab이 이미 구독 중인 팩 목록
/// ([allPacks])에서 바로 찾아 쓴다.
class HeroBannerSection extends StatefulWidget {
  final List<HomeBanner> banners;
  final List<StoryPack> allPacks;

  /// 모바일 16/6, 데스크톱 21/6 — HomeTab이 폭에 따라 골라 넘긴다.
  final double aspectRatio;

  /// true(데스크톱 폭)면 좌우 화살표를 마우스 호버 중에만 보여주고, false
  /// (모바일 폭)면 항상 보여준다. 실제 터치/마우스 포인터 종류를 감지하는
  /// 대신 HomeTab이 이미 쓰고 있는 폭 기준(600px)을 그대로 재사용한다 —
  /// 이 프로젝트가 데스크톱/모바일을 구분하는 다른 모든 자리와 같은 기준.
  final bool showArrowsOnHoverOnly;

  const HeroBannerSection({
    super.key,
    required this.banners,
    required this.allPacks,
    this.aspectRatio = 16 / 7,
    this.showArrowsOnHoverOnly = false,
  });

  @override
  State<HeroBannerSection> createState() => _HeroBannerSectionState();
}

class _HeroBannerSectionState extends State<HeroBannerSection> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;
  bool _paused = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _scheduleAutoAdvance();
  }

  @override
  void didUpdateWidget(covariant HeroBannerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.banners.length != oldWidget.banners.length && _page >= widget.banners.length) {
      _page = 0;
    }
    // ⚠️ 버그 수정: initState 시점엔 Firestore 배너 스트림이 아직 데이터를
    // 안 내려준 상태라 banners가 비어 있거나 1개뿐인 경우가 많다 —
    // _scheduleAutoAdvance()가 `length <= 1`에 걸려 타이머를 아예 안 건다.
    // 그 뒤 실제 배너 목록(2개 이상)이 도착해도 여기서 다시 스케줄링을
    // 안 해주면 타이머가 영원히 안 걸린 채로 남는다 — 일시정지 버튼을
    // 한 번 눌러야(그 핸들러가 _scheduleAutoAdvance를 호출하니까) 그제서야
    // 넘어가기 시작하던 증상이 바로 이거였다. banners 목록 자체가 바뀔
    // 때마다(길이든 내용이든) 다시 스케줄링해서, "이미 4초 타이머가 잘 돌고
    // 있는데 매 리빌드마다 초기화되는" 문제 없이도 최초 데이터 도착 시점을
    // 놓치지 않게 한다.
    if (!identical(widget.banners, oldWidget.banners)) {
      _scheduleAutoAdvance();
    }
  }

  void _scheduleAutoAdvance() {
    _timer?.cancel();
    if (_paused || widget.banners.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.banners.isEmpty) return;
      final next = (_page + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _scheduleAutoAdvance();
  }

  /// 화살표 버튼 — 즉시 그 페이지로 넘기고, 자동 넘김 타이머를 처음부터
  /// 다시 스케줄한다(방금 수동으로 넘겼는데 1초 뒤에 또 자동으로 넘어가면
  /// 어색하다 — 수동 조작 시점부터 다시 4초를 센다).
  void _goToDelta(int delta) {
    if (widget.banners.length <= 1) return;
    final next = (_page + delta) % widget.banners.length;
    final wrapped = next < 0 ? next + widget.banners.length : next;
    _controller.animateToPage(
      wrapped,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _scheduleAutoAdvance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  StoryPack? _linkedPack(HomeBanner banner) {
    final packId = banner.linkedPackId;
    if (packId == null) return null;
    for (final pack in widget.allPacks) {
      if (pack.id == packId) return pack;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    final showArrows = banners.length > 1 && (!widget.showArrowsOnHoverOnly || _hovering);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: banners.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => _BannerImage(
                  banner: banners[index],
                  linkedPack: _linkedPack(banners[index]),
                  // 배너가 2개 이상이면 _CounterPill이 바로 이 위젯 위,
                  // 같은 왼쪽 아래 모서리(left:10, bottom:10)에 그려진다 —
                  // 텍스트 오버레이가 있으면 그 아래를 침범하지 않도록,
                  // 이 값이 true일 때 텍스트 블록을 더 위로 띄운다.
                  reserveSpaceForCounterPill: banners.length > 1,
                ),
              ),
              if (banners.length > 1) ...[
                Positioned(
                  left: 6,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      icon: Icons.chevron_left_rounded,
                      visible: showArrows,
                      onTap: () => _goToDelta(-1),
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      icon: Icons.chevron_right_rounded,
                      visible: showArrows,
                      onTap: () => _goToDelta(1),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: _CounterPill(
                    paused: _paused,
                    page: _page,
                    total: banners.length,
                    onTogglePause: _togglePause,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 배너 좌우의 이전/다음 화살표 — 데스크톱 폭에서는 호버 중에만
/// (AnimatedOpacity로 부드럽게), 모바일 폭에서는 항상 보인다. 안 보일 때도
/// IgnorePointer로 탭을 막아 PageView의 스와이프 제스처와 겹치지 않게 한다.
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _ivory, size: 20),
          ),
        ),
      ),
    );
  }
}

/// 배너 프레임 왼쪽 아래에 얹는 일시정지/재생 + 페이지 카운터 pill —
/// 목업의 "⏸ 1 / 3" 배지 그대로. PageView 밖의 Stack에 고정돼 있어 페이지가
/// 넘어가도 그대로 남아 있다.
class _CounterPill extends StatelessWidget {
  final bool paused;
  final int page;
  final int total;
  final VoidCallback onTogglePause;

  const _CounterPill({
    required this.paused,
    required this.page,
    required this.total,
    required this.onTogglePause,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTogglePause,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 13,
              color: _ivory,
            ),
            const SizedBox(width: 6),
            Text(
              '${page + 1} / $total',
              style: const TextStyle(fontSize: 11.5, color: _ivory, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// 텍스트 오버레이(스크림 그라디언트 + 아이브로우/타이틀/서브텍스트)를
/// 켜는 기준값 — [HomeBanner.hasTextOverlay]와 정확히 같은 규칙을 여기서도
/// 다시 쓴다(title이 없으면 오버레이 자체를 그리지 않는다).
const Color _eyebrowColor = Color(0xFFFFB648);

class _BannerImage extends StatelessWidget {
  final HomeBanner banner;
  final StoryPack? linkedPack;

  /// true면 이 배너 바로 위(Stack 상위 레이어)에 _CounterPill이
  /// bottom-left(left:10, bottom:10)에 그려진다 — 텍스트 블록도 같은
  /// 왼쪽 아래 정렬이라, 겹치지 않게 텍스트 블록을 그만큼 더 띄운다.
  final bool reserveSpaceForCounterPill;

  const _BannerImage({
    required this.banner,
    required this.linkedPack,
    required this.reserveSpaceForCounterPill,
  });

  @override
  Widget build(BuildContext context) {
    final pack = linkedPack;
    return InkWell(
      onTap: pack == null
          ? null
          : () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          banner.imageUrl.isNotEmpty
              ? Image.network(
            banner.imageUrl,
            fit: BoxFit.cover,
            // 헤더 배경 이미지와 동시에 화면에 떠도 GPU 텍스처 자원을
            // 덜 쓰도록 디코딩 해상도를 실제 표시 크기에 맞춰 낮춘다 —
            // 원본 해상도 그대로 올리면 두 이미지가 동시에 GPU에 올라갈
            // 때 자원 부족으로 렌더링이 깨지는 기기가 있었다.
            cacheWidth: 800,
            errorBuilder: (_, _, _) => const _BannerImageFallback(),
          )
              : const _BannerImageFallback(),
          // title이 없으면(예: 기존 이미지 전용 배너) 스크림도 텍스트도
          // 아예 안 그린다 — 오늘 있는 이미지 전용 배너가 그대로 유지돼야
          // 한다는 요구사항 그대로다.
          if (banner.hasTextOverlay) ...[
            const Positioned.fill(child: _BannerScrim()),
            Positioned(
              left: 20,
              right: 20,
              bottom: reserveSpaceForCounterPill ? 46 : 18,
              child: _BannerTextBlock(banner: banner),
            ),
          ],
        ],
      ),
    );
  }
}

/// 배너 하단에서 위로 갈수록 투명해지는 어두운 스크림 — 텍스트가 배너
/// 이미지 위에서도 항상 읽히게 한다. 텍스트 블록이 없을 땐(hasTextOverlay
/// == false) 이 위젯 자체가 트리에 안 들어가므로 기존 이미지 전용 배너는
/// 완전히 그대로다.
class _BannerScrim extends StatelessWidget {
  const _BannerScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.78), Colors.transparent],
          stops: const [0.0, 0.85],
        ),
      ),
    );
  }
}

/// 아이브로우(선택) + 타이틀 + 서브텍스트(선택), 왼쪽 아래 정렬. 오른쪽
/// 여백을 넉넉히 남기도록 가로폭을 부모 폭의 약 70%로만 쓴다 — 배너가
/// 넓어질수록 제목 한 줄이 끝까지 늘어져 읽기 불편해지는 걸 막는
/// 일반적인 레이아웃 규칙이다(카운터 pill과의 충돌은 세로로 띄우는
/// reserveSpaceForCounterPill이 이미 해결한다).
class _BannerTextBlock extends StatelessWidget {
  final HomeBanner banner;

  const _BannerTextBlock({required this.banner});

  @override
  Widget build(BuildContext context) {
    final eyebrow = banner.eyebrow;
    final subtitle = banner.subtitle;

    return Align(
      alignment: Alignment.bottomLeft,
      child: FractionallySizedBox(
        widthFactor: 0.7,
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null && eyebrow.isNotEmpty) ...[
              Text(
                eyebrow.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _eyebrowColor,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              banner.title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white.withOpacity(0.78),
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BannerImageFallback extends StatelessWidget {
  const _BannerImageFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF2C2C2A),
      child: Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.white.withOpacity(0.3), size: 28),
      ),
    );
  }
}