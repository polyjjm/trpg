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
import '../widgets/pack_comments_section.dart';
import '../widgets/pack_reviews_section.dart';

const Color _ivory = Color(0xFFE2D4BF);
const List<Color> _brandGradient = [Color(0xFFFF6B4A), Color(0xFFFFB648)];

/// 이야기 팩 상세 화면 — 카드를 탭하면 바로 이 전체 화면으로 들어온다(예전엔
/// 작은 미리보기 시트를 거쳐야 했지만, 이 화면 자체가 미리보기 역할까지
/// 겸하도록 합쳤다). 위쪽은 표지가 화면 상단을 가득 채우는 헤더, 아래쪽은
/// 설명/메타데이터/액션 버튼이 있는 일반 스크롤 영역이다.
///
/// 유료 팩도 미구매 상태로 바로 들어올 수 있으며, 무료 미리보기 한도는
/// 리더 화면(InteractiveReader/LinearReader) 안에서 노드 이동 시점에 따로
/// 검사한다.
class StoryPackDetailPage extends StatefulWidget {
  final StoryPack pack;

  const StoryPackDetailPage({super.key, required this.pack});

  @override
  State<StoryPackDetailPage> createState() => _StoryPackDetailPageState();
}

class _StoryPackDetailPageState extends State<StoryPackDetailPage> {
  final ReadingProgressRepository _progressRepository =
      ReadingProgressRepository();
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
    // (아직 InheritedWidget 의존성 등록 전) 여기서, 딱 한 번만 시작한다 —
    // SceneFrame의 _resolvedUid와 같은 이유의 같은 가드 패턴.
    if (_resolvedProgress) return;
    _resolvedProgress = true;
    _loadProgress();
  }

  /// 이번 세션에 이미 메모리(GameState)로 알고 있으면 그걸 그대로 쓰고,
  /// 로그인 사용자인데 아직 모르면(앱을 새로 켠 뒤 이 팩을 처음 여는 경우)
  /// Firestore에서 한 번 불러와 GameState에도 채워 둔다 — 그래야 이 화면
  /// 다음에 여는 리더가 같은 값을 다시 네트워크로 조회하지 않는다.
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
    // owned만으로는 게스트도 true가 될 수 있는데(무료 팩), Firestore 쓰기
    // 자체가 로그인을 요구하니(firestore.rules) 여기서 미리 걸러야 한다.
    final canReview = owned && AuthScope.of(context).userId != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _CoverHeader(pack: pack),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.white.withOpacity(0.86),
                  ),
                ),
                const SizedBox(height: 22),
                _MetadataRow(pack: pack, hasProgress: hasProgress),
                const SizedBox(height: 22),
                if (!owned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '구매 전 ${pack.previewNodeLimit}개 노드까지 무료로 미리볼 수 있어요',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _ivory.withOpacity(0.68),
                      ),
                    ),
                  ),
                _PrimaryActionButton(
                  label: owned ? (hasProgress ? '이어보기' : '읽기 시작') : '결제하기',
                  onTap: () => _handleAction(context, owned),
                ),
                const SizedBox(height: 32),
                StreamBuilder<List<PackBundle>>(
                  stream: _bundlesStream,
                  builder: (context, snapshot) {
                    final bundles = snapshot.data ?? const <PackBundle>[];
                    if (bundles.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: _BundlesForPackSection(
                        bundles: bundles,
                        packRepository: _packRepository,
                      ),
                    );
                  },
                ),
                Container(height: 1, color: Colors.white.withOpacity(0.08)),
                const SizedBox(height: 24),
                PackReviewsSection(pack: pack, eligible: canReview),
                const SizedBox(height: 28),
                Container(height: 1, color: Colors.white.withOpacity(0.08)),
                const SizedBox(height: 24),
                PackCommentsSection(pack: pack, eligible: canReview),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [owned]가 false면 먼저 requestPackPurchase(paywall.dart)로 구매를
  /// 진행한다 — 리더 안에서 미리보기 한도에 걸렸을 때 뜨는 것과 완전히 같은
  /// 흐름(가격 확인 다이얼로그 → purchasePack Cloud Function → 성공 시
  /// gameState.markPackOwned)이다. 취소했거나 코인이 부족해 구매가 안 끝났으면
  /// (purchased == false) 리더로 넘어가지 않는다.
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

class _CoverHeader extends StatelessWidget {
  final StoryPack pack;

  const _CoverHeader({required this.pack});

