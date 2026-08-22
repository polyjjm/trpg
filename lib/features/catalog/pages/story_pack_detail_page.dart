import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/state/game_state_scope.dart';
import '../../../core/state/reading_progress.dart';
import '../../../core/state/reading_progress_repository.dart';
import '../../../reader/interactive/interactive_reader.dart';
import '../../../reader/linear/linear_reader.dart';
import '../../../reader/shared/paywall.dart';
import '../data/pack_bundle_repository.dart';
import '../data/story_pack_repository.dart';
import '../models/genre_style.dart';
import '../models/pack_bundle.dart';
import '../models/story_pack.dart';
import '../widgets/bundle_card.dart';
import '../widgets/home_desktop_layout.dart';
import '../widgets/pack_comments_section.dart';
import '../widgets/pack_reviews_section.dart';

const Color _ivory = Color(0xFFE2D4BF);
const List<Color> _brandGradient = [Color(0xFFFF6B4A), Color(0xFFFFB648)];

/// 데스크톱에서 본문(설명/리뷰/댓글)이 늘어나는 최대 폭 — 1440px 화면에서
/// 왼쪽 컬럼은 950px쯤 되는데, 본문 한 줄이 거기까지 늘어나면 눈이 줄을
/// 놓친다. 읽기 폭은 760으로 잠그고 남는 공간은 여백으로 둔다.
const double _readingColumnMaxWidth = 760;

/// 데스크톱 오른쪽 액션 컬럼 폭.
const double _actionColumnWidth = 360;

/// 이야기 팩 상세 화면 — 카드를 탭하면 바로 이 전체 화면으로 들어온다.
///
/// 좁은 폭: 표지 헤더(화면 높이 46%) 아래로 설명 → 메타 행 → 액션 버튼 →
/// 번들 → 리뷰 → 댓글이 한 줄로 쌓인다(기존 그대로).
///
/// 데스크톱 폭([homeDesktopBreakpoint] 이상): 표지 헤더를 340px 밴드로
/// 낮추고, 그 아래를 2단으로 쪼갠다 — 왼쪽은 읽는 것(설명/번들/리뷰/댓글),
/// 오른쪽 360px은 결정하는 것(표지·메타·가격·액션 버튼). 예전엔 화면 높이의
/// 절반을 표지가 먹고 나머지가 한 줄로 이어져서, 넓은 화면에서는 스크롤만
/// 길고 정작 액션 버튼은 한참 내려가야 나왔다.
///
/// 유료 팩도 미구매 상태로 바로 들어올 수 있으며, 무료 미리보기 한도는
/// 리더 화면 안에서 노드 이동 시점에 따로 검사한다.
class StoryPackDetailPage extends StatefulWidget {
  final StoryPack pack;

  const StoryPackDetailPage({super.key, required this.pack});

  @override
  State<StoryPackDetailPage> createState() => _StoryPackDetailPageState();
}

class _StoryPackDetailPageState extends State<StoryPackDetailPage> {
  final ReadingProgressRepository _progressRepository = ReadingProgressRepository();
  final PackBundleRepository _bundleRepository = PackBundleRepository();
  final StoryPackRepository _packRepository = StoryPackRepository();
  late final Stream<List<PackBundle>> _bundlesStream =
      _bundleRepository.watchBundlesContainingPack(widget.pack.id);

