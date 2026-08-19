import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:graphview/graphview.dart';

import '../data/admin_story_repository.dart';
import '../data/node_edit_session_cache.dart';
import '../data/node_id_suggestion.dart';
import '../models/admin_node_choice.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/story_pack_type.dart';
import 'admin_theme.dart';
import 'choice_edit_form.dart';
import 'choice_target_picker.dart';
import 'labeled_field.dart';

/// "구조 보기" — 사이드바+에디터 대신 노드 전체를 그래프로 보여준다.
/// [graphview] 패키지의 SugiyamaAlgorithm은 오직 레이아웃 계산(각 노드의
/// position/size)에만 쓴다 — 패키지 내장 GraphView 위젯은 간선에 라벨을
/// 달거나 탭/드래그를 받는 걸 지원하지 않아서, 실제 렌더링(노드 박스, 간선
/// 선/라벨, 드래그로 잇기)은 Stack + CustomPaint로 직접 그린다.
///
/// [nodes]는 반드시 저장된 노드 + 세션 캐시 초안을 합친 목록
/// (story_tab_view.dart의 displaySummaries)이어야 한다 — id 자동 제안
/// 규칙(suggestSequentialNodeIds)이 요구하는 "부분적으로 섞이지 않은 목록"
/// 규칙을 여기서도 그대로 따른다.
class StoryMapView extends StatefulWidget {
  final String packId;
  final StoryPackType packType;
  final List<AdminStoryNodeSummary> nodes;
  final Set<String> unsavedNodeIds;
  final NodeEditSessionCache sessionCache;
  final AdminStoryRepository repository;

  /// 노드 박스를 탭했을 때 — 부모(StoryTabView)가 "노드별로 쓰기" 모드로
  /// 돌아가 이 노드를 연다(사이드바에서 노드를 고르는 것과 동일한 동작).
  final ValueChanged<String> onOpenNode;

  /// "+"에서 빈 캔버스로 드래그해 새 노드를 만들었을 때 — (새 노드 id,
  /// 출발 노드 id, interactive면 출발 노드에 방금 생긴 선택지의 인덱스)를
  /// 넘긴다. 부모가 "노드별로 쓰기" 모드로 돌아가 이 노드를 열되, 헤더에
  /// "새 노드 ({sourceId}에서 연결됨)" 컨텍스트를 보여주고, 저장 시점에
  /// 그 선택지 문구가 비어 있으면 채우도록 안내한다
  /// (story_map_choice_popover_spec.md).
  final void Function(String newNodeId, String sourceId, int? choiceIndex)
  onNodeCreatedFromDrag;

  /// 세션 캐시가 바뀌었으니 다시 그려 달라는 신호 — 부모가 setState한다.
  final VoidCallback onChanged;

  const StoryMapView({
    super.key,
    required this.packId,
    required this.packType,
    required this.nodes,
    required this.unsavedNodeIds,
    required this.sessionCache,
    required this.repository,
    required this.onOpenNode,
    required this.onNodeCreatedFromDrag,
    required this.onChanged,
  });

  @override
  State<StoryMapView> createState() => _StoryMapViewState();
}

class _StoryMapViewState extends State<StoryMapView> {
  static const _nodeSize = Size(200, 72);
  static const _missingSize = Size(72, 40);

  /// 캔버스(InteractiveViewer 안쪽의 Stack을 감싼 SizedBox)의 RenderBox를
  /// 찾는 데 쓴다 — 팝오버를 노드 박스 옆에 앵커링하려면 그래프 로컬 좌표
  /// (layout의 Rect)를 화면 전역 좌표로 바꿔야 하는데, InteractiveViewer가
  /// 지금 어떤 pan/zoom 상태인지와 무관하게 정확한 값을 얻으려면 실제로 그
  /// 변환이 걸린 렌더 트리를 통해 localToGlobal을 태워야 한다.
  final GlobalKey _canvasKey = GlobalKey();

  Future<AdminStoryNode?> _loadNode(String nodeId) async {
    final cached = widget.sessionCache.get(widget.packId, nodeId);
    if (cached != null) return cached;
    return widget.repository.fetchNode(widget.packId, nodeId);
  }

  void _restage(AdminStoryNode node) {
    widget.sessionCache.put(widget.packId, node);
    widget.onChanged();
  }

