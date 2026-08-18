import 'package:flutter/material.dart';

import '../../../core/state/game_state.dart';
import '../../../core/state/game_state_scope.dart';
import '../../../reader/interactive/interactive_reader.dart';
import '../../../reader/linear/linear_reader.dart';
import '../../story/data/story_nodes.dart';
import '../models/genre_style.dart';
import '../models/story_pack.dart';

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
class StoryPackDetailPage extends StatelessWidget {
  final StoryPack pack;

  const StoryPackDetailPage({super.key, required this.pack});

  @override
  Widget build(BuildContext context) {
    final gameState = GameStateScope.of(context);
    final owned = pack.isFree || gameState.ownsPack(pack.id);

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
                  style: TextStyle(fontSize: 14, height: 1.6, color: Colors.white.withOpacity(0.86)),
                ),
                const SizedBox(height: 22),
                _MetadataRow(pack: pack, gameState: gameState),
                const SizedBox(height: 22),
                if (!owned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '구매 전 ${pack.previewNodeLimit}개 노드까지 무료로 미리볼 수 있어요',
                      style: TextStyle(fontSize: 12.5, color: _ivory.withOpacity(0.68)),
                    ),
                  ),
                _PrimaryActionButton(
                  label: owned ? '읽기 시작' : '결제하기',
                  onTap: () => _handleAction(context, owned),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, bool owned) {
    if (owned) {
      final reader = pack.format == StoryPackFormat.linear
          ? LinearReader(pack: pack)
          : InteractiveReader(pack: pack);
      Navigator.push(context, MaterialPageRoute(builder: (_) => reader));
      return;
    }
    // 결제 기능은 아직 없다 — 스텁.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('결제 기능은 아직 준비 중이에요.')),
    );
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
              child: Align(
                alignment: Alignment.topLeft,
                child: _BackButton(),
              ),
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
                _GenreTypeBadge(genreStyle: genreStyle, typeLabel: pack.format.label),
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
                  style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.75)),
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
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.38)),
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
        style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 진행률/엔딩 발견/가격을 나란히 보여주는 요약 행.
///
/// - 가격은 실데이터(pack.price/isFree)를 그대로 쓴다.
/// - 진행률은 아직 팩별로 추적되지 않는다 — GameState가 앱 전체에서 하나의
///   진행 상황(currentNodeId)만 갖고 있고, 리더 앱이 실제 팩별 콘텐츠를
///   읽지 않는 지금 아키텍처의 한계다. 여기서는 그 전역 신호를 그대로
///   재사용한 placeholder다 — 팩별 진행 상황이 생기면 pack.id로 좁혀야 한다.
/// - 엔딩 발견 개수는 인터랙티브 타입에서만 보여주지만, 애초에 "엔딩"이라는
///   개념 자체가 실제 콘텐츠 모델(AdminStoryNode)에도 GameState에도 없어서
///   항상 0으로 표시되는 고정 placeholder다. 실제 엔딩 추적 시스템이 생기기
///   전까지는 숫자가 절대 바뀌지 않는다.
class _MetadataRow extends StatelessWidget {
  final StoryPack pack;
  final GameState gameState;

  const _MetadataRow({required this.pack, required this.gameState});

  @override
  Widget build(BuildContext context) {
    final hasProgress = gameState.currentNodeId != storyStartNodeId;

    final items = <Widget>[
      _MetadataItem(label: '진행률', value: hasProgress ? '진행 중' : '시작 전'),
    ];
    if (pack.format == StoryPackFormat.interactive) {
      items.add(const _MetadataItem(label: '엔딩 발견', value: '0개'));
    }
    items.add(_MetadataItem(label: '가격', value: pack.isFree ? '무료' : '₩${pack.price}'));

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
        Text(label, style: TextStyle(fontSize: 11, color: _ivory.withOpacity(0.55))),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ivory)),
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
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
        child: Icon(genreStyle.icon, color: Colors.white.withOpacity(0.5), size: 96),
      ),
    );
  }
}