  bool _resolvedProgress = false;
  ReadingProgress? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // GameStateScope.of/AuthScope.of는 initState에서 부르면 안 되는 타이밍이라
    // (아직 InheritedWidget 의존성 등록 전) 여기서, 딱 한 번만 시작한다.
    if (_resolvedProgress) return;
    _resolvedProgress = true;
    _loadProgress();
  }

  /// 이번 세션에 이미 메모리(GameState)로 알고 있으면 그걸 그대로 쓰고,
  /// 로그인 사용자인데 아직 모르면 Firestore에서 한 번 불러와 GameState에도
  /// 채워 둔다 — 그래야 다음에 여는 리더가 같은 값을 다시 조회하지 않는다.
  Future<void> _loadProgress() async {
    final gameState = GameStateScope.of(context);
    final existing = gameState.progressFor(widget.pack.id);
    if (existing != null) {
      if (mounted) setState(() => _progress = existing);
      return;
    }

    final uid = AuthScope.of(context).userId;
    if (uid == null) return;
    try {
      final loaded = await _progressRepository.load(uid, widget.pack.id);
      if (!mounted || loaded == null) return;
      gameState.seedPackProgress(widget.pack.id, loaded);
      setState(() => _progress = loaded);
    } catch (e) {
      debugPrint('읽기 진행 상황 불러오기 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final gameState = GameStateScope.of(context);
    final owned = pack.isFree || gameState.ownsPack(pack.id);
    final hasProgress = _progress != null;
    // 리뷰/댓글 작성 자격 — 소유(또는 무료)뿐 아니라 로그인도 돼 있어야 한다.
    // owned만으로는 게스트도 true가 될 수 있는데(무료 팩) Firestore 쓰기
    // 자체가 로그인을 요구하니 여기서 미리 걸러야 한다.
    final canReview = owned && AuthScope.of(context).userId != null;
    final isDesktop = MediaQuery.sizeOf(context).width >= homeDesktopBreakpoint;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _CoverHeader(pack: pack, isDesktop: isDesktop),
          if (isDesktop)
            _DesktopBody(
              pack: pack,
              owned: owned,
              hasProgress: hasProgress,
              canReview: canReview,
              bundlesStream: _bundlesStream,
              packRepository: _packRepository,
              onAction: () => _handleAction(context, owned),
            )
          else
            _MobileBody(
              pack: pack,
              owned: owned,
              hasProgress: hasProgress,
              canReview: canReview,
              bundlesStream: _bundlesStream,
              packRepository: _packRepository,
              onAction: () => _handleAction(context, owned),
            ),
        ],
      ),
    );
  }

  /// [owned]가 false면 먼저 requestPackPurchase(paywall.dart)로 구매를
  /// 진행한다 — 리더 안에서 미리보기 한도에 걸렸을 때 뜨는 것과 완전히 같은
  /// 흐름이다. 취소했거나 코인이 부족해 구매가 안 끝났으면 리더로 넘어가지
  /// 않는다.
  Future<void> _handleAction(BuildContext context, bool owned) async {
    final pack = widget.pack;

    if (!owned) {
      final gameState = GameStateScope.of(context);
      final purchased = await requestPackPurchase(context, gameState, pack);
      if (!purchased || !context.mounted) return;
    }

    final reader = pack.format == StoryPackFormat.linear
        ? LinearReader(pack: pack)
        : InteractiveReader(pack: pack);
    Navigator.push(context, MaterialPageRoute(builder: (_) => reader));
  }
}

/// 좁은 폭 본문 — 기존 순서 그대로.
class _MobileBody extends StatelessWidget {
  final StoryPack pack;
  final bool owned;
  final bool hasProgress;
  final bool canReview;
  final Stream<List<PackBundle>> bundlesStream;
  final StoryPackRepository packRepository;
  final VoidCallback onAction;

  const _MobileBody({
    required this.pack,
    required this.owned,
    required this.hasProgress,
    required this.canReview,
    required this.bundlesStream,
    required this.packRepository,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Description(pack: pack),
          const SizedBox(height: 22),
          _MetadataRow(pack: pack, hasProgress: hasProgress),
          const SizedBox(height: 22),
          if (!owned)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PreviewNotice(pack: pack),
            ),
          _PrimaryActionButton(
            label: owned ? (hasProgress ? '이어보기' : '읽기 시작') : '결제하기',
            onTap: onAction,
          ),
          const SizedBox(height: 32),
          _BundlesForPack(
            bundlesStream: bundlesStream,
            packRepository: packRepository,
          ),
          _SectionRule(),
          PackReviewsSection(pack: pack, eligible: canReview),
          const SizedBox(height: 28),
          _SectionRule(),
          PackCommentsSection(pack: pack, eligible: canReview),
        ],
      ),
    );
  }
}

