import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_scope.dart';
import '../../core/state/game_state.dart';
import '../../core/state/game_state_scope.dart';
import '../../core/state/reading_progress_repository.dart';
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
  final ReadingProgressRepository _progressRepository =
      ReadingProgressRepository();

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

      // 리딩 세션 시작 — 노드 이동마다가 아니라 팩을 여는 시점에 딱 한 번만.
      unawaited(_repository.incrementViewCount(widget.pack.id));

      // fetchPublishedNodes()가 이미 order 오름차순으로 정렬해 반환한다.
      final entryId = nodes.first.node.id;
      final nodesById = {for (final n in nodes) n.node.id: n};

      final resumeNodeId = await _resolveResumeNodeId(
        entryId: entryId,
        validNodeIds: nodesById.keys.toSet(),
      );
      if (!mounted) return;

      setState(() {
        _nodesById = nodesById;
        _entryNodeId = entryId;
        _currentNodeId = resumeNodeId;
        _loading = false;
      });
    } catch (e, stackTrace) {
      // catch (_)로 예외 자체를 버리면 화면엔 "불러오지 못했어요"만 남고 콘솔에도
      // 아무것도 안 찍혀서(권한 거부/색인 누락/필드 타입 불일치 등) 원인을 전혀
      // 알 수 없었다 — 실제 예외를 콘솔에 남긴다.
      debugPrint('InteractiveReader._load() 실패: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = '스토리를 불러오지 못했어요.';
        _loading = false;
      });
    }
  }

  /// 이 팩에 저장된 위치가 있으면 그 노드에서, 없으면 [entryId](처음)부터
  /// 시작한다. 메모리(GameState — 게스트, 또는 이번 세션에 StoryPackDetailPage가
  /// 이미 미리 불러와 채워 둔 로그인 사용자)를 먼저 보고, 거기 없을 때만
  /// Firestore(users/{uid}/readingProgress/{packId})를 확인한다.
  Future<String> _resolveResumeNodeId({
    required String entryId,
    required Set<String> validNodeIds,
  }) async {
    final gameState = GameStateScope.of(context);
    var progress = gameState.progressFor(widget.pack.id);

    if (progress == null) {
      final uid = AuthScope.of(context).userId;
      if (uid != null) {
        final loaded = await _progressRepository.load(uid, widget.pack.id);
        if (!mounted) return entryId;
        if (loaded != null) {
          gameState.seedPackProgress(widget.pack.id, loaded);
          progress = loaded;
        }
      }
    }

    final savedNodeId = progress?.currentNodeId;
    if (savedNodeId != null && validNodeIds.contains(savedNodeId)) {
      return savedNodeId;
    }
    return entryId;
  }

  Future<void> _handleChoice(Choice choice) async {
    if (!_nodesById.containsKey(choice.nextNodeId)) return;

    final gameState = GameStateScope.of(context);
    final pack = widget.pack;
    final previewLimitReached =
        !pack.isFree &&
        !gameState.ownsPack(pack.id) &&
        (gameState.progressFor(pack.id)?.visitedNodeCount ?? 0) >=
            pack.previewNodeLimit;

    if (previewLimitReached) {
      final purchased = await requestPackPurchase(context, gameState, pack);
      if (!purchased || !mounted) return;
    }

    final targetChoices =
        _nodesById[choice.nextNodeId]?.node.choices ?? const <Choice>[];
    gameState.recordNodeVisit(
      packId: pack.id,
      nodeId: choice.nextNodeId,
      completed: targetChoices.isEmpty,
    );
    unawaited(_persistProgress(gameState));
    if (!mounted) return;
    setState(() => _currentNodeId = choice.nextNodeId);
  }

  void _restart() {
    final entryId = _entryNodeId;
    if (entryId == null) return;
    final gameState = GameStateScope.of(context);
    gameState.resetProgress();
    gameState.resetPackProgress(widget.pack.id, entryId);
    unawaited(_persistProgress(gameState));
    setState(() => _currentNodeId = entryId);
  }

  /// 로그인 사용자만 Firestore에 저장한다 — 게스트는 GameState의 메모리
  /// 상태만으로 이번 세션 안에서의 팩별 분리를 이미 만족한다.
  Future<void> _persistProgress(GameState gameState) async {
    final uid = AuthScope.of(context).userId;
    if (uid == null) return;
    final progress = gameState.progressFor(widget.pack.id);
    if (progress == null) return;
    try {
      await _progressRepository.save(uid, widget.pack.id, progress);
    } catch (e) {
      debugPrint('읽기 진행 상황 저장 실패: $e');
    }
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
