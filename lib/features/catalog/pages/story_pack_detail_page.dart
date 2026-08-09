import 'package:flutter/material.dart';

import '../../../core/state/game_state_scope.dart';
import '../../story/data/story_nodes.dart';
import '../../story/widgets/story_page.dart';
import '../models/story_pack.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 이야기 팩 상세 화면. 기존 MainPage의 '새 게임/이어하기' 역할을 흡수해,
/// 클라우드 세이브 진행 상황을 보여주고 그 상태에 맞는 액션 버튼으로 게임플레이에
/// 진입시킨다. 유료 팩도 미구매 상태로 바로 들어갈 수 있으며, 무료 미리보기 한도는
/// StoryPage 안에서 노드 이동 시점에 따로 검사한다.
class StoryPackDetailPage extends StatelessWidget {
  final StoryPack pack;

  const StoryPackDetailPage({super.key, required this.pack});

  @override
  Widget build(BuildContext context) {
    final gameState = GameStateScope.of(context);
    final hasProgress = gameState.currentNodeId != storyStartNodeId;
    final currentNode = storyNodes[gameState.currentNodeId];
    final owned = pack.isFree || gameState.ownsPack(pack.id);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(pack.coverImage, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.20),
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.92),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    pack.format.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _gold,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pack.title,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: _ivory,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pack.authorName,
                    style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.72)),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    pack.description,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: Colors.white.withOpacity(0.86),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        hasProgress ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        size: 16,
                        color: _ivory.withOpacity(0.82),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hasProgress && currentNode != null
                              ? '진행 중: ${currentNode.dayLabel} · ${currentNode.title}'
                              : '시작 전',
                          style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.88)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    pack.isFree ? '무료' : '₩${pack.price}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _gold,
                    ),
                  ),
                  if (!owned) ...[
                    const SizedBox(height: 4),
                    Text(
                      '구매 전 ${pack.previewNodeLimit}개 노드까지 무료로 미리볼 수 있어요',
                      style: TextStyle(fontSize: 12.5, color: _ivory.withOpacity(0.68)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => _handleAction(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        hasProgress ? '이어하기' : '시작하기',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoryPage(pack: pack)),
    );
  }
}