  void _createFirstNode() {
    final newId = suggestSequentialNodeIds(const [], 1).first;
    final newNode = AdminStoryNode(id: newId, order: 0);
    widget.sessionCache.put(widget.packId, newNode);
    widget.onChanged();
    widget.onOpenNode(newId);
  }

  Rect? _globalRectForNode(String nodeId) {
    final canvasBox = _canvasKey.currentContext?.findRenderObject();
    if (canvasBox is! RenderBox || !canvasBox.attached) return null;
    final layout = _computeLayout(widget.nodes, widget.packType);
    final localRect = layout.nodeRects[nodeId];
    if (localRect == null) return null;
    return Rect.fromPoints(
      canvasBox.localToGlobal(localRect.topLeft),
      canvasBox.localToGlobal(localRect.bottomRight),
    );
  }

  /// "+" 탭(드래그 없음) — 노드 생성/이동 없이 그 자리에 인라인 팝업을 연다.
  /// 대상은 아직 안 정해졌으니 팝업의 "기존 노드 카드" 목록에서 골라야
  /// 선택지가 만들어진다(story_map_choice_popover_spec.md).
  Future<void> _handlePlusTap(String sourceId) async {
    await _openChoicePopover(sourceId: sourceId, prefilledTargetId: null);
  }

  /// "+"에서 기존 노드로 드래그 — 같은 팝업이 뜨되 대상이 이미 정해져
  /// 있다. 드롭 즉시 선택지를 만들어 스테이징해 두고(빈 라벨이어도), 팝업은
  /// 라벨을 마저 채우거나 대상을 바꾸는 용도로 연다.
  Future<void> _connectToExisting(String sourceId, String targetId) async {
    if (sourceId == targetId) return;
    await _openChoicePopover(sourceId: sourceId, prefilledTargetId: targetId);
  }

  /// "+"에서 빈 캔버스로 드래그해 드롭 — 새 노드를 만들고 바로 이어 붙인 뒤,
  /// Part 1 쓰기 카드로 곧장 연다(기존 동작 유지). 드롭 좌표 자체는 저장하지
  /// 않는다 — Sugiyama가 다음 레이아웃 재계산 때 알아서 배치하므로, 여기서는
  /// order만 "일단 맨 뒤"로 매겨 둔다.
  Future<void> _connectToNewNode(String sourceId) async {
    final takenIds = widget.nodes.map((n) => n.id).toSet();
    final newId = suggestSequentialNodeIds(takenIds, 1).first;
    final maxOrder = widget.nodes.isEmpty
        ? -1
        : widget.nodes.map((n) => n.order).reduce((a, b) => a > b ? a : b);
    final newNode = AdminStoryNode(id: newId, order: maxOrder + 1);
    widget.sessionCache.put(widget.packId, newNode);

    final sourceNode = await _loadNode(sourceId);
    int? choiceIndex;
    if (sourceNode != null) {
      if (widget.packType == StoryPackType.interactive) {
        sourceNode.choices.add(AdminNodeChoice(nextNodeId: newId));
        choiceIndex = sourceNode.choices.length - 1;
      } else {
        sourceNode.nextNodeId = newId;
      }
      widget.sessionCache.put(widget.packId, sourceNode);
    }
    if (!mounted) return;
    widget.onChanged();
    widget.onNodeCreatedFromDrag(newId, sourceId, choiceIndex);
  }