/// 데스크톱 본문 — 왼쪽은 읽는 것, 오른쪽 360px은 결정하는 것.
///
/// 오른쪽 카드는 CSS의 position: sticky처럼 따라 내려오지는 않는다. 이
/// 화면 전체가 하나의 ListView라서 Flutter에서 그걸 하려면 CustomScrollView +
/// SliverPersistentHeader로 구조를 바꿔야 하는데, 카드가 이미 화면 높이만큼
/// 길어서 실익이 적었다.
class _DesktopBody extends StatelessWidget {
  final StoryPack pack;
  final bool owned;
  final bool hasProgress;
  final bool canReview;
  final Stream<List<PackBundle>> bundlesStream;
  final StoryPackRepository packRepository;
  final VoidCallback onAction;

  const _DesktopBody({
    required this.pack,
    required this.owned,
    required this.hasProgress,
    required this.canReview,
    required this.bundlesStream,
    required this.packRepository,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 80),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _readingColumnMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Description(pack: pack),
                  const SizedBox(height: 32),
                  _BundlesForPack(
                    bundlesStream: bundlesStream,
                    packRepository: packRepository,
                  ),
                  _SectionRule(),
                  PackReviewsSection(pack: pack, eligible: canReview),
                  const SizedBox(height: 28),
                  _SectionRule(),
                  PackCommentsSection(pack: pack, eligible: canReview),
                ],
              ),
            ),
          ),
          const SizedBox(width: 44),
          SizedBox(
            width: _actionColumnWidth,
            child: _ActionCard(
              pack: pack,
              owned: owned,
              hasProgress: hasProgress,
              onAction: onAction,
            ),
          ),
        ],
      ),
    );
  }
}

/// 데스크톱 오른쪽 카드 — 표지 + 메타 + 미리보기 안내 + 액션 버튼.
///
/// 메타는 좁은 폭의 가로 4칸 행([_MetadataRow]) 대신 라벨/값 세로 나열이다 —
/// 360px에 4칸을 넣으면 "리뷰 없음"이나 "★4.6 (28)" 같은 값이 줄바꿈된다.
/// 항목과 값 규칙 자체는 [_MetadataRow]와 같은 것을 공유한다.
class _ActionCard extends StatelessWidget {
  final StoryPack pack;
  final bool owned;
  final bool hasProgress;
  final VoidCallback onAction;

  const _ActionCard({
    required this.pack,
    required this.owned,
    required this.hasProgress,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final genreStyle = genreStyleFor(pack.primaryGenre);
    final coverUrl = pack.coverImageUrl;
    final isInteractive = pack.format == StoryPackFormat.interactive;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            // storyCoverAspectRatio(0.6)와 같은 비율 — 앱 전체 표지 비율.
            aspectRatio: 0.6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: coverUrl != null && coverUrl.isNotEmpty
                      ? Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _CoverFallback(genreStyle: genreStyle, iconSize: 72),
                        )
                      : _CoverFallback(genreStyle: genreStyle, iconSize: 72),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isInteractive
                          ? const Color(0xFF2AA198)
                          : const Color(0xFF3A7BD5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      isInteractive ? Icons.call_split_rounded : Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final item in metadataEntriesFor(pack, hasProgress)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.55)),
                    ),
                  ),
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ivory,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!owned) ...[
            const SizedBox(height: 2),
            _PreviewNotice(pack: pack),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 6),
          _PrimaryActionButton(
            label: owned ? (hasProgress ? '이어보기' : '읽기 시작') : '결제하기',
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

class _Description extends StatelessWidget {
  final StoryPack pack;

  const _Description({required this.pack});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= homeDesktopBreakpoint;
    return Text(
      pack.description,
      style: TextStyle(
        fontSize: isDesktop ? 15.5 : 14,
        height: isDesktop ? 1.8 : 1.6,
        color: Colors.white.withOpacity(0.86),
      ),
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  final StoryPack pack;

  const _PreviewNotice({required this.pack});

  @override
  Widget build(BuildContext context) {
    return Text(
      '구매 전 ${pack.previewNodeLimit}개 노드까지 무료로 미리볼 수 있어요',
      style: TextStyle(fontSize: 12.5, height: 1.55, color: _ivory.withOpacity(0.68)),
    );
  }
}

class _SectionRule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
    );
  }
}