  @override
  Widget build(BuildContext context) {
    final genreStyle = genreStyleFor(pack.primaryGenre);
    final coverImageUrl = pack.coverImageUrl;
    final height = MediaQuery.of(context).size.height * 0.46;

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(alignment: Alignment.topLeft, child: _BackButton()),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _GenreTypeBadge(
                  genreStyle: genreStyle,
                  typeLabel: pack.format.label,
                ),
                const SizedBox(height: 10),
                Text(
                  pack.title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _ivory,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pack.authorName,
                  style: TextStyle(
                    fontSize: 13,
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
        child: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 20,
        ),
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

/// 진행률/엔딩 발견/평점/가격을 나란히 보여주는 요약 행.
///
/// - 가격은 pack.effectivePrice/isFree를 쓴다 — 할인 중이면 salePrice가
///   자동으로 반영된다(정가 pack.price를 직접 보여주지 않는다).
/// - 진행률([hasProgress])은 이제 진짜 팩별 신호다 — GameState.progressFor(pack.id)
///   (메모리, 게스트/이번 세션) 또는 users/{uid}/readingProgress/{packId}
///   (로그인, ReadingProgressRepository)에 저장된 위치가 있는지를 부모
///   (StoryPackDetailPage)가 미리 조회해 넘겨준다 — 예전엔 GameState가 앱
///   전체에서 하나의 진행 상황만 갖고 있어서 팩을 옮겨다니면 서로의 값을
///   덮어썼던 known limitation이었다(CLAUDE.md 참고, 이제 고쳐졌다).
/// - 엔딩 발견 개수는 인터랙티브 타입에서만 보여주지만, 애초에 "엔딩"이라는
///   개념 자체가 실제 콘텐츠 모델(AdminStoryNode)에도 GameState에도 없어서
///   항상 0으로 표시되는 고정 placeholder다. 실제 엔딩 추적 시스템이 생기기
///   전까지는 숫자가 절대 바뀌지 않는다.
/// - 평점(pack.avgRating/reviewCount)은 storyPacks 문서에 비정규화된 값을
///   그대로 보여준다 — 매번 reviews 서브컬렉션을 훑어 평균을 내지 않는다,
///   그 집계는 Cloud Function(functions/src/index.ts)이 리뷰 쓰기마다
///   서버에서 갱신한다. 리뷰가 하나도 없으면(avgRating == null) "리뷰 없음".
class _MetadataRow extends StatelessWidget {
  final StoryPack pack;
  final bool hasProgress;

  const _MetadataRow({required this.pack, required this.hasProgress});

  @override
  Widget build(BuildContext context) {
    final avgRating = pack.avgRating;

    final items = <Widget>[
      _MetadataItem(label: '진행률', value: hasProgress ? '진행 중' : '시작 전'),
    ];
    if (pack.format == StoryPackFormat.interactive) {
      items.add(const _MetadataItem(label: '엔딩 발견', value: '0개'));
    }
    items.add(
      _MetadataItem(
        label: '평점',
        value: avgRating == null
            ? '리뷰 없음'
            : '★${avgRating.toStringAsFixed(1)} (${pack.reviewCount})',
      ),
    );
    items.add(
      _MetadataItem(label: '가격', value: pack.isFree ? '무료' : '${pack.effectivePrice}코인'),
    );

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const _MetadataDivider(),
          Expanded(child: items[i]),
        ],
      ],
    );
  }
}

class _MetadataItem extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: _ivory.withOpacity(0.55)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _ivory,
          ),
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

/// "이 팩이 포함된 번들" — 이 팩을 담은 활성 번들이 하나라도 있을 때만
/// 나타난다. BundleCard(홈 탭 "번들 상품" 섹션과 같은 위젯)가 카드 안에
/// 포함된 팩들의 표지/제목을 보여주려면 그 팩들의 StoryPack을 알아야
/// 하는데, 이 화면은 원래 [widget.pack] 하나만 갖고 있다 — 그래서
/// bundles가 도착하면 그 안의 packIds 전체를 한 번에 조회한다
/// (StoryPackRepository.fetchPacksByIds). bundles의 id 구성이 실제로
/// 바뀔 때만 다시 조회한다(매 리빌드마다 새로 조회하지 않는다).
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

/// 표지 이미지가 없거나 로드에 실패했을 때 쓰는 fallback — StoryPackCard와
/// 같은 브랜드 그라디언트 + 장르 아이콘.
class _CoverFallback extends StatelessWidget {
  final GenreStyle genreStyle;

  const _CoverFallback({required this.genreStyle});

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
        child: Icon(
          genreStyle.icon,
          color: Colors.white.withOpacity(0.5),
          size: 96,
        ),
      ),
    );
  }
}
