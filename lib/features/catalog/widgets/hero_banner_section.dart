import 'dart:async';

import 'package:flutter/material.dart';

import '../models/home_banner.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE7E2DA);
const Color _muted = Color(0xFFAAA59E);
const Color _orange = Color(0xFFF47A2A);

/// 홈의 메인 피처 배너.
///
/// 관리자 배너에 title/subtitle이 없더라도 linkedPackId가 있으면 연결된
/// StoryPack의 제목/설명/장르/형식을 자동으로 사용한다. 따라서 기존 이미지
/// 전용 배너 데이터도 별도 마이그레이션 없이 현대적인 메인 피처 UI로 보인다.
class HeroBannerSection extends StatefulWidget {
  final List<HomeBanner> banners;
  final List<StoryPack> allPacks;
  final double aspectRatio;
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
    if (widget.banners.length != oldWidget.banners.length &&
        _page >= widget.banners.length) {
      _page = 0;
    }
    if (!identical(widget.banners, oldWidget.banners)) {
      _scheduleAutoAdvance();
    }
  }

  void _scheduleAutoAdvance() {
    _timer?.cancel();
    if (_paused || widget.banners.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.banners.isEmpty) return;
      _goTo((_page + 1) % widget.banners.length, reschedule: false);
    });
  }

  void _goTo(int index, {bool reschedule = true}) {
    if (widget.banners.isEmpty) return;
    final safe = index % widget.banners.length;
    _controller.animateToPage(
      safe,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
    if (reschedule) _scheduleAutoAdvance();
  }

  void _goToDelta(int delta) {
    if (widget.banners.length <= 1) return;
    var next = (_page + delta) % widget.banners.length;
    if (next < 0) next += widget.banners.length;
    _goTo(next);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _scheduleAutoAdvance();
  }

  StoryPack? _linkedPack(HomeBanner banner) {
    final id = banner.linkedPackId;
    if (id == null) return null;
    for (final pack in widget.allPacks) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    final arrowsVisible =
        banners.length > 1 && (!widget.showArrowsOnHoverOnly || _hovering);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: _orange.withOpacity(0.07),
              blurRadius: 36,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.38),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: banners.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) {
                    final banner = banners[index];
                    return _FeatureSlide(
                      banner: banner,
                      pack: _linkedPack(banner),
                    );
                  },
                ),
                if (banners.length > 1) ...[
                  Positioned(
                    left: 28,
                    bottom: 22,
                    child: _PageDots(
                      page: _page,
                      total: banners.length,
                      onSelected: _goTo,
                    ),
                  ),
                  Positioned(
                    right: 22,
                    bottom: 18,
                    child: Row(
                      children: [
                        _CircleButton(
                          icon: Icons.chevron_left_rounded,
                          visible: arrowsVisible,
                          onTap: () => _goToDelta(-1),
                        ),
                        const SizedBox(width: 8),
                        _CircleButton(
                          icon: Icons.chevron_right_rounded,
                          visible: arrowsVisible,
                          onTap: () => _goToDelta(1),
                        ),
                        const SizedBox(width: 8),
                        _CircleButton(
                          icon: _paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          visible: arrowsVisible,
                          onTap: _togglePause,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureSlide extends StatelessWidget {
  final HomeBanner banner;
  final StoryPack? pack;

  const _FeatureSlide({required this.banner, required this.pack});

  void _open(BuildContext context) {
    final target = pack;
    if (target == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: target)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 900;
    final linked = pack;

    final title = (banner.title?.trim().isNotEmpty ?? false)
        ? banner.title!.trim()
        : (linked?.title ?? 'TELO 추천 스토리');
    final subtitle = (banner.subtitle?.trim().isNotEmpty ?? false)
        ? banner.subtitle!.trim()
        : (linked?.description ?? '새로운 이야기를 만나보세요.');
    final eyebrow = (banner.eyebrow?.trim().isNotEmpty ?? false)
        ? banner.eyebrow!.trim()
        : '오늘의 추천';

    final imageUrl = banner.imageUrl.isNotEmpty
        ? banner.imageUrl
        : (linked?.coverImageUrl ?? '');

    return InkWell(
      onTap: linked == null ? null : () => _open(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              cacheWidth: 1400,
              errorBuilder: (_, _, _) => const _HeroFallback(),
            )
          else
            const _HeroFallback(),

          // 왼쪽은 텍스트를 위해 확실히 어둡게, 오른쪽은 이미지를 살린다.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xF2050505),
                  Color(0xD90A0908),
                  Color(0x55070605),
                  Color(0x08000000),
                ],
                stops: [0.0, 0.32, 0.62, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xA8000000), Colors.transparent],
                stops: [0.0, 0.55],
              ),
            ),
          ),

          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 440 : 570),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 28 : 42,
                  26,
                  20,
                  48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _orange.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _orange.withOpacity(0.30)),
                      ),
                      child: Text(
                        eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 30 : 40,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ivory.withOpacity(0.76),
                        fontSize: compact ? 13 : 14.5,
                        height: 1.6,
                      ),
                    ),
                    if (linked != null) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetaPill(label: linked.format.label),
                          for (final genre in linked.genres.take(2))
                            _MetaPill(label: _prettyGenre(genre)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PrimaryButton(onTap: () => _open(context)),
                          const SizedBox(width: 10),
                          _SecondaryButton(onTap: () => _open(context)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _prettyGenre(String value) {
    return switch (value) {
      'slice_of_life' => '일상',
      'scifi' => 'SF',
      _ => value.isEmpty ? '기타' : value,
    };
  }
}

class _MetaPill extends StatelessWidget {
  final String label;

  const _MetaPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _ivory.withOpacity(0.82),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PrimaryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: _orange,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
              SizedBox(width: 7),
              Text(
                '읽기',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SecondaryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.24)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: _ivory),
              SizedBox(width: 7),
              Text(
                '자세히 보기',
                style: TextStyle(
                  color: _ivory,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int page;
  final int total;
  final ValueChanged<int> onSelected;

  const _PageDots({
    required this.page,
    required this.total,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          InkWell(
            onTap: () => onSelected(i),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: i == page ? 22 : 7,
              height: 7,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: i == page ? _orange : Colors.white.withOpacity(0.34),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.52),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.16)),
              ),
              child: Icon(icon, size: 20, color: _ivory),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF241710), Color(0xFF0B0B0B)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          color: Color(0x66F47A2A),
          size: 54,
        ),
      ),
    );
  }
}
