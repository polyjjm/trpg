import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_scope.dart';
import '../../core/state/game_state.dart';
import '../../core/state/game_state_scope.dart';
import '../../core/state/reading_progress_repository.dart';
import '../../features/catalog/models/story_pack.dart';
import '../shared/data/story_reader_repository.dart';
import '../shared/paywall.dart';
import '../shared/reader_back_button.dart';
import '../shared/scene_frame.dart';

const Color _ivory = Color(0xFFE2D4BF);
const List<Color> _brandGradient = [Color(0xFFFF6B4A), Color(0xFFFFB648)];

/// storyPack.type == 'linear'인 팩의 리더 화면. 선택지가 없고, node.nextNodeId
/// 체인을 따라 "다음" 버튼 하나로만 진행한다 — nextNodeId가 null이면 마지막
/// 챕터라는 뜻이라 "완료" 버튼을 보여준다.
class LinearReader extends StatefulWidget {
  final StoryPack pack;

  const LinearReader({super.key, required this.pack});

  @override
  State<LinearReader> createState() => _LinearReaderState();
}

class _LinearReaderState extends State<LinearReader> {
  final StoryReaderRepository _repository = StoryReaderRepository();
  final ReadingProgressRepository _progressRepository =
      ReadingProgressRepository();

  Map<String, ResolvedStoryNode> _nodesById = {};
  String? _currentNodeId;
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
          _errorMessage = '아직 읽을 수 있는 챕터가 없어요.';
          _loading = false;
        });
        return;
      }

      // 리딩 세션 시작 — 노드 이동마다가 아니라 팩을 여는 시점에 딱 한 번만.
      unawaited(_repository.incrementViewCount(widget.pack.id));

      // fetchPublishedNodes()가 이미 order(=챕터 순서) 오름차순으로 정렬해 반환한다.
      final entryId = nodes.first.node.id;
      final nodesById = {for (final n in nodes) n.node.id: n};

      final resumeNodeId = await _resolveResumeNodeId(
        entryId: entryId,
        validNodeIds: nodesById.keys.toSet(),
      );
      if (!mounted) return;

      setState(() {
        _nodesById = nodesById;
        _currentNodeId = resumeNodeId;
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

  /// InteractiveReader._resolveResumeNodeId와 같다 — 이 팩에 저장된 위치가
  /// 있으면 그 챕터에서, 없으면 [entryId](첫 챕터)부터 시작한다.
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

  Future<void> _goToNext(String nextNodeId) async {
    if (!_nodesById.containsKey(nextNodeId)) return;

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

    final isLastChapter = _nodesById[nextNodeId]?.node.nextNodeId == null;
    gameState.recordNodeVisit(
      packId: pack.id,
      nodeId: nextNodeId,
      completed: isLastChapter,
    );
    unawaited(_persistProgress(gameState));
    if (!mounted) return;
    setState(() => _currentNodeId = nextNodeId);
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
          '챕터를 찾을 수 없어요.',
          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.7)),
        ),
      );
    }

    final nextNodeId = current.node.nextNodeId;

    return SceneFrame(
      key: ValueKey(current.node.id),
      blocks: current.node.blocks,
      backgroundImageUrl: current.backgroundImageUrl,
      effects: current.node.effects,
      sfxUrl: current.sfxUrl,
      ttsAllowed: widget.pack.ttsEnabled,
      actionAreaBuilder: (context) => _NextButton(
        label: nextNodeId == null ? '완료' : '다음',
        onTap: nextNodeId == null
            ? () => Navigator.pop(context)
            : () => _goToNext(nextNodeId),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NextButton({required this.label, required this.onTap});

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