  /// "선택지 만들기" 인라인 팝업 — 탭 흐름과 드래그-투-기존노드 흐름이
  /// 공유하는 단 하나의 구현. [prefilledTargetId]가 null이면 탭 흐름(아직
  /// 선택지가 없다, 카드를 눌러야 생긴다) — non-null이면 드래그 흐름(드롭
  /// 즉시 만들어 스테이징해 둔 선택지를 이 팝업에서 마저 다듬는다).
  Future<void> _openChoicePopover({
    required String sourceId,
    required String? prefilledTargetId,
  }) async {
    final anchorRect = _globalRectForNode(sourceId);
    if (anchorRect == null || !mounted) return;

    final sourceNode = await _loadNode(sourceId);
    if (sourceNode == null || !mounted) return;

    int? choiceIndex;
    if (prefilledTargetId != null &&
        widget.packType == StoryPackType.interactive) {
      sourceNode.choices.add(AdminNodeChoice(nextNodeId: prefilledTargetId));
      choiceIndex = sourceNode.choices.length - 1;
      _restage(sourceNode);
    } else if (prefilledTargetId != null) {
      // linear 팩은 "선택지 목록"이 아니라 nextNodeId 하나뿐이다.
      sourceNode.nextNodeId = prefilledTargetId;
      _restage(sourceNode);
    }

    final isInteractive = widget.packType == StoryPackType.interactive;

    _showAnchoredPopover(
      anchorRect: anchorRect,
      builder: (close) => _ChoiceCreatePopoverCard(
        title: isInteractive ? '선택지 만들기' : '다음 노드 연결',
        showLabelSection: isInteractive,
        candidates: widget.nodes.where((c) => c.id != sourceId).toList(),
        initialLabel: choiceIndex != null
            ? sourceNode.choices[choiceIndex].label
            : '',
        autofocusLabel: choiceIndex != null,
        selectedTargetId: prefilledTargetId,
        onLabelLiveChanged: choiceIndex == null
            ? null
            : (value) {
                sourceNode.choices[choiceIndex!].label = value;
                _restage(sourceNode);
              },
        onSelectTarget: (targetId, labelText) {
          if (isInteractive) {
            if (choiceIndex != null) {
              sourceNode.choices[choiceIndex].nextNodeId = targetId;
              sourceNode.choices[choiceIndex].label = labelText;
            } else {
              sourceNode.choices.add(
                AdminNodeChoice(label: labelText, nextNodeId: targetId),
              );
            }
          } else {
            sourceNode.nextNodeId = targetId;
          }
          _restage(sourceNode);
          close();
        },
      ),
    );
  }

