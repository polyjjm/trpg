import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_scope.dart';
import '../../core/state/game_state.dart';
import '../../core/state/game_state_scope.dart';
import '../../core/state/reading_progress_repository.dart';
import '../../features/catalog/models/story_pack.dart';
import '../shared/data/reader_prefs_repository.dart';
import '../shared/data/story_reader_repository.dart';
import '../shared/models/reader_prefs.dart';
import '../shared/paywall.dart';
import '../shared/reader_back_button.dart';
import '../shared/scene_frame.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);
const Color _coral = Color(0xFFFF6B4A);

/// 두 쪽 펼침을 시도하는 최소 폭 — SceneFrame의 데스크톱 기준과 같은 값이다.
const double _spreadBreakpoint = 1100;

/// storyPack.type == 'linear'인 팩의 리더 화면. 선택지가 없고, node.nextNodeId
/// 체인을 따라 "다음" 버튼 하나로만 진행한다 — nextNodeId가 null이면 마지막
/// 페이지라는 뜻이라 "완료" 버튼을 보여준다.
///
/// 배경 이미지가 없는 페이지를 데스크톱에서 볼 때, readerPrefs.pageMode가
/// 'spread'면 **두 페이지를 한 화면에 펼친다** — 왼쪽에 현재 페이지, 오른쪽에
/// 다음 페이지. 그래서 "다음"은 두 페이지를 건너뛴다(오른쪽까지 이미 읽었으니까).
/// 배경 이미지가 있는 페이지는 시네마틱 레이아웃이라 펼치지 않는다.
class LinearReader extends StatefulWidget {
  final StoryPack pack;

  const LinearReader({super.key, required this.pack});

  @override
  State<LinearReader> createState() => _LinearReaderState();
}

class _LinearReaderState extends State<LinearReader> {
  final StoryReaderRepository _repository = StoryReaderRepository();
  final ReadingProgressRepository _progressRepository = ReadingProgressRepository();

  /// 펼침 여부를 정하려면 이 화면도 pageMode를 알아야 한다 — SceneFrame이
  /// 자기 안에서 구독하는 것과 같은 문서를 여기서도 본다(문서 하나에 대한
  /// 구독이 둘이 되지만, Firestore 로컬 캐시가 같은 스냅샷을 공유한다).
  final ReaderPrefsRepository _prefsRepository = ReaderPrefsRepository();
  StreamSubscription<ReaderPrefs>? _prefsSub;
  ReaderPrefs _prefs = ReaderPrefs.defaults;
  bool _resolvedUid = false;

  Map<String, ResolvedStoryNode> _nodesById = {};

  /// 페이지 순서(order 오름차순) — "12페이지", "12 / 34" 표기를 만들려면 순서가 필요하다.
  List<String> _orderedIds = const [];

