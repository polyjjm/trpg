import 'package:flutter/material.dart';

import '../../core/state/game_state_scope.dart';
import '../../features/catalog/models/story_pack.dart';
import '../shared/data/story_reader_repository.dart';
import '../shared/models/choice.dart';
import '../shared/paywall.dart';
import '../shared/reader_back_button.dart';
import '../shared/scene_frame.dart';

const Color _ivory = Color(0xFFE2D4BF);
const List<Color> _brandGradient = [Color(0xFFFF6B4A), Color(0xFFFFB648)];

/// storyPack.type == 'interactive'인 팩의 리더 화면. 노드를 전부 미리 읽어와
/// 메모리에 올려 두고(팩 하나 분량이라 부담 없다), choice.nextNodeId를 따라
/// 화면 안에서 노드를 스위치한다 — 노드마다 새 라우트를 쌓지 않는다(뒤로가기를
/// 누르면 스토리 중간이 아니라 곧장 상세 화면으로 나가야 하므로).
class InteractiveReader extends StatefulWidget {
  final StoryPack pack;

  const InteractiveReader({super.key, required this.pack});

  @override
  State<InteractiveReader> createState() => _InteractiveReaderState();
}

class _InteractiveReaderState extends State<InteractiveReader> {
  final StoryReaderRepository _repository = StoryReaderRepository();

  Map<String, ResolvedStoryNode> _nodesById = {};
  String? _currentNodeId;
  String? _entryNodeId;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final nodes = await _repository.fetchPublishedNodes(
        widget.pack.id,
        packDefaultBackgroundImageId: widget.pack.defaultBackgroundImage,
      );
      if (!mounted) return;

      if (nodes.isEmpty) {
        setState(() {
          _errorMessage = '아직 읽을 수 있는 노드가 없어요.';
          _loading = false;
        });
        return;
      }

      // fetchPublishedNodes()가 이미 order 오름차순으로 정렬해 반환한다.
      final entryId = nodes.first.node.id;
      setState(() {
        _nodesById = {for (final n in nodes) n.node.id: n};
        _entryNodeId = entryId;
        _currentNodeId = entryId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '스토리를 불러오지 못했어요.';
        _loading = false;
      });
    }
  }

  Future<void> _handleChoice(Choice choice) async {
    if (!_nodesById.containsKey(choice.nextNodeId)) return;

    final gameState = GameStateScope.of(context);
    final pack = widget.pack;
    final previewLimitReached =
        !pack.isFree &&
        !gameState.ownsPack(pack.id) &&
        gameState.visitedNodeCount >= pack.previewNodeLimit;

    if (previewLimitReached) {
      final purchased = await requestPackPurchase(context, gameState, pack);
      if (!purchased || !mounted) return;
    }

    gameState.goToNode(choice.nextNodeId);
    if (!mounted) return;
    setState(() => _currentNodeId = choice.nextNodeId);
  }

  void _restart() {
    final entryId = _entryNodeId;
    if (entryId == null) return;
    GameStateScope.of(context).resetProgress(entryId);
    setState(() => _currentNodeId = entryId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [_buildBody(context), const ReaderBackButton()]),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _ivory));
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(
        child: Text(
          errorMessage,
          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.7)),
        ),
      );
    }

    final current = _nodesById[_currentNodeId];
    if (current == null) {
      return Center(
        child: Text(
          '노드를 찾을 수 없어요.',
          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.7)),
        ),
      );
    }

    final choices = current.node.choices ?? const <Choice>[];

    return SceneFrame(
      key: ValueKey(current.node.id),
      blocks: current.node.blocks,
      backgroundImageUrl: current.backgroundImageUrl,
      effects: current.node.effects,
      sfxUrl: current.sfxUrl,
      ttsAllowed: widget.pack.ttsEnabled,
      actionAreaBuilder: (context) => choices.isEmpty
          ? _EndingActionArea(onRestart: _restart)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < choices.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _ChoiceButton(
                    label: choices[i].label,
                    onTap: () => _handleChoice(choices[i]),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ChoiceButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
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
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
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

/// 새 스토리 그래프에는 story_node.dart의 옛 isEnding 같은 명시적 플래그가
/// 없다 — choices가 비어 있으면(작가가 안 넣었거나 못 넣었거나) 그 자체가
/// 막다른 끝이라는 뜻이라, "처음부터"만 보여준다.
class _EndingActionArea extends StatelessWidget {
  final VoidCallback onRestart;

  const _EndingActionArea({required this.onRestart});

  @override
  Widget build(BuildContext context) {
    return _ChoiceButton(label: '처음부터', onTap: onRestart);
  }
}