class _CoverHeader extends StatelessWidget {
  final StoryPack pack;
  final bool isDesktop;

  const _CoverHeader({required this.pack, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final genreStyle = genreStyleFor(pack.primaryGenre);
    final coverImageUrl = pack.coverImageUrl;
    // 데스크톱에서 46%는 1080px 화면에서 500px에 달한다 — 표지만 보고
    // 스크롤을 시작해야 한다. 넓은 화면에서는 고정 340px 밴드로 낮춘다.
    final height = isDesktop ? 340.0 : MediaQuery.of(context).size.height * 0.46;
    final horizontalPadding = isDesktop ? 40.0 : 22.0;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverImageUrl != null && coverImageUrl.isNotEmpty)
            Image.network(
              coverImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _CoverFallback(genreStyle: genreStyle),
            )
          else
            _CoverFallback(genreStyle: genreStyle),
          // 텍스트가 표지 위에서도 읽히도록 중간부터 아래로 짙어지는 그라디언트.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.92)],
                stops: const [0.4, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 40 : 12,
                vertical: 8,
              ),
              child: const Align(alignment: Alignment.topLeft, child: _BackButton()),
            ),
          ),
          Positioned(
            left: horizontalPadding,
            right: horizontalPadding,
            bottom: isDesktop ? 30 : 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _GenreTypeBadge(genreStyle: genreStyle, typeLabel: pack.format.label),
                SizedBox(height: isDesktop ? 12 : 10),
                Text(
                  pack.title,
                  style: TextStyle(
                    fontSize: isDesktop ? 42 : 26,
                    fontWeight: FontWeight.w800,
                    color: _ivory,
                    letterSpacing: 0.4,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: isDesktop ? 6 : 4),
                Text(
                  pack.authorName,
                  style: TextStyle(
                    fontSize: isDesktop ? 15 : 13,
                    color: _ivory.withOpacity(0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.38),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

class _GenreTypeBadge extends StatelessWidget {
  final GenreStyle genreStyle;
  final String typeLabel;

  const _GenreTypeBadge({required this.genreStyle, required this.typeLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: genreStyle.color.withOpacity(0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${genreStyle.label} · $typeLabel',
        style: const TextStyle(
          fontSize: 11.5,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 메타 항목 한 쌍.
class MetadataEntry {
  final String label;
  final String value;

  const MetadataEntry(this.label, this.value);
}

/// 진행률/엔딩 발견/평점/가격 — 좁은 폭의 가로 행과 데스크톱 카드의 세로
/// 나열이 같은 목록을 공유한다(두 곳이 각자 문구를 들고 있다가 어긋나는 걸
/// 막는다).
///
/// - 가격은 pack.effectivePrice/isFree를 쓴다 — 할인 중이면 salePrice가
///   자동으로 반영된다(정가 pack.price를 직접 보여주지 않는다). 보유 여부는
///   여기서 말하지 않는다 — 액션 버튼 라벨이 이미 알려준다.
/// - 진행률([hasProgress])은 팩별 신호다 — GameState.progressFor(pack.id)
///   또는 users/{uid}/readingProgress/{packId}에 저장된 위치가 있는지를
///   부모가 미리 조회해 넘겨준다.
/// - 엔딩 발견은 인터랙티브에서만 보이지만, "엔딩" 개념 자체가 콘텐츠 모델에도
///   GameState에도 없어서 항상 0으로 표시되는 고정 placeholder다.
/// - 평점은 storyPacks 문서에 비정규화된 avgRating/reviewCount를 그대로
///   보여준다 — 집계는 Cloud Function이 리뷰 쓰기마다 서버에서 갱신한다.
List<MetadataEntry> metadataEntriesFor(StoryPack pack, bool hasProgress) {
  final avgRating = pack.avgRating;
  return [
    MetadataEntry('진행률', hasProgress ? '진행 중' : '시작 전'),
    if (pack.format == StoryPackFormat.interactive) const MetadataEntry('엔딩 발견', '0개'),
    MetadataEntry(
      '평점',
      avgRating == null
          ? '리뷰 없음'
          : '★${avgRating.toStringAsFixed(1)} (${pack.reviewCount})',
    ),
    MetadataEntry('가격', pack.isFree ? '무료' : '${pack.effectivePrice}코인'),
  ];
}

class _MetadataRow extends StatelessWidget {
  final StoryPack pack;
  final bool hasProgress;

  const _MetadataRow({required this.pack, required this.hasProgress});

  @override
  Widget build(BuildContext context) {
    final entries = metadataEntriesFor(pack, hasProgress);
    return Row(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const _MetadataDivider(),
          Expanded(child: _MetadataItem(entry: entries[i])),
        ],
      ],
    );
  }
}

class _MetadataItem extends StatelessWidget {
  final MetadataEntry entry;

  const _MetadataItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.label, style: TextStyle(fontSize: 11, color: _ivory.withOpacity(0.55))),
        const SizedBox(height: 4),
        Text(
          entry.value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ivory),
        ),
      ],
    );
  }
}

class _MetadataDivider extends StatelessWidget {
  const _MetadataDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white.withOpacity(0.12),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: _brandGradient),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "이 팩이 포함된 번들" 래퍼 — 활성 번들이 없으면 아무것도 그리지 않는다.
class _BundlesForPack extends StatelessWidget {
  final Stream<List<PackBundle>> bundlesStream;
  final StoryPackRepository packRepository;

  const _BundlesForPack({required this.bundlesStream, required this.packRepository});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PackBundle>>(
      stream: bundlesStream,
      builder: (context, snapshot) {
        final bundles = snapshot.data ?? const <PackBundle>[];
        if (bundles.isEmpty) return const SizedBox.shrink();
        return _BundlesForPackSection(bundles: bundles, packRepository: packRepository);
      },
    );
  }
}

/// BundleCard(홈 탭 "번들 상품" 섹션과 같은 위젯)가 카드 안에 포함된 팩들의
/// 표지/제목을 보여주려면 그 팩들의 StoryPack을 알아야 하는데, 이 화면은
/// 원래 pack 하나만 갖고 있다 — 그래서 bundles가 도착하면 그 안의 packIds
/// 전체를 한 번에 조회한다. bundles의 id 구성이 실제로 바뀔 때만 다시
/// 조회한다(매 리빌드마다 새로 조회하지 않는다).
class _BundlesForPackSection extends StatefulWidget {
  final List<PackBundle> bundles;
  final StoryPackRepository packRepository;

  const _BundlesForPackSection({required this.bundles, required this.packRepository});

  @override
  State<_BundlesForPackSection> createState() => _BundlesForPackSectionState();
}

class _BundlesForPackSectionState extends State<_BundlesForPackSection> {
  late Future<List<StoryPack>> _packsFuture = _fetchPacks();
  late Set<String> _fetchedIds = _idsOf(widget.bundles);

  static Set<String> _idsOf(List<PackBundle> bundles) =>
      bundles.expand((b) => b.packIds).toSet();

  Future<List<StoryPack>> _fetchPacks() {
    return widget.packRepository.fetchPacksByIds(_idsOf(widget.bundles).toList());
  }

  @override
  void didUpdateWidget(covariant _BundlesForPackSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIds = _idsOf(widget.bundles);
    if (!setEquals(newIds, _fetchedIds)) {
      _fetchedIds = newIds;
      _packsFuture = _fetchPacks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoryPack>>(
      future: _packsFuture,
      builder: (context, snapshot) {
        final packs = snapshot.data ?? const <StoryPack>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '이 팩이 포함된 번들',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ivory),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.bundles.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    BundleCard(bundle: widget.bundles[index], allPacks: packs),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 표지 이미지가 없거나 로드에 실패했을 때 쓰는 fallback — StoryCoverCard와
/// 같은 브랜드 그라디언트 + 장르 아이콘.
class _CoverFallback extends StatelessWidget {
  final GenreStyle genreStyle;
  final double iconSize;

  const _CoverFallback({required this.genreStyle, this.iconSize = 96});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _brandGradient,
        ),
      ),
      child: Center(
        child: Icon(genreStyle.icon, color: Colors.white.withOpacity(0.5), size: iconSize),
      ),
    );
  }
}