  String? _currentNodeId;
  String? _entryNodeId;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedUid) return;
    _resolvedUid = true;
    final uid = AuthScope.of(context).userId;
    if (uid != null) {
      _prefsSub = _prefsRepository.watch(uid).listen((prefs) {
        if (mounted) setState(() => _prefs = prefs);
      });
    }
  }

  @override
  void dispose() {
    _prefsSub?.cancel();
    super.dispose();
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
          _errorMessage = '아직 읽을 수 있는 페이지가 없어요.';
          _loading = false;
        });
        return;
      }

      // 리딩 세션 시작 — 노드 이동마다가 아니라 팩을 여는 시점에 딱 한 번만.
      unawaited(_repository.incrementViewCount(widget.pack.id));

      // fetchPublishedNodes()가 이미 order(=페이지 순서) 오름차순으로 정렬해 반환한다.
      final entryId = nodes.first.node.id;
      final nodesById = {for (final n in nodes) n.node.id: n};
      final orderedIds = [for (final n in nodes) n.node.id];

      final resumeNodeId = await _resolveResumeNodeId(
        entryId: entryId,
        validNodeIds: nodesById.keys.toSet(),
      );
      if (!mounted) return;

      setState(() {
        _nodesById = nodesById;
        _orderedIds = orderedIds;
        _entryNodeId = entryId;
        _currentNodeId = resumeNodeId;
        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('LinearReader._load() 실패: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = '스토리를 불러오지 못했어요.';
        _loading = false;
      });
    }
  }

  /// 이 팩에 저장된 위치가 있으면 그 페이지에서, 없으면 [entryId](첫 페이지)부터.
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

  /// [alsoVisited]는 두 쪽 펼침에서 오른쪽에 이미 보여 준 페이지다 — 넘어가기
  /// 전에 그 페이지도 읽은 것으로 기록해야 진행률과 무료 미리보기 카운트가 화면과
  /// 어긋나지 않는다.
  Future<void> _goToNext(String nextNodeId, {String? alsoVisited}) async {
    if (!_nodesById.containsKey(nextNodeId)) return;

    final gameState = GameStateScope.of(context);
    final pack = widget.pack;
    final previewLimitReached = !pack.isFree &&
        !gameState.ownsPack(pack.id) &&
        (gameState.progressFor(pack.id)?.visitedNodeCount ?? 0) >= pack.previewNodeLimit;

    if (previewLimitReached) {
      final purchased = await requestPackPurchase(context, gameState, pack);
      if (!purchased || !mounted) return;
    }

    if (alsoVisited != null && _nodesById.containsKey(alsoVisited)) {
      gameState.recordNodeVisit(packId: pack.id, nodeId: alsoVisited);
    }

    final isLastPage = _nodesById[nextNodeId]?.node.nextNodeId == null;
    gameState.recordNodeVisit(
      packId: pack.id,
      nodeId: nextNodeId,
      completed: isLastPage,
    );
    unawaited(_persistProgress(gameState));
    if (!mounted) return;
    setState(() => _currentNodeId = nextNodeId);
  }

  /// 첫 페이지로 되돌린다 — InteractiveReader의 '처음부터'와 같은 흐름이다.
  /// 이 팩의 진행 상황만 초기화하고(resetPackProgress) 화면을 진입 페이지로
  /// 돌린다.
  void _restart() {
    final entryId = _entryNodeId;
    if (entryId == null) return;
    final gameState = GameStateScope.of(context);
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

  String? _chapterLabelFor(String nodeId) {
    final index = _orderedIds.indexOf(nodeId);
    return index >= 0 ? '${index + 1}페이지' : null;
  }

  String? _progressLabelFor(String nodeId) {
    final index = _orderedIds.indexOf(nodeId);
    if (index < 0 || _orderedIds.isEmpty) return null;
    return '${index + 1} / ${_orderedIds.length}';
  }

  void _handlePageModeChanged(String mode) {
    if (!mounted || _prefs.pageMode == mode) return;
    setState(() => _prefs = _prefs.copyWith(pageMode: mode));
  }

  bool _hasNoBackground(ResolvedStoryNode node) {
    final url = node.backgroundImageUrl;
    return url == null || url.isEmpty;
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _ivory));
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(
        child: Text(errorMessage, style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.7))),
      );
    }

    final current = _nodesById[_currentNodeId];
    if (current == null) {
      return Center(
        child: Text('페이지를 찾을 수 없어요.', style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.7))),
      );
    }

    final nextNodeId = current.node.nextNodeId;
    final nextNode = nextNodeId == null ? null : _nodesById[nextNodeId];

    // 두 페이지를 펼치는 조건: 데스크톱 폭 + 두 페이지 모두 배경 이미지 없음 +
    // pageMode == spread + 다음 페이지가 실제로 존재. 하나라도 어긋나면 한 쪽이다.
    final canSpread = MediaQuery.sizeOf(context).width >= _spreadBreakpoint &&
        _prefs.isSpread &&
        _hasNoBackground(current) &&
        nextNode != null &&
        _hasNoBackground(nextNode);

    if (!canSpread) {
      return SceneFrame(
        key: ValueKey(current.node.id),
        blocks: current.node.blocks,
        backgroundImageUrl: current.backgroundImageUrl,
        effects: current.node.effects,
        sfxUrl: current.sfxUrl,
        ttsAllowed: widget.pack.ttsEnabled,
        simplifiedSettings: true,
        chapterLabel: _chapterLabelFor(current.node.id),
        progressLabel: _progressLabelFor(current.node.id),
        onPageModeChanged: _handlePageModeChanged,
        actionAreaBuilder: (context) => _ActionRow(
          isLast: nextNodeId == null,
          onRestart: _restart,
          onNext: nextNodeId == null
              ? () => Navigator.pop(context)
              : () => _goToNext(nextNodeId),
        ),
      );
    }

    // 왼쪽 = 현재 페이지, 오른쪽 = 다음 페이지. 두 페이지의 블록을 이어 붙여
    // 넘기고 경계 인덱스를 알려주면 SceneFrame이 그 지점에서 쪽을 자른다
    // (타이핑은 왼쪽 페이지부터 순서대로 이어진다).
    final afterId = nextNode.node.nextNodeId;

    return SceneFrame(
      key: ValueKey('${current.node.id}+${nextNode.node.id}'),
      blocks: [...current.node.blocks, ...nextNode.node.blocks],
      spreadSplitIndex: current.node.blocks.length,
      backgroundImageUrl: null,
      effects: current.node.effects,
      sfxUrl: current.sfxUrl,
      ttsAllowed: widget.pack.ttsEnabled,
      simplifiedSettings: true,
      chapterLabel: _chapterLabelFor(current.node.id),
      progressLabel: _progressLabelFor(current.node.id),
      secondaryChapterLabel: _chapterLabelFor(nextNode.node.id),
      secondaryProgressLabel: _progressLabelFor(nextNode.node.id),
      onPageModeChanged: _handlePageModeChanged,
      actionAreaBuilder: (context) => _ActionRow(
        isLast: afterId == null,
        onRestart: _restart,
        onNext: afterId == null
            ? () => Navigator.pop(context)
            : () => _goToNext(afterId, alsoVisited: nextNode.node.id),
      ),
    );
  }
}