  /// 화면 전역 좌표 [anchorRect] 옆에 붙는 오버레이 팝업 — 바깥을 탭하면
  /// 아무 것도 만들지 않고 닫힌다(story_map_choice_popover_spec.md의 "팝업
  /// 바깥 클릭 → 취소" 규칙).
  void _showAnchoredPopover({
    required Rect anchorRect,
    required Widget Function(VoidCallback close) builder,
  }) {
    final overlayState = Overlay.of(context);
    late OverlayEntry entry;
    void close() {
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (overlayContext) {
        final screenSize = MediaQuery.sizeOf(overlayContext);
        const popoverWidth = 300.0;
        const estimatedHeight = 420.0;

        var left = anchorRect.right + 14;
        if (left + popoverWidth + 12 > screenSize.width) {
          left = anchorRect.left - popoverWidth - 14;
        }
        final maxLeft = math.max(12.0, screenSize.width - popoverWidth - 12);
        left = left.clamp(12.0, maxLeft);

        var top = anchorRect.top - 20;
        final maxTop = math.max(12.0, screenSize.height - estimatedHeight - 12);
        top = top.clamp(12.0, maxTop);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: popoverWidth,
              child: builder(close),
            ),
          ],
        );
      },
    );

    overlayState.insert(entry);
  }

  Future<void> _openEdgePopover(
    AdminStoryNode sourceNode,
    int? choiceIndex, {
    bool autofocusLabel = false,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _EdgePopover(
        sourceNode: sourceNode,
        choiceIndex: choiceIndex,
        candidates: widget.nodes,
        autofocusLabel: autofocusLabel,
        onStaged: () => _restage(sourceNode),
      ),
    );
  }

  Future<void> _handleEdgeTap(_LayoutEdge edge) async {
    final node = await _loadNode(edge.sourceId);
    if (node == null || !mounted) return;
    await _openEdgePopover(node, edge.choiceIndex);
  }

  /// 간선 위 라벨 칩 — 두 박스 중점에 뜬다. 선(CustomPaint) 자체는 탭을 못
  /// 받으니, "간선을 탭한다"는 요구사항은 실제로는 이 칩이 받는다.
  Widget _buildEdgeLabel(_LayoutEdge edge, Map<String, Rect> nodeRects) {
    final sourceRect = nodeRects[edge.sourceId];
    final targetRect = nodeRects[edge.targetKey];
    if (sourceRect == null || targetRect == null) {
      return const SizedBox.shrink();
    }
    final mid = Offset(
      (sourceRect.center.dx + targetRect.center.dx) / 2,
      (sourceRect.center.dy + targetRect.center.dy) / 2,
    );
    final text = edge.label.isEmpty ? (edge.broken ? '?' : '→') : edge.label;

    return Positioned(
      key: ValueKey(
        'edgelabel_${edge.sourceId}_${edge.choiceIndex}_${edge.targetKey}',
      ),
      left: mid.dx - 55,
      top: mid.dy - 12,
      width: 110,
      child: Center(
        child: InkWell(
          onTap: () => _handleEdgeTap(edge),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AdminColors.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: edge.broken ? AdminColors.danger : AdminColors.border,
              ),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: edge.broken ? AdminColors.danger : AdminColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('아직 노드가 없어요.', style: TextStyle(color: AdminColors.muted)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _createFirstNode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.gold,
                foregroundColor: Colors.white,
              ),
              child: const Text('+ 첫 노드 만들기'),
            ),
          ],
        ),
      );
    }

    final layout = _computeLayout(widget.nodes, widget.packType);
    final nodeById = {for (final n in widget.nodes) n.id: n};

    return ColoredBox(
      color: AdminColors.bg,
      child: InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(240),
        minScale: 0.25,
        maxScale: 2,
        child: SizedBox(
          key: _canvasKey,
          width: layout.canvasSize.width,
          height: layout.canvasSize.height,
          child: Stack(
            children: [
              // 빈 캔버스에 드롭했을 때(=새 노드 만들기)를 받는 배경 —
              // Stack에서 제일 먼저(맨 아래) 그려야, 노드 박스 위에 드롭하면
              // 그 노드의 DragTarget이 먼저 히트테스트되어 우선한다.
              Positioned.fill(
                child: DragTarget<String>(
                  onAcceptWithDetails: (details) =>
                      _connectToNewNode(details.data),
                  builder: (context, candidateData, rejectedData) =>
                      const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(layout.edges, layout.nodeRects),
                ),
              ),
              // 간선 라벨 칩을 노드 박스보다 먼저(= 아래 z-order에) 넣는다 —
              // Stack은 나중에 넣은 자식일수록 위에서 먼저 히트테스트되므로,
              // 순서가 반대였을 때는 라벨 칩의 사각 히트 영역이 노드 박스(와
              // 그 위의 "+" 핸들) 위에 겹쳐 탭을 가로챌 수 있었다 — 특히
              // 선택지가 여러 개라 간선이 부모 오른쪽 아래로 뻗을 때
              // (story_map_choice_popover_spec.md 후속 버그 리포트의 "선택지가
              // 있는 노드에서 +를 누르면 그중 하나의 편집 모드로 열린다" 증상).
              for (final edge in layout.edges)
                _buildEdgeLabel(edge, layout.nodeRects),
              for (final id in layout.nodeRects.keys)
                if (!id.startsWith('__missing__'))
                  _NodeBox(
                    key: ValueKey('node_$id'),
                    summary: nodeById[id]!,
                    rect: layout.nodeRects[id]!,
                    unsaved: widget.unsavedNodeIds.contains(id),
                    onTap: () => widget.onOpenNode(id),
                    onConnectRequested: (sourceId) =>
                        _connectToExisting(sourceId, id),
                  )
                else
                  _MissingBox(
                    key: ValueKey('missing_$id'),
                    rect: layout.nodeRects[id]!,
                  ),
              // "+" 핸들은 노드 박스 자신의 Stack에 중첩시키는 대신, 바깥
              // Stack의 맨 마지막(=항상 최상단 z-order) 자식으로 따로 뺐다 —
              // 중첩된 GestureDetector의 제스처 아레나 우선순위에 기대는
              // 대신, 어떤 노드든(간선이 0개든 여러 개든) "+"가 항상 다른
              // 무엇보다도 위에서 탭을 가로채도록 구조적으로 보장하기 위해서다
              // (실제로 겪은 버그 — 위 주석 참고).
              for (final id in layout.nodeRects.keys)
                if (!id.startsWith('__missing__'))
                  _PlusHandle(
                    key: ValueKey('plus_$id'),
                    nodeId: id,
                    rect: layout.nodeRects[id]!,
                    onTap: () => _handlePlusTap(id),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  _LayoutResult _computeLayout(
    List<AdminStoryNodeSummary> nodes,
    StoryPackType packType,
  ) {
    final graph = Graph()..isTree = false;
    final nodeObjs = <String, Node>{};

    for (final n in nodes) {
      final node = Node.Id(n.id);
      node.size = _nodeSize;
      graph.addNode(node);
      nodeObjs[n.id] = node;
    }

    final edgeInfos = <_LayoutEdge>[];
    final missingIds = <String>{};

    void addEdge(
      String sourceId,
      String? targetId,
      String label,
      int? choiceIndex,
    ) {
      if (targetId == null || targetId.isEmpty) return;
      final exists = nodeObjs.containsKey(targetId);
      final key = exists ? targetId : '__missing__$targetId';
      if (!exists) missingIds.add(targetId);
      edgeInfos.add(
        _LayoutEdge(
          sourceId: sourceId,
          targetKey: key,
          broken: !exists,
          label: label,
          choiceIndex: choiceIndex,
        ),
      );
    }

    for (final n in nodes) {
      if (packType == StoryPackType.interactive) {
        for (var i = 0; i < n.choices.length; i++) {
          addEdge(n.id, n.choices[i].nextNodeId, n.choices[i].label, i);
        }
      } else {
        addEdge(n.id, n.nextNodeId, '', null);
      }
    }

    for (final missingId in missingIds) {
      final key = '__missing__$missingId';
      final node = Node.Id(key);
      node.size = _missingSize;
      graph.addNode(node);
      nodeObjs[key] = node;
    }

    for (final e in edgeInfos) {
      final sourceNode = nodeObjs[e.sourceId];
      final targetNode = nodeObjs[e.targetKey];
      if (sourceNode == null || targetNode == null) continue;
      graph.addEdge(sourceNode, targetNode);
    }

    final config = SugiyamaConfiguration()
      ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM
      ..nodeSeparation = 36
      ..levelSeparation = 90;
    final algorithm = SugiyamaAlgorithm(config);
    final size = algorithm.run(graph, 40, 40);

    final rects = <String, Rect>{};
    nodeObjs.forEach((key, node) {
      rects[key] = Rect.fromLTWH(node.x, node.y, node.width, node.height);
    });

    return _LayoutResult(
      nodeRects: rects,
      edges: edgeInfos,
      canvasSize: Size(size.width + 80, size.height + 80),
    );
  }
}

class _LayoutEdge {
  final String sourceId;
  final String targetKey;
  final bool broken;
  final String label;

  /// interactive 팩에서만 값이 있다 — choices 배열 안 인덱스. linear면 null
  /// (nextNodeId는 인덱스 개념이 없다).
  final int? choiceIndex;

  _LayoutEdge({
    required this.sourceId,
    required this.targetKey,
    required this.broken,
    required this.label,
    required this.choiceIndex,
  });
}

class _LayoutResult {
  final Map<String, Rect> nodeRects;
  final List<_LayoutEdge> edges;
  final Size canvasSize;

  _LayoutResult({
    required this.nodeRects,
    required this.edges,
    required this.canvasSize,
  });
}

/// 노드 박스 — 미리보기(굵게) + id(흐리게), Part 3의 카드와 같은 패턴.
/// 전체를 DragTarget으로 감싸 다른 노드의 "+" 핸들 드롭을 받는다.
///
/// "+" 핸들은 더 이상 이 박스 안에 중첩되지 않는다 — [_PlusHandle] 참고.
/// 처음엔 이 박스의 Stack 맨 위에 중첩된 GestureDetector로 넣었었는데,
/// 간선이 있는 노드에서는 그 위에 겹쳐 그려지는 간선 라벨 칩이(같은 바깥
/// Stack에서 이 박스보다 나중에 추가돼 z-order가 더 위였다) 핸들의 탭을
/// 가로채 그 선택지 하나의 편집 모드가 열려버렸고, 간선이 하나도 없는
/// 노드에서도(원인을 픽셀 단위로 재현하지는 못했지만) 탭이 이 박스 자신의
/// onTap으로 새는 경우가 있었다 — 둘 다 "핸들의 우선순위가 박스 내부의
/// 중첩 구조와 바깥 Stack의 z-order 양쪽에 암묵적으로 의존한다"는 게
/// 근본 문제였다. 그래서 핸들을 아예 바깥 Stack의 별도 자식으로 빼서,
/// 노드/간선이 몇 개든 상관없이 구조적으로 항상 최상단에서 탭을 받도록
/// 바꿨다.
class _NodeBox extends StatelessWidget {
  final AdminStoryNodeSummary summary;
  final Rect rect;
  final bool unsaved;
  final VoidCallback onTap;
  final ValueChanged<String> onConnectRequested;

  const _NodeBox({
    required super.key,
    required this.summary,
    required this.rect,
    required this.unsaved,
    required this.onTap,
    required this.onConnectRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != summary.id,
        onAcceptWithDetails: (details) => onConnectRequested(details.data),
        builder: (context, candidateData, rejectedData) {
          final hovering = candidateData.isNotEmpty;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hovering ? AdminColors.gold : AdminColors.border,
                  width: hovering ? 2 : 1,
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.preview.isEmpty ? '(내용 없음)' : summary.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.ivory,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AdminColors.muted,
                        ),
                      ),
                    ],
                  ),
                  if (unsaved)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AdminColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "+" 핸들 — 바깥 Stack의 별도 자식(항상 노드 박스/간선 라벨보다 나중에
/// 추가되어 z-order가 가장 위)으로 렌더링된다(_NodeBox의 클래스 doc 참고).
/// [rect]는 이 핸들이 속한 노드의 박스 좌표 그대로 받아서, 예전에
/// _NodeBox 안에서 Positioned(bottom:-14,right:-14)로 잡던 것과 같은
/// 시각적 위치(박스 오른쪽 아래 모서리)를 바깥 좌표계 기준으로 재현한다.
///
/// 탭은 [onTap]으로 팝업을 연다(_StoryMapViewState._handlePlusTap). 드래그는
/// [Draggable] 자신의 인식기가 처리하고, 놓인 곳은 다른 노드의 DragTarget
/// (_NodeBox) 또는 빈 캔버스의 배경 DragTarget이 받는다 — 탭 인식기와
/// 드래그 인식기가 같은 제스처 아레나 안에서 경쟁하되(움직임 없이 손을
/// 떼면 탭이, 슬롭 이상 움직이면 드래그가 이긴다), 이제는 둘 다 이 위젯
/// 하나에만 걸려 있어서 바깥의 다른 위젯이 끼어들 여지가 없다.
class _PlusHandle extends StatelessWidget {
  final String nodeId;
  final Rect rect;
  final VoidCallback onTap;

  const _PlusHandle({
    required super.key,
    required this.nodeId,
    required this.rect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const handleSize = 22.0;
    // 박스의 오른쪽 아래 모서리 점 위에 핸들 중심이 오도록 — 목업들이
    // 보여주는 "모서리에 살짝 걸쳐 튀어나온" 자리와 같다.
    return Positioned(
      left: rect.right - handleSize / 2,
      top: rect.bottom - handleSize / 2,
      width: handleSize,
      height: handleSize,
      child: GestureDetector(
        onTap: onTap,
        child: Draggable<String>(
          data: nodeId,
          feedback: Material(
            color: Colors.transparent,
            child: Icon(
              Icons.add_circle_rounded,
              size: 26,
              color: AdminColors.gold,
            ),
          ),
          childWhenDragging: Icon(
            Icons.add_circle_outline_rounded,
            size: handleSize,
            color: AdminColors.muted,
          ),
          child: Container(
            width: handleSize,
            height: handleSize,
            decoration: BoxDecoration(
              color: AdminColors.gold,
              shape: BoxShape.circle,
              border: Border.all(color: AdminColors.panel, width: 2),
            ),
            child: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// 존재하지 않는 노드를 가리키는 참조 — "?" 박스. 실제 편집은 여기가 아니라
/// 이 박스로 이어지는 간선(라벨 칩)을 탭해서 한다 — 소스 노드 문맥이 있어야
/// 어떤 선택지를 고칠지 알 수 있기 때문이다.
class _MissingBox extends StatelessWidget {
  final Rect rect;

  const _MissingBox({required super.key, required this.rect});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AdminColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.danger, width: 1.4),
        ),
        child: Text(
          '?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AdminColors.danger,
          ),
        ),
      ),
    );
  }
}

/// 간선(선 + 화살촉)을 그린다 — 끊어진 참조는 빨간 점선, 정상 간선은 코랄
/// 실선. 라벨/탭은 CustomPaint가 못 받으니 [_StoryMapViewState._buildEdgeLabel]가
/// 같은 좌표계 위에 별도 칩으로 그린다.
class _EdgePainter extends CustomPainter {
  final List<_LayoutEdge> edges;
  final Map<String, Rect> nodeRects;

  _EdgePainter(this.edges, this.nodeRects);

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final sourceRect = nodeRects[edge.sourceId];
      final targetRect = nodeRects[edge.targetKey];
      if (sourceRect == null || targetRect == null) continue;

      final start = sourceRect.bottomCenter;
      final end = targetRect.topCenter;
      final color = edge.broken ? AdminColors.danger : AdminColors.gold;
      final linePaint = Paint()
        ..color = color.withOpacity(edge.broken ? 0.85 : 0.55)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;

      if (edge.broken) {
        _drawDashedLine(canvas, start, end, linePaint);
      } else {
        canvas.drawLine(start, end, linePaint);
      }
      _drawArrowHead(canvas, start, end, Paint()..color = color);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    final total = (end - start).distance;
    if (total == 0) return;
    final direction = (end - start) / total;
    var covered = 0.0;
    while (covered < total) {
      final segStart = start + direction * covered;
      final segEnd = start + direction * math.min(covered + dashLength, total);
      canvas.drawLine(segStart, segEnd, paint);
      covered += dashLength + gapLength;
    }
  }

  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Paint paint) {
    final direction = end - start;
    final distance = direction.distance;
    if (distance == 0) return;
    final unit = direction / distance;
    const arrowSize = 7.0;
    final angle = math.atan2(unit.dy, unit.dx);
    final p1 =
        end - Offset(math.cos(angle - 0.5), math.sin(angle - 0.5)) * arrowSize;
    final p2 =
        end - Offset(math.cos(angle + 0.5), math.sin(angle + 0.5)) * arrowSize;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) {
    return oldDelegate.edges != edges || oldDelegate.nodeRects != nodeRects;
  }
}

/// 간선 편집 팝오버 — 선택지의 라벨/이동 대상을 [ChoiceEditForm]으로,
/// linear의 다음 노드는 [ChoiceTargetPicker]만으로 편집한다. 타이핑/선택할
/// 때마다 즉시 세션 캐시에 반영한다(onStaged) — 이 앱 전반의 관례와 같다,
/// "저장"은 Firestore에 쓰는 임시저장/승인요청 버튼의 몫이고 여기 "저장"은
/// 그냥 팝오버를 닫는 확인 버튼이다.
class _EdgePopover extends StatefulWidget {
  final AdminStoryNode sourceNode;

  /// null이면 linear 팩의 다음 노드 편집 — interactive면 choices 배열 안
  /// 인덱스(항상 값이 있다, 새로 만든 선택지도 팝오버를 열기 전에 먼저
  /// choices에 append해 둔다).
  final int? choiceIndex;

  final List<AdminStoryNodeSummary> candidates;
  final bool autofocusLabel;
  final VoidCallback onStaged;

  const _EdgePopover({
    required this.sourceNode,
    required this.choiceIndex,
    required this.candidates,
    required this.autofocusLabel,
    required this.onStaged,
  });

  @override
  State<_EdgePopover> createState() => _EdgePopoverState();
}

class _EdgePopoverState extends State<_EdgePopover> {
  @override
  Widget build(BuildContext context) {
    final choiceIndex = widget.choiceIndex;
    final isLinear = choiceIndex == null;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(
        isLinear ? '다음 노드' : '선택지 편집',
        style: TextStyle(color: AdminColors.ivory, fontSize: 15),
      ),
      content: SizedBox(
        width: 340,
        child: isLinear
            ? ChoiceTargetPicker(
                selectedId: widget.sourceNode.nextNodeId,
                candidates: widget.candidates
                    .where((c) => c.id != widget.sourceNode.id)
                    .toList(),
                onSelected: (id) {
                  setState(() => widget.sourceNode.nextNodeId = id);
                  widget.onStaged();
                },
              )
            : ChoiceEditForm(
                label: widget.sourceNode.choices[choiceIndex].label,
                nextNodeId:
                    widget.sourceNode.choices[choiceIndex].nextNodeId.isEmpty
                    ? null
                    : widget.sourceNode.choices[choiceIndex].nextNodeId,
                candidates: widget.candidates,
                autofocusLabel: widget.autofocusLabel,
                initiallyExpandTarget: !widget.autofocusLabel,
                onLabelChanged: (value) {
                  widget.sourceNode.choices[choiceIndex].label = value;
                  widget.onStaged();
                },
                onTargetChanged: (id) {
                  setState(
                    () =>
                        widget.sourceNode.choices[choiceIndex].nextNodeId = id,
                  );
                  widget.onStaged();
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (isLinear) {
              widget.sourceNode.nextNodeId = null;
            } else {
              widget.sourceNode.choices.removeAt(choiceIndex);
            }
            widget.onStaged();
            Navigator.pop(context);
          },
          child: const Text('삭제', style: TextStyle(color: AdminColors.danger)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AdminColors.gold,
            foregroundColor: Colors.white,
          ),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// "선택지 만들기" 인라인 팝업 카드 — mockup_choice_popover.html 그대로:
/// 제목 → 텍스트 입력 → 템플릿 칩 → "또는 기존 노드에 연결하기" → 기존 노드
/// 카드 목록([ChoiceTargetPicker] 재사용). 탭 흐름과 드래그-투-기존노드
/// 흐름이 이 카드 하나를 공유한다([_StoryMapViewState._openChoicePopover]
/// 참고) — [selectedTargetId]가 이미 정해져 있으면(드래그 흐름) 그 카드가
/// 목록에서 강조되고, 텍스트 입력은 자동 포커스된다.
class _ChoiceCreatePopoverCard extends StatefulWidget {
  final String title;

  /// linear 팩은 "선택지 문구"라는 개념이 없다(nextNodeId 하나뿐, 라벨
  /// 없음) — false면 텍스트 입력/템플릿 칩 블록 자체를 안 그린다.
  final bool showLabelSection;

  final List<AdminStoryNodeSummary> candidates;
  final String initialLabel;
  final bool autofocusLabel;
  final String? selectedTargetId;

  /// null이면 탭 흐름 — 아직 선택지가 없어서 스테이징할 대상이 없다(카드를
  /// 눌러야 비로소 생긴다). non-null이면 드래그 흐름 — 이미 스테이징된
  /// 선택지의 라벨을 타이핑할 때마다 실시간으로 반영한다.
  final ValueChanged<String>? onLabelLiveChanged;

  /// 기존 노드 카드를 탭했을 때 — (대상 id, 그 순간 텍스트 입력값)을 넘긴다.
  final void Function(String targetId, String labelText) onSelectTarget;

  const _ChoiceCreatePopoverCard({
    required this.title,
    required this.showLabelSection,
    required this.candidates,
    required this.initialLabel,
    required this.autofocusLabel,
    required this.selectedTargetId,
    required this.onLabelLiveChanged,
    required this.onSelectTarget,
  });

  @override
  State<_ChoiceCreatePopoverCard> createState() =>
      _ChoiceCreatePopoverCardState();
}

class _ChoiceCreatePopoverCardState extends State<_ChoiceCreatePopoverCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLabel,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminColors.ivory,
              ),
            ),
            if (widget.showLabelSection) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: widget.autofocusLabel,
                style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                decoration: adminInputDecoration(hintText: '선택지 문구를 입력하세요'),
                onChanged: widget.onLabelLiveChanged,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final chip in kChoiceTemplateChips)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        _controller.text = chip;
                        widget.onLabelLiveChanged?.call(chip);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AdminColors.panel2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AdminColors.border),
                        ),
                        child: Text(
                          chip,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AdminColors.muted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              widget.showLabelSection ? '또는 기존 노드에 연결하기' : '기존 노드에 연결하기',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
            const SizedBox(height: 8),
            ChoiceTargetPicker(
              selectedId: widget.selectedTargetId,
              candidates: widget.candidates,
              maxListHeight: 200,
              onSelected: (id) => widget.onSelectTarget(id, _controller.text),
            ),
          ],
        ),
      ),
    );
  }
}