/// 지면 아래 액션 줄 — 마지막 페이지에서만 "처음부터"를 같이 보여준다.
///
/// 인터랙티브는 엔딩에서 '처음부터'가 나오는데 선형은 마지막에 '완료'뿐이라
/// 다시 읽을 길이 없었다. 완료로 나가면 진행 위치가 마지막 페이지에 남아
/// 상세 화면에서 '이어보기'를 눌러도 곧장 마지막 페이지로 돌아온다.
class _ActionRow extends StatelessWidget {
  final bool isLast;
  final VoidCallback onRestart;
  final VoidCallback onNext;

  const _ActionRow({
    required this.isLast,
    required this.onRestart,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isLast) ...[
          _GhostButton(label: '처음부터', onTap: onRestart),
          const SizedBox(width: 10),
        ],
        _NextButton(label: isLast ? '완료' : '다음', isLast: isLast, onTap: onNext),
      ],
    );
  }
}

/// 보조 동작 — 골드 인디케이터 없이 글자만. 같은 줄의 '완료'가 주 동작이라
/// 둘이 같은 무게로 보이면 안 된다.
class _GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostButton({required this.label, required this.onTap});

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _ivory.withOpacity(_hovered ? 0.95 : 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// "다음"/"완료" 버튼 — 인터랙티브 선택지와 같은 시각 언어(왼쪽 골드 2px
/// 인디케이터 + 옅은 유리 채움). 폭은 전체가 아니라 글자에 맞춰 오른쪽에
/// 붙인다 — 지면 아래에서 다음 장으로 넘기는 동작이라 오른쪽이 자연스럽다.
class _NextButton extends StatefulWidget {
  final String label;
  final bool isLast;
  final VoidCallback onTap;

  const _NextButton({required this.label, required this.isLast, required this.onTap});

  @override
  State<_NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<_NextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(_hovered ? 0.10 : 0.05),
              border: Border(
                left: BorderSide(
                  color: _hovered ? _coral : _gold.withOpacity(0.55),
                  width: 2,
                ),
              ),
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ivory,
                  ),
                ),
                if (!widget.isLast) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 19, color: _gold.withOpacity(0.8)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
