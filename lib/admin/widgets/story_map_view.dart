import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:graphview/graphview.dart';

import '../data/admin_story_repository.dart';
import '../data/admin_tts_voice_repository.dart';
import '../data/node_edit_session_cache.dart';
import '../data/node_id_suggestion.dart';
import '../models/admin_bgm.dart';
import '../models/admin_image.dart';
import '../models/admin_node_choice.dart';
import '../models/admin_sfx.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_tts_voice.dart';
import '../models/story_pack_type.dart';
import 'admin_theme.dart';
import 'choice_edit_form.dart';
import 'choice_target_picker.dart';
import 'labeled_field.dart';
import 'node_editor.dart';

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

  /// 노드 박스를 탭했을 때 — 부모(StoryTabView)가 이 노드를 [editingNode]로
  /// 선택한다("노드별로 쓰기" 모드로 옮기지 않는다 — 그래프 화면 안에서
  /// [_NodeEditorPanel]로 바로 연다).
  final ValueChanged<String> onOpenNode;

  /// "+"에서 빈 캔버스로 드래그해 새 노드를 만들었을 때 — (새 노드 id,
  /// 출발 노드 id, interactive면 출발 노드에 방금 생긴 선택지의 인덱스)를
  /// 넘긴다. 부모가 이 노드를 [editingNode]로 선택하고(그래프 화면에 그대로
  /// 머문다), 헤더에 "새 노드 ({sourceId}에서 연결됨)" 컨텍스트를 보여주고,
  /// 저장 시점에 그 선택지 문구가 비어 있으면 채우도록 안내한다
  /// (story_map_choice_popover_spec.md).
  final void Function(String newNodeId, String sourceId, int? choiceIndex)
  onNodeCreatedFromDrag;

  /// 세션 캐시가 바뀌었으니 다시 그려 달라는 신호 — 부모가 setState한다.
  final VoidCallback onChanged;

  /// 지금 그래프 화면 안에서 열려 있는 쓰기 카드가 편집 중인 노드 — null이면
  /// 패널이 안 열려 있다는 뜻이다. 노드별로 쓰기 탭의 NodeEditor와 완전히
  /// 같은 편집 세션([_StoryTabViewState]가 [_editingNode]/[_selectedNodeId]로
  /// 이미 관리하던 바로 그 상태)을 그대로 재사용한다 — 임시저장/승인요청/
  /// 삭제요청취소 로직을 여기서 새로 만들지 않기 위해서다.
  final AdminStoryNode? editingNode;
  final bool editingNodeDirty;
  final bool editingNodeIdEditable;
  final List<AdminImage> images;
  final List<AdminSfx> sfxLibrary;
  final List<AdminBgm> bgmLibrary;
  final List<AdminTtsVoice> ttsVoices;
  final VoidCallback onRefreshTtsVoices;
  final bool refreshingTtsVoices;
  final AdminTtsVoiceRepository ttsVoiceRepository;
  final String? defaultTtsVoiceId;
  final String? inheritedBackgroundImageId;
  final String? editingNodeCreationSourceId;

  /// NodeEditor의 onChanged와 같다 — 필드가 바뀔 때마다 세션 캐시에 반영해
  /// 달라는 신호.
  final VoidCallback onEditorChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onCancelDeleteRequest;

  /// 패널을 닫는다(명시적 닫기 버튼, 또는 빈 캔버스 탭) — 그래프 화면은
  /// 그대로 두고 [editingNode]만 null로 되돌아간다.
  final VoidCallback onClosePanel;

  /// 왼쪽 아래 "전체 저장" 툴바 — [unsavedNodeIds](= 세션 캐시에 있는 노드
  /// 중 실제로 라이브 버전과 다른(AdminStoryNode.hasUnsubmittedChanges)
  /// 노드, "수정됨" 배지와 같은 값)가 0보다 크면 뜬다. 실제 저장 로직은
  /// [_StoryTabViewState]가 개별 패널의 임시저장/승인요청과 똑같이 갖고
  /// 있다 — 여기서는 그 핸들러를 그대로 받아서 부른다.
  final VoidCallback onBulkSaveDraft;
  final VoidCallback onBulkRequestApproval;

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
    required this.editingNode,
    required this.editingNodeDirty,
    required this.editingNodeIdEditable,
    required this.images,
    required this.sfxLibrary,
    required this.bgmLibrary,
    required this.ttsVoices,
    required this.onRefreshTtsVoices,
    required this.refreshingTtsVoices,
    required this.ttsVoiceRepository,
    required this.defaultTtsVoiceId,
    required this.inheritedBackgroundImageId,
    required this.editingNodeCreationSourceId,
    required this.onEditorChanged,
    required this.onSaveDraft,
    required this.onCancelDeleteRequest,
    required this.onClosePanel,
    required this.onBulkSaveDraft,
    required this.onBulkRequestApproval,
  });

  @override
  State<StoryMapView> createState() => _StoryMapViewState();
}

class _StoryMapViewState extends State<StoryMapView> {
  // 200x72이던 예전 크기는 미리보기 2줄 + id 1줄 + 패딩을 넣으면 여백이
  // 거의 없어서(폰트 지표에 따라 자간이 조금만 더 벌어져도) "BOTTOM
  // OVERFLOWED" 렌더 에러가 났다(실제로 겪은 버그) — 92로 넉넉하게 올리고,
  // _NodeBox 쪽 텍스트도 Flexible로 한 번 더 방어한다(아래 참고).
  static const _nodeSize = Size(200, 92);
  static const _missingSize = Size(72, 40);

  /// 선택지 카드 크기 — 스토리 노드 카드(_nodeSize, 200x92)보다 가로/세로
  /// 모두 눈에 띄게 작게 잡아서 "이건 노드가 아니다"가 크기만으로도
  /// 드러나게 한다(140x84 → 112x68을 거쳐 다시 한 단계 더 줄였다).
  /// "선택지" 배지 한 줄 + 라벨 최대 2줄 + "+ 신규 노드" 버튼 한 줄이
  /// 들어갈 만큼(대상이 이미 있으면 버튼 자리가 비어 보이지만, 카드
  /// 크기를 선택지마다 다르게 주면 Sugiyama 레이아웃이 지저분해져서
  /// 통일했다).
  static const _choiceSize = Size(92, 56);

  /// 캔버스(InteractiveViewer 안쪽의 Stack을 감싼 SizedBox)의 RenderBox를
  /// 찾는 데 쓴다 — 팝오버를 노드 박스 옆에 앵커링하려면 그래프 로컬 좌표
  /// (layout의 Rect)를 화면 전역 좌표로 바꿔야 하는데, InteractiveViewer가
  /// 지금 어떤 pan/zoom 상태인지와 무관하게 정확한 값을 얻으려면 실제로 그
  /// 변환이 걸린 렌더 트리를 통해 localToGlobal을 태워야 한다.
  final GlobalKey _canvasKey = GlobalKey();

  /// 지금 떠 있는 앵커 팝업(있다면) — [_showAnchoredPopover]가 새 팝업을
  /// 열 때마다 먼저 이걸 지운다. 예전엔 "+"를 연달아 두 번 누르면(예:
  /// 첫 팝업이 검증 실패로 안 닫힌 채 남아있는 상태에서 다시 "+"를 누르는
  /// 경우) OverlayEntry가 두 개 겹쳐 쌓일 수 있었다 — 겉보기엔 새 팝업이
  /// 열린 것처럼 보여도 실제로는 예전 세션의 엔트리가 그 아래(또는 위)에
  /// 같이 살아있어서, 어느 쪽과 상호작용하고 있는지 화면만 봐서는 알 수
  /// 없었다(실제로 겪은 버그 — "선택 안 함" 오탐/이전 세션의 선택이
  /// 새 세션에 남아 보이는 증상). 이 필드로 "팝업은 항상 최대 하나"를
  /// 강제한다.
  OverlayEntry? _openPopoverEntry;

  /// [_showAnchoredPopover]가 열 때마다 하나씩 늘려서, 매번 새 팝업 위젯에
  /// 서로 다른 키를 준다 — 같은 노드에서 "+"를 다시 눌러도(소스 노드 id가
  /// 같아도) Flutter가 이전 세션의 State를 절대 재사용하지 않도록 구조적으로
  /// 강제하기 위해서다(아래 [_showAnchoredPopover] 참고).
  int _popoverSessionCounter = 0;

  /// InteractiveViewer의 확대/축소/이동 상태 — "전체 보기" 버튼이 이 값을
  /// 직접 갈아끼워서 리셋한다.
  final TransformationController _transformationController =
      TransformationController();

  /// 화면에 처음 들어왔을 때 한 번만 자동으로 전체 보기를 맞춘다 — 그
  /// 이후에는(타이핑 등으로 build가 다시 돌 때마다) 사용자가 손으로 옮긴
  /// 확대/이동 상태를 건드리지 않는다. "전체 보기" 버튼은 이 플래그와
  /// 무관하게 언제든 다시 누를 수 있다.
  bool _hasAutoFitted = false;

  /// InteractiveViewer의 maxScale — "전체 보기"가 계산한 배율도 이 값을
  /// 넘지 않게 clamp한다.
  static const _maxScale = 2.0;

  /// InteractiveViewer의 minScale 기본 하한 — 마우스 휠/핀치로 직접
  /// 축소할 때 이 배율까지는 항상 내려갈 수 있어야 한다. 그래프가 이
  /// 값으로도 화면에 다 안 들어올 만큼 아주 크면(드문 경우)
  /// [_computeDynamicMinScale]이 실제로 다 담기는 데 필요한 배율까지 한
  /// 번 더 낮춘다 — 그 반대(이 값보다 커지는) 방향으로는 절대 움직이지
  /// 않는다.
  static const _baseMinScale = 0.1;

  @override
  void dispose() {
    // "구조 보기"를 벗어나는 등으로 이 State 자체가 사라질 때 팝업이 열려
    // 있었다면 — Overlay는 이 위젯의 부모보다 수명이 길어서, 안 지우고
    // 두면 이미 죽은 콜백을 참조하는 엔트리가 화면에 유령처럼 남는다.
    _openPopoverEntry?.remove();
    _openPopoverEntry = null;
    _transformationController.dispose();
    super.dispose();
  }

  /// [rects] 전체(스토리 노드 + 선택지 카드 + "?" 박스)를 담는 최소
  /// 사각형 — "전체 보기"와 동적 minScale 계산이 공유한다. 노드 개수/위치가
  /// 바뀌어도 항상 그 시점의 layout.nodeRects에서 다시 계산하므로 하드코딩된
  /// 좌표/배율이 없다.
  Rect _boundingBoxOf(Iterable<Rect> rects) {
    final iterator = rects.iterator;
    if (!iterator.moveNext()) return Rect.zero;
    var left = iterator.current.left;
    var top = iterator.current.top;
    var right = iterator.current.right;
    var bottom = iterator.current.bottom;
    while (iterator.moveNext()) {
      final r = iterator.current;
      if (r.left < left) left = r.left;
      if (r.top < top) top = r.top;
      if (r.right > right) right = r.right;
      if (r.bottom > bottom) bottom = r.bottom;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// InteractiveViewer의 minScale — [_baseMinScale](0.1)이 기본 하한이고,
  /// 그래프가 뷰포트보다 훨씬 커서 0.1로도 전체가 안 들어올 때만 그보다
  /// 더 낮춘다. early-return으로 짜서 "0.1보다 커지는 경로"가 아예 없게
  /// 했다 — 이전엔 math.min(baseMinScale, fitScale * 0.9) 한 줄로 압축돼
  /// 있었는데, 같은 계산이라도 실제로 사용자가 휠/핀치로 축소할 때 0.1
  /// 밑으로 안 내려간다는 버그 리포트가 있어서, 계산 자체를 의심할 여지
  /// 없이 더 단순하게 다시 짰다.
  double _computeDynamicMinScale(Size viewportSize, Rect boundingBox) {
    if (viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        boundingBox.width <= 0 ||
        boundingBox.height <= 0) {
      return _baseMinScale;
    }
    final fitScale = math.min(
      viewportSize.width / boundingBox.width,
      viewportSize.height / boundingBox.height,
    );
    if (fitScale >= _baseMinScale) return _baseMinScale;
    return fitScale * 0.9;
  }

  /// "전체 보기" — 지금 그래프에 있는 모든 노드/선택지 카드의 bounding box를
  /// 계산해서, 뷰포트에 여백을 두고 딱 맞는 배율/위치로 [_transformationController]를
  /// 덮어쓴다. 좌표/배율을 하드코딩하지 않고 매번 [boundingBox]/[viewportSize]
  /// 기준으로 다시 계산하므로, 노드를 추가하거나 옮겨도 그대로 맞는다.
  void _resetToFitAll(Size viewportSize, Rect boundingBox, double minScale) {
    if (boundingBox.isEmpty ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return;
    }
    const padding = 48.0;
    final availableWidth = math.max(1.0, viewportSize.width - padding * 2);
    final availableHeight = math.max(1.0, viewportSize.height - padding * 2);
    final rawScale = math.min(
      availableWidth / boundingBox.width,
      availableHeight / boundingBox.height,
    );
    final scale = rawScale.clamp(minScale, _maxScale);

    final center = boundingBox.center;
    final matrix = Matrix4.identity()
      ..translate(
        viewportSize.width / 2 - center.dx * scale,
        viewportSize.height / 2 - center.dy * scale,
      )
      ..scale(scale);
    _transformationController.value = matrix;
  }

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

  /// 후보 목록에서 [targetId]에 해당하는 노드를 찾아 "노드 {id} · {라벨}"
  /// 형태의 안내 문구로 만든다 — 이미 연결된 대상이 있는 선택지를 편집할 때
  /// (연결된 대상을 다시 고를 수는 없고, 확인만 시켜준다 — 대상을 바꾸는 건
  /// 이제 선택지 카드 자신의 "+"([_handleChoicePlusTap]) 몫이다) 보여준다.
  String? _targetHintFor(String? targetId) {
    if (targetId == null || targetId.isEmpty) return null;
    for (final n in widget.nodes) {
      if (n.id == targetId) return '노드 ${n.id} · ${n.shortLabel}';
    }
    return '노드 $targetId (찾을 수 없음)';
  }

  /// "+" 탭(드래그 없음).
  /// - interactive: STEP 1 — 텍스트만 있는 최소 팝업을 연다. 대상 노드는
  ///   이 단계에 전혀 없다 — 저장하면 nextNodeId가 비어 있는 선택지가
  ///   그대로 만들어지고, 그래프에 자기 자신의 박스로 매달려 렌더링된다(그
  ///   상태 자체가 정상이다 — 나중에 그 박스의 "+"로 언제든 연결하면 된다,
  ///   STEP 2 = [_handleChoicePlusTap]).
  /// - linear: "선택지 문구" 개념 자체가 없다(nextNodeId 하나뿐) — 텍스트
  ///   단계 없이 곧바로 대상을 고르는 팝업을 연다.
  Future<void> _handlePlusTap(String sourceId) async {
    final anchorRect = _globalRectForNode(sourceId);
    if (anchorRect == null || !mounted) return;

    if (widget.packType != StoryPackType.interactive) {
      _showAnchoredPopover(
        anchorRect: anchorRect,
        builder: (close) => _ChoiceConnectPopoverCard(
          candidates: widget.nodes.where((c) => c.id != sourceId).toList(),
          onCreateNewNode: () {
            close();
            _connectToNewNode(sourceId);
          },
          onSelectExisting: (targetId) =>
              _handleLinearConnect(sourceId, targetId, close),
        ),
      );
      return;
    }

    _showAnchoredPopover(
      anchorRect: anchorRect,
      builder: (close) => _ChoiceLabelPopoverCard(
        initialLabel: '',
        autofocus: true,
        connectedToHint: null,
        onDelete: null,
        onSave: (label) => _handleCreateBlankChoice(sourceId, label, close),
      ),
    );
  }

  Future<void> _handleCreateBlankChoice(
    String sourceId,
    String label,
    VoidCallback close,
  ) async {
    final sourceNode = await _loadNode(sourceId);
    if (sourceNode == null || !mounted) return;
    sourceNode.choices.add(AdminNodeChoice(label: label));
    _restage(sourceNode);
    close();
  }

  Future<void> _handleLinearConnect(
    String sourceId,
    String targetId,
    VoidCallback close,
  ) async {
    final sourceNode = await _loadNode(sourceId);
    if (sourceNode == null || !mounted) return;
    sourceNode.nextNodeId = targetId;
    _restage(sourceNode);
    close();
  }

  /// "+"에서 기존 노드로 드래그.
  /// - interactive: 드래그 자체가 이미 "이 노드로 연결한다"는 명확한
  ///   의사표시라서, STEP 1/STEP 2를 굳이 나누지 않고 드롭 즉시 nextNodeId가
  ///   채워진 선택지를 만들어 스테이징한다. 뜨는 팝업은 대상을 다시 고르는
  ///   자리가 아니라(그건 이제 선택지 카드의 "+" 몫이다) 문구만 채우는
  ///   자리다 — 이미 연결된 대상은 안내 문구로만 보여준다.
  /// - linear: 팝업 없이 nextNodeId만 바로 바꾼다(편집할 "문구"가 아예
  ///   없으므로).
  Future<void> _connectToExisting(String sourceId, String targetId) async {
    if (sourceId == targetId) return;

    if (widget.packType != StoryPackType.interactive) {
      final sourceNode = await _loadNode(sourceId);
      if (sourceNode == null || !mounted) return;
      sourceNode.nextNodeId = targetId;
      _restage(sourceNode);
      return;
    }

    final anchorRect = _globalRectForNode(sourceId);
    if (anchorRect == null || !mounted) return;

    final sourceNode = await _loadNode(sourceId);
    if (sourceNode == null || !mounted) return;

    sourceNode.choices.add(AdminNodeChoice(nextNodeId: targetId));
    final choiceIndex = sourceNode.choices.length - 1;
    _restage(sourceNode);

    _showAnchoredPopover(
      anchorRect: anchorRect,
      builder: (close) => _ChoiceLabelPopoverCard(
        initialLabel: '',
        autofocus: true,
        connectedToHint: _targetHintFor(targetId),
        onDelete: () {
          sourceNode.choices.removeAt(choiceIndex);
          _restage(sourceNode);
          close();
        },
        onSave: (label) {
          sourceNode.choices[choiceIndex].label = label;
          _restage(sourceNode);
          close();
        },
      ),
    );
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

  /// 선택지 카드 탭(카드의 "+" 말고 본문/문구 부분) — 그 선택지의 문구만
  /// 고치는 작은 팝업을 연다(이름 바꾸기/삭제). 대상을 다시 고르는 자리가
  /// 아니다 — 이미 연결돼 있으면 안내 문구로만 보여주고, 대상을 바꾸거나
  /// 새로 잇는 건 이 카드 자신의 "+"([_handleChoicePlusTap]) 몫이다.
  Future<void> _handleChoiceCardTap(String sourceId, int choiceIndex) async {
    final anchorRect = _globalRectForNode(
      '__choice__${sourceId}__$choiceIndex',
    );
    if (anchorRect == null || !mounted) return;

    final sourceNode = await _loadNode(sourceId);
    if (sourceNode == null ||
        !mounted ||
        choiceIndex >= sourceNode.choices.length) {
      return;
    }

    _showAnchoredPopover(
      anchorRect: anchorRect,
      builder: (close) => _ChoiceLabelPopoverCard(
        initialLabel: sourceNode.choices[choiceIndex].label,
        autofocus: false,
        connectedToHint: _targetHintFor(
          sourceNode.choices[choiceIndex].nextNodeId,
        ),
        onDelete: () {
          sourceNode.choices.removeAt(choiceIndex);
          _restage(sourceNode);
          close();
        },
        onSave: (label) {
          sourceNode.choices[choiceIndex].label = label;
          _restage(sourceNode);
          close();
        },
      ),
    );
  }

  /// STEP 2 — 선택지 카드 자신의 "+" 탭. 아직 대상이 없든(가장 흔한 경우)
  /// 이미 있든 상관없이 항상 이 팝업으로 대상을 고르거나 바꾼다.
  Future<void> _handleChoicePlusTap(String sourceId, int choiceIndex) async {
    final anchorRect = _globalRectForNode(
      '__choice__${sourceId}__$choiceIndex',
    );
    if (anchorRect == null || !mounted) return;

    _showAnchoredPopover(
      anchorRect: anchorRect,
      builder: (close) => _ChoiceConnectPopoverCard(
        candidates: widget.nodes.where((c) => c.id != sourceId).toList(),
        onCreateNewNode: () {
          close();
          _createNewNodeForChoice(sourceId, choiceIndex);
        },
        onSelectExisting: (targetId) => _handleConnectChoiceToExisting(
          sourceId,
          choiceIndex,
          targetId,
          close,
        ),
      ),
    );
  }

  Future<void> _handleConnectChoiceToExisting(
    String sourceId,
    int choiceIndex,
    String targetId,
    VoidCallback close,
  ) async {
    final sourceNode = await _loadNode(sourceId);
    if (sourceNode == null ||
        !mounted ||
        choiceIndex >= sourceNode.choices.length) {
      return;
    }
    sourceNode.choices[choiceIndex].nextNodeId = targetId;
    _restage(sourceNode);
    close();
  }

  /// 선택지 카드의 "+ 새 노드 만들기"(STEP 2의 한 갈래) — 아직 대상이
  /// 없든 이미 있든, 이 선택지를 새로 만든 빈 노드로 (다시) 연결한다.
  /// _connectToNewNode(캔버스에 "+"를 드래그해 놓는 흐름)와 거의 같은
  /// 로직이지만, 새 선택지를 만드는 게 아니라 이미 있는
  /// 선택지(choiceIndex)의 nextNodeId만 채운다는 점이 다르다.
  /// onNodeCreatedFromDrag 콜백을 그대로 재사용한다 — 부모가 이미 (새 노드
  /// id, 출발 노드 id, 선택지 인덱스)를 받아서 그래프 화면 안 패널을 그
  /// 새 노드로 열고, 저장 시점에 라벨이 비어 있으면 채우도록 안내하는
  /// 로직을 갖고 있다.
  Future<void> _createNewNodeForChoice(String sourceId, int choiceIndex) async {
    final takenIds = widget.nodes.map((n) => n.id).toSet();
    final newId = suggestSequentialNodeIds(takenIds, 1).first;
    final maxOrder = widget.nodes.isEmpty
        ? -1
        : widget.nodes.map((n) => n.order).reduce((a, b) => a > b ? a : b);
    final newNode = AdminStoryNode(id: newId, order: maxOrder + 1);
    widget.sessionCache.put(widget.packId, newNode);

    final sourceNode = await _loadNode(sourceId);
    if (sourceNode != null && choiceIndex < sourceNode.choices.length) {
      sourceNode.choices[choiceIndex].nextNodeId = newId;
      widget.sessionCache.put(widget.packId, sourceNode);
    }
    if (!mounted) return;
    widget.onChanged();
    widget.onNodeCreatedFromDrag(newId, sourceId, choiceIndex);
  }

  /// 화면 전역 좌표 [anchorRect] 옆에 붙는 오버레이 팝업 — 바깥을 탭하면
  /// 아무 것도 만들지 않고 닫힌다(story_map_choice_popover_spec.md의 "팝업
  /// 바깥 클릭 → 취소" 규칙).
  ///
  /// 매번 (1) 먼저 이전에 떠 있던 팝업을 지우고(항상 최대 하나만 존재하게)
  /// (2) 이번 세션 전용 키를 [builder]가 만드는 위젯에 붙인다(같은 소스
  /// 노드로 다시 열어도 매번 완전히 새로운 State로 시작하도록) —
  /// [_openPopoverEntry]/[_popoverSessionCounter] doc 참고.
  void _showAnchoredPopover({
    required Rect anchorRect,
    required Widget Function(VoidCallback close) builder,
  }) {
    _openPopoverEntry?.remove();
    _openPopoverEntry = null;

    final overlayState = Overlay.of(context);
    final sessionKey = ValueKey(_popoverSessionCounter++);
    late OverlayEntry entry;
    void close() {
      if (entry.mounted) entry.remove();
      if (identical(_openPopoverEntry, entry)) _openPopoverEntry = null;
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
              key: sessionKey,
              left: left,
              top: top,
              width: popoverWidth,
              child: builder(close),
            ),
          ],
        );
      },
    );

    _openPopoverEntry = entry;
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
    // 이 칩은 이제 linear 팩의 노드→노드 직결 간선에만 쓰인다(interactive의
    // 노드→선택지 카드/선택지 카드→대상 간선은 isStructural이라 호출부에서
    // 아예 걸러진다) — linear는 애초에 "선택지 문구" 개념이 없어서 화살표
    // 아이콘 아니면 끊어짐 표시뿐이다.
    final text = edge.broken ? '?' : '→';

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
    final editingNode = widget.editingNode;
    final boundingBox = _boundingBoxOf(layout.nodeRects.values);

    return ColoredBox(
      color: AdminColors.bg,
      // LayoutBuilder로 실제 뷰포트 크기를 받아야 "전체 보기"/동적 minScale
      // 계산이 하드코딩 없이 지금 창 크기에 맞게 나온다.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = constraints.biggest;
          // build()마다 다시 계산하다 보니 레이아웃이 미세하게 흔들리면
          // (부동소수점 오차 수준) minScale 값도 매번 살짝 다르게 나올 수
          // 있다 — 0.01 단위로 내림해서 고정한다. 내림이라 실제로 필요한
          // 값보다 더 작아지는 방향으로만 어긋나므로("덜 줄어드는" 쪽으로는
          // 절대 안 어긋난다), 안전하면서도 InteractiveViewer가 매 프레임
          // 미세하게 다른 minScale을 받는 상황 자체를 없앤다.
          final dynamicMinScale =
              (_computeDynamicMinScale(viewportSize, boundingBox) * 100)
                  .floorToDouble() /
              100;

          // 이 화면에 처음 들어왔을 때 딱 한 번, 다음 프레임에 전체 보기로
          // 맞춘다(레이아웃이 실제로 자리잡은 뒤에 계산해야 정확하다) —
          // build() 도중에 곧바로 컨트롤러를 바꾸면 "빌드 중 setState"류
          // 에러가 난다.
          if (!_hasAutoFitted &&
              viewportSize.width > 0 &&
              viewportSize.height > 0) {
            _hasAutoFitted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _resetToFitAll(viewportSize, boundingBox, dynamicMinScale);
            });
          }

          return Stack(
            children: [
              // 패널은 이 바깥 Stack의 형제로 둔다 — InteractiveViewer
              // 안쪽에 두면 패널도 그래프와 같이 확대/축소·이동되어
              // 버린다. 패널은 화면 오른쪽에 고정돼야 한다.
              InteractiveViewer(
                transformationController: _transformationController,
                constrained: false,
                // 유한한 240 여백은 가로/세로에 똑같이 적용되는 값이라
                // 축별로 비대칭일 수는 없지만(EdgeInsets.all은 항상
                // 대칭), 요청대로 아예 무한대로 풀어서 팬 이동 범위 자체가
                // 어떤 축으로도 제한되지 않게 한다.
                boundaryMargin: const EdgeInsets.all(double.infinity),
                // 기본값이라 원래도 true였지만, "정말 꺼져 있는 게
                // 아닌지" 소스에서 바로 보이도록 명시적으로 적어 둔다.
                panEnabled: true,
                scaleEnabled: true,
                // 예전 0.25는 노드가 몇 개만 넘어가도 전체를 한 화면에
                // 담을 수 없을 만큼 큰 하한이었다(실제로 겪은 문제) —
                // 기본 0.1로 낮추고, 그래도 모자라면(그래프가 아주 크면)
                // _computeDynamicMinScale이 한 번 더 낮춘다.
                minScale: dynamicMinScale,
                maxScale: _maxScale,
                child: SizedBox(
                  key: _canvasKey,
                  width: layout.canvasSize.width,
                  height: layout.canvasSize.height,
                  child: Stack(
                    children: [
                      // 빈 캔버스에 드롭했을 때(=새 노드 만들기)를 받는 배경 —
                      // Stack에서 제일 먼저(맨 아래) 그려야, 노드 박스 위에
                      // 드롭하면 그 노드의 DragTarget이 먼저 히트테스트되어
                      // 우선한다. 패널이 열려 있을 때 빈 캔버스를 "탭"(드래그가
                      // 아니라)하면 패널을 닫는다 — onTap은 움직임 없이 뗄 때만
                      // 반응해서, "+"를 이 배경 위로 드래그하는 동작과는 서로
                      // 간섭하지 않는다.
                      Positioned.fill(
                        child: DragTarget<String>(
                          onAcceptWithDetails: (details) =>
                              _connectToNewNode(details.data),
                          builder: (context, candidateData, rejectedData) =>
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: editingNode == null
                                    ? null
                                    : widget.onClosePanel,
                                child: const SizedBox.expand(),
                              ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _EdgePainter(layout.edges, layout.nodeRects),
                        ),
                      ),
                      // 간선 라벨 칩을 노드 박스보다 먼저(= 아래 z-order에)
                      // 넣는다 — Stack은 나중에 넣은 자식일수록 위에서 먼저
                      // 히트테스트되므로, 순서가 반대였을 때는 라벨 칩의 사각
                      // 히트 영역이 노드 박스(와 그 위의 "+" 핸들) 위에 겹쳐
                      // 탭을 가로챌 수 있었다 — 특히 선택지가 여러 개라 간선이
                      // 부모 오른쪽 아래로 뻗을 때(story_map_choice_popover_spec.md
                      // 후속 버그 리포트의 "선택지가 있는 노드에서 +를 누르면
                      // 그중 하나의 편집 모드로 열린다" 증상). interactive의
                      // 노드→선택지/선택지→대상 간선(isStructural)은 여기서
                      // 걸러진다 — 선택지 카드 자신이 라벨을 보여준다.
                      for (final edge in layout.edges)
                        if (!edge.isStructural)
                          _buildEdgeLabel(edge, layout.nodeRects),
                      for (final id in layout.nodeRects.keys)
                        if (id.startsWith('__missing__'))
                          _MissingBox(
                            key: ValueKey('missing_$id'),
                            rect: layout.nodeRects[id]!,
                          )
                        else if (!id.startsWith('__choice__'))
                          _NodeBox(
                            key: ValueKey('node_$id'),
                            summary: nodeById[id]!,
                            rect: layout.nodeRects[id]!,
                            unsaved: widget.unsavedNodeIds.contains(id),
                            isEditingOpen: editingNode?.id == id,
                            onTap: () => widget.onOpenNode(id),
                            onConnectRequested: (sourceId) =>
                                _connectToExisting(sourceId, id),
                          ),
                      // 선택지 카드 — 부모 노드 아래, 대상 노드/"?" 박스
                      // 위에 낀 중간 계층. 문구만 보여준다 — 대상 연결은
                      // 이 카드 자신의 "+" 핸들(_ChoicePlusHandle) 몫이라
                      // 카드 안에는 없다.
                      for (final info in layout.choiceCards)
                        _ChoiceCard(
                          key: ValueKey('choice_${info.key}'),
                          choice: info.choice,
                          rect: layout.nodeRects[info.key]!,
                          onTapEdit: () => _handleChoiceCardTap(
                            info.sourceId,
                            info.choiceIndex,
                          ),
                        ),
                      // "+" 핸들은 각자의 박스(노드/선택지 카드) 자신의
                      // Stack에 중첩시키는 대신, 바깥 Stack의 맨 마지막(=항상
                      // 최상단 z-order) 자식으로 따로 뺐다 — 중첩된
                      // GestureDetector의 제스처 아레나 우선순위에 기대는
                      // 대신, 몇 개든 "+"가 항상 다른 무엇보다도 위에서
                      // 탭을 가로채도록 구조적으로 보장하기 위해서다(실제로
                      // 겪은 버그 — 위 주석 참고). 스토리 노드는 STEP 1(문구
                      // 만 있는 선택지 만들기)을 여는 [_PlusHandle], 선택지
                      // 카드는 STEP 2(대상 연결/변경)를 여는
                      // [_ChoicePlusHandle]로 서로 다르다.
                      for (final id in layout.nodeRects.keys)
                        if (!id.startsWith('__missing__') &&
                            !id.startsWith('__choice__'))
                          _PlusHandle(
                            key: ValueKey('plus_$id'),
                            nodeId: id,
                            rect: layout.nodeRects[id]!,
                            onTap: () => _handlePlusTap(id),
                          ),
                      for (final info in layout.choiceCards)
                        _ChoicePlusHandle(
                          key: ValueKey('choiceplus_${info.key}'),
                          rect: layout.nodeRects[info.key]!,
                          onTap: () => _handleChoicePlusTap(
                            info.sourceId,
                            info.choiceIndex,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (editingNode != null)
                _NodeEditorPanel(
                  key: ObjectKey(editingNode),
                  node: editingNode,
                  dirty: widget.editingNodeDirty,
                  isIdEditable: widget.editingNodeIdEditable,
                  images: widget.images,
                  sfxLibrary: widget.sfxLibrary,
                  bgmLibrary: widget.bgmLibrary,
                  ttsVoices: widget.ttsVoices,
                  onRefreshTtsVoices: widget.onRefreshTtsVoices,
                  refreshingTtsVoices: widget.refreshingTtsVoices,
                  ttsVoiceRepository: widget.ttsVoiceRepository,
                  packId: widget.packId,
                  defaultTtsVoiceId: widget.defaultTtsVoiceId,
                  packType: widget.packType,
                  candidates: widget.nodes,
                  inheritedBackgroundImageId: widget.inheritedBackgroundImageId,
                  creationSourceId: widget.editingNodeCreationSourceId,
                  onChanged: widget.onEditorChanged,
                  onSaveDraft: widget.onSaveDraft,
                  onCancelDeleteRequest: widget.onCancelDeleteRequest,
                  onClose: widget.onClosePanel,
                ),
              // 패널이 열려 있으면 그 폭만큼 오른쪽에서 더 띄워서 겹치지
              // 않게 한다.
              Positioned(
                right: editingNode != null
                    ? _NodeEditorPanel._panelWidth + 16
                    : 16,
                bottom: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 지금 실제로 적용된 배율/이 화면의 minScale을 그대로
                    // 보여준다 — "정말 0.1까지 줄어드는지"를 브라우저에서
                    // 직접 눈으로 확인할 수 있게 하려는 디버그용 표시다.
                    // _transformationController를 직접 구독해서 휠/핀치로
                    // 배율이 바뀔 때마다 이 텍스트만 다시 그려진다.
                    _ScaleReadout(
                      controller: _transformationController,
                      minScale: dynamicMinScale,
                    ),
                    const SizedBox(width: 8),
                    _FitToScreenButton(
                      onPressed: () => _resetToFitAll(
                        viewportSize,
                        boundingBox,
                        dynamicMinScale,
                      ),
                    ),
                  ],
                ),
              ),
              // 오른쪽 아래 전체 보기/배율 컨트롤을 그대로 좌우만 뒤집은
              // 자리 — "수정됨" 배지와 같은 소스(widget.unsavedNodeIds, 곧
              // AdminStoryNode.hasUnsubmittedChanges로 걸러진 세션 캐시
              // 항목)를 그대로 읽으므로 개별 저장이든 이 툴바의 일괄
              // 저장이든 항상 실시간으로 맞는 개수를 보여준다.
              Positioned(
                left: 16,
                bottom: 16,
                child: _SaveAllToolbar(
                  unsavedCount: widget.unsavedNodeIds.length,
                  onSaveDraftAll: widget.onBulkSaveDraft,
                  onRequestApprovalAll: widget.onBulkRequestApproval,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// interactive 팩은 이제 "노드 → 선택지 카드 → 대상 노드" 3단 구조로
  /// 레이아웃한다 — 선택지 하나마다 별도 Sugiyama 노드(`__choice__{sourceId}__
  /// {index}`)를 만들어서, 선택지 문구와 "+ 신규 노드 작성" 버튼이 실제
  /// 카드로 다이어그램 위에 보이게 한다(예전엔 선(라인) 중점의 작은 칩
  /// 하나뿐이라 여러 선택지가 있어도 잘 눈에 안 띄었다). linear 팩은
  /// "선택지"라는 개념 자체가 없으므로(nextNodeId 하나뿐) 노드→노드 직결
  /// 간선을 그대로 유지한다.
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
    final choiceCards = <_ChoiceCardInfo>[];
    final missingIds = <String>{};

    void addMissingEdge(String sourceKey, String targetId, int? choiceIndex) {
      final exists = nodeObjs.containsKey(targetId);
      final targetKey = exists ? targetId : '__missing__$targetId';
      if (!exists) missingIds.add(targetId);
      edgeInfos.add(
        _LayoutEdge(
          sourceId: sourceKey,
          targetKey: targetKey,
          broken: !exists,
          isStructural: true,
          choiceIndex: choiceIndex,
        ),
      );
    }

    if (packType == StoryPackType.interactive) {
      for (final n in nodes) {
        for (var i = 0; i < n.choices.length; i++) {
          final choice = n.choices[i];
          final choiceKey = '__choice__${n.id}__$i';

          final choiceNode = Node.Id(choiceKey);
          choiceNode.size = _choiceSize;
          graph.addNode(choiceNode);
          nodeObjs[choiceKey] = choiceNode;
          choiceCards.add(
            _ChoiceCardInfo(sourceId: n.id, choiceIndex: i, choice: choice),
          );

          // 부모 노드 → 이 선택지 카드. 선택지 자체는 "존재하는" 것이라
          // 끊어질 일이 없다 — broken은 항상 false.
          edgeInfos.add(
            _LayoutEdge(
              sourceId: n.id,
              targetKey: choiceKey,
              broken: false,
              isStructural: true,
              choiceIndex: i,
            ),
          );

          final targetId = choice.nextNodeId;
          if (targetId.isNotEmpty) {
            addMissingEdge(choiceKey, targetId, i);
          }
        }
      }
    } else {
      for (final n in nodes) {
        final targetId = n.nextNodeId;
        if (targetId == null || targetId.isEmpty) continue;
        final exists = nodeObjs.containsKey(targetId);
        final targetKey = exists ? targetId : '__missing__$targetId';
        if (!exists) missingIds.add(targetId);
        edgeInfos.add(
          _LayoutEdge(
            sourceId: n.id,
            targetKey: targetKey,
            broken: !exists,
            isStructural: false,
            choiceIndex: null,
          ),
        );
      }
    }

    for (final missingId in missingIds) {
      final key = '__missing__$missingId';
      if (nodeObjs.containsKey(key)) continue;
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
      choiceCards: choiceCards,
      canvasSize: Size(size.width + 80, size.height + 80),
    );
  }
}

/// 선택지 카드 하나가 어떤 노드의 몇 번째 선택지인지 — [_ChoiceCard] 렌더링과
/// 탭/버튼 콜백에 필요한 정보. Sugiyama 그래프 상의 위치는
/// `layout.nodeRects['__choice__${sourceId}__$choiceIndex']`로 따로 찾는다.
class _ChoiceCardInfo {
  final String sourceId;
  final int choiceIndex;
  final AdminNodeChoice choice;

  _ChoiceCardInfo({
    required this.sourceId,
    required this.choiceIndex,
    required this.choice,
  });

  String get key => '__choice__${sourceId}__$choiceIndex';
}

class _LayoutEdge {
  final String sourceId;
  final String targetKey;
  final bool broken;

  /// true면 "노드 → 선택지 카드" 또는 "선택지 카드 → 대상 노드" 간선이다
  /// — 라벨은 선택지 카드 자체가 보여주므로 [_StoryMapViewState._buildEdgeLabel]가
  /// 이 간선에는 따로 칩을 그리지 않는다. false는 linear 팩의 노드→노드
  /// 직결 간선(여전히 칩으로 편집한다).
  final bool isStructural;

  /// interactive 팩에서만 값이 있다 — choices 배열 안 인덱스. linear면 null
  /// (nextNodeId는 인덱스 개념이 없다).
  final int? choiceIndex;

  _LayoutEdge({
    required this.sourceId,
    required this.targetKey,
    required this.broken,
    required this.isStructural,
    required this.choiceIndex,
  });
}

class _LayoutResult {
  final Map<String, Rect> nodeRects;
  final List<_LayoutEdge> edges;
  final List<_ChoiceCardInfo> choiceCards;
  final Size canvasSize;

  _LayoutResult({
    required this.nodeRects,
    required this.edges,
    required this.choiceCards,
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

  /// 지금 이 노드가 [_NodeEditorPanel]에 열려 있는지 — 사이드바의 active
  /// 상태와 같은 골드 테두리로 강조한다.
  final bool isEditingOpen;

  final VoidCallback onTap;
  final ValueChanged<String> onConnectRequested;

  const _NodeBox({
    required super.key,
    required this.summary,
    required this.rect,
    required this.unsaved,
    required this.isEditingOpen,
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
          final highlighted = candidateData.isNotEmpty || isEditingOpen;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: highlighted ? AdminColors.gold : AdminColors.border,
                  width: highlighted ? 2 : 1,
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 두 Text 모두 Flexible로 감싼다 — maxLines/ellipsis는
                  // 가로 방향(한 줄 안에서) 잘라내는 것뿐이라, 실제 렌더
                  // 높이가 이 박스의 고정 높이를 넘으면(폰트 지표가 조금만
                  // 달라도 넘길 수 있다) Column이 "BOTTOM OVERFLOWED BY
                  // X PIXELS" 렌더 에러를 던졌다(실제로 겪은 버그) —
                  // Flexible로 감싸면 Column이 남은 공간만큼만 나눠 줘서
                  // 하드 오버플로 대신(최악의 경우에도) 자연스러운 클립으로
                  // 대체된다.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          summary.preview.isEmpty ? '(내용 없음)' : summary.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.ivory,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          summary.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AdminColors.muted,
                          ),
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

/// 선택지 카드 — 부모 노드와 대상 노드 사이의 중간 계층으로 그려진다
/// (_computeLayout이 선택지마다 Sugiyama 가상 노드를 하나씩 만들기 때문에
/// 부모 바로 아래 한 층에 자연스럽게 배치된다). 스토리 노드 카드
/// (_NodeBox)보다 눈에 띄게 작게 그려서 "이건 노드가 아니라 선택지다"를
/// 크기만으로도 구분할 수 있게 하고, 상단 "선택지" 배지 + 보라색 테두리로
/// (이미지 라이브러리의 "선택지" 카테고리 배지와 같은 색 — AdminColors의
/// imageCategoryChoiceBg/Text) 한 번 더 구분한다.
///
/// 카드 본문(배지+문구)을 탭하면 문구만 고치는 팝업이 열린다(rename/삭제,
/// [_StoryMapViewState._handleChoiceCardTap]) — 대상을 정하거나 바꾸는 건
/// 이 카드가 아니라 자신의 "+" 핸들([_ChoicePlusHandle]) 몫이다. 대상이
/// 아직 없는 채로 매달려 있는 것도(dangling) 정상 상태다 — 에러가 아니다.
class _ChoiceCard extends StatelessWidget {
  final AdminNodeChoice choice;
  final Rect rect;
  final VoidCallback onTapEdit;

  const _ChoiceCard({
    required super.key,
    required this.choice,
    required this.rect,
    required this.onTapEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTapEdit,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AdminColors.panel2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AdminColors.imageCategoryChoiceText,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "선택지" 배지 — 스토리 노드 카드에는 없는 표식이라 한눈에
                // 카드 종류를 구분하게 해준다.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 0.5,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.imageCategoryChoiceBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.call_split_rounded,
                        size: 6,
                        color: AdminColors.imageCategoryChoiceText,
                      ),
                      const SizedBox(width: 1),
                      Text(
                        '선택지',
                        style: TextStyle(
                          fontSize: 6,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.imageCategoryChoiceText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 1.5),
                Flexible(
                  child: Text(
                    choice.label.isEmpty ? '(문구 없음)' : choice.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.ivory,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 선택지 카드 자신의 "+" 핸들 — STEP 2(대상 연결/변경)를 연다. 스토리
/// 노드의 [_PlusHandle]과 같은 자리(오른쪽 아래 모서리)에, 선택지 카드의
/// 작은 크기에 맞춰 더 작게, 골드 대신 선택지 색(보라)으로 그린다. 대상이
/// 있든 없든 항상 떠 있다 — 탭 하나만 지원한다(드래그로 잇는 건 스토리
/// 노드의 "+"만 지원, 선택지 카드는 필요하다고 판단하지 않아 뺐다).
class _ChoicePlusHandle extends StatelessWidget {
  final Rect rect;
  final VoidCallback onTap;

  const _ChoicePlusHandle({
    required super.key,
    required this.rect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const handleSize = 15.0;
    return Positioned(
      left: rect.right - handleSize / 2,
      top: rect.bottom - handleSize / 2,
      width: handleSize,
      height: handleSize,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: handleSize,
          height: handleSize,
          decoration: BoxDecoration(
            color: AdminColors.imageCategoryChoiceText,
            shape: BoxShape.circle,
            border: Border.all(color: AdminColors.panel, width: 1.5),
          ),
          child: const Icon(Icons.add_rounded, size: 10, color: Colors.white),
        ),
      ),
    );
  }
}

/// 지금 배율과 이 화면의 minScale을 실시간으로 보여주는 작은 표시 —
/// [controller](=[_StoryMapViewState._transformationController])를 직접
/// 구독해서, 휠/핀치로 배율이 바뀔 때마다 다시 그려진다. minScale이 실제로
/// 코드에 어떤 값으로 설정돼 있고 그 값까지 축소가 실제로 되는지를 브라우저
/// 화면에서 직접, 별도 디버그 도구 없이 확인할 수 있게 하려고 넣었다.
class _ScaleReadout extends StatelessWidget {
  final TransformationController controller;
  final double minScale;

  const _ScaleReadout({required this.controller, required this.minScale});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final currentScale = controller.value.getMaxScaleOnAxis();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AdminColors.panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AdminColors.border),
          ),
          child: Text(
            '배율 ${currentScale.toStringAsFixed(2)}x '
            '(최소 ${minScale.toStringAsFixed(2)}x)',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        );
      },
    );
  }
}

/// "전체 보기" 리셋 버튼 — InteractiveViewer 바깥(캔버스와 같이 확대/이동
/// 되지 않는 고정 위치)에 떠 있는다. 실제 fit-to-screen 계산은
/// [_StoryMapViewState._resetToFitAll]이 한다 — 이 위젯은 순수하게
/// 버튼 모양/탭 전달만 맡는다.
class _FitToScreenButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _FitToScreenButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminColors.panel,
      elevation: 4,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AdminColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fit_screen_rounded,
                size: 16,
                color: AdminColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                '전체 보기',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 왼쪽 아래 "전체 저장" 툴바 — 오른쪽 아래 전체 보기/배율 컨트롤과 같은
/// 자리(InteractiveViewer 바깥, 화면에 고정)를 좌우만 뒤집었다.
/// [unsavedCount]는 [_StoryMapViewState]가 [StoryMapView.unsavedNodeIds]를
/// 그대로 세어 넘긴다 — "수정됨" 배지와 정확히 같은 소스
/// (AdminStoryNode.hasUnsubmittedChanges로 걸러진 세션 캐시 항목)라서,
/// 개별 노드를 저장하든 이 툴바로 한꺼번에 저장하든 항상 실시간으로 맞는
/// 개수를 보여준다. 0개면 버튼 없이 "저장할 변경사항 없음"만 보여준다 —
/// 빈 활성 바처럼 보이지 않게.
class _SaveAllToolbar extends StatelessWidget {
  final int unsavedCount;
  final VoidCallback onSaveDraftAll;
  final VoidCallback onRequestApprovalAll;

  const _SaveAllToolbar({
    required this.unsavedCount,
    required this.onSaveDraftAll,
    required this.onRequestApprovalAll,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnsaved = unsavedCount > 0;
    return Material(
      color: AdminColors.panel,
      elevation: 4,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AdminColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasUnsaved
                  ? Icons.edit_note_rounded
                  : Icons.check_circle_outline_rounded,
              size: 16,
              color: hasUnsaved ? AdminColors.gold : AdminColors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              hasUnsaved ? '수정된 노드 $unsavedCount개' : '저장할 변경사항 없음',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: hasUnsaved ? FontWeight.w700 : FontWeight.w500,
                color: hasUnsaved ? AdminColors.ivory : AdminColors.muted,
              ),
            ),
            if (hasUnsaved) ...[
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: onSaveDraftAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.muted,
                  side: BorderSide(color: AdminColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('전체 임시저장', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: onRequestApprovalAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.gold,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  '전체 승인 요청 보내기',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 그래프 화면 안에서 그대로 노드를 쓰는 패널 — 화면 오른쪽에 고정폭으로
/// 붙는다. 안쪽은 "노드별로 쓰기" 탭이 쓰는 것과 완전히 같은 [NodeEditor]다
/// — 이 패널 자체는 그 위에 닫기 버튼만 얹은 얇은 껍데기일 뿐, 본문/배경/
/// 연출 효과/선택지 편집 로직은 전혀 새로 만들지 않았다. 저장/승인요청/
/// 삭제요청취소도 부모([_StoryTabViewState])가 이미 갖고 있던 핸들러를
/// 그대로 받아 쓴다.
///
/// [key]를 [ObjectKey]로 잡는 이유는 "노드별로 쓰기"의 NodeEditor와 같다 —
/// "새 노드 만들기"로 체인을 타고 내려가며 편집 대상 노드가 바뀔 때마다
/// (매번 다른 AdminStoryNode 인스턴스) NodeBodyBlocksEditor의 TextFormField가
/// 이전 노드의 내용을 그대로 들고 있지 않고 확실히 다시 마운트되게 한다.
class _NodeEditorPanel extends StatelessWidget {
  final AdminStoryNode node;
  final bool dirty;
  final bool isIdEditable;
  final List<AdminImage> images;
  final List<AdminSfx> sfxLibrary;
  final List<AdminBgm> bgmLibrary;
  final List<AdminTtsVoice> ttsVoices;
  final VoidCallback onRefreshTtsVoices;
  final bool refreshingTtsVoices;
  final AdminTtsVoiceRepository ttsVoiceRepository;
  final String packId;
  final String? defaultTtsVoiceId;
  final StoryPackType packType;
  final List<AdminStoryNodeSummary> candidates;
  final String? inheritedBackgroundImageId;
  final String? creationSourceId;
  final VoidCallback onChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onCancelDeleteRequest;
  final VoidCallback onClose;

  const _NodeEditorPanel({
    required super.key,
    required this.node,
    required this.dirty,
    required this.isIdEditable,
    required this.images,
    required this.sfxLibrary,
    required this.bgmLibrary,
    required this.ttsVoices,
    required this.onRefreshTtsVoices,
    required this.refreshingTtsVoices,
    required this.ttsVoiceRepository,
    required this.packId,
    required this.defaultTtsVoiceId,
    required this.packType,
    required this.candidates,
    required this.inheritedBackgroundImageId,
    required this.creationSourceId,
    required this.onChanged,
    required this.onSaveDraft,
    required this.onCancelDeleteRequest,
    required this.onClose,
  });

  static const _panelWidth = 440.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: _panelWidth,
      child: Material(
        color: AdminColors.panel,
        elevation: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AdminColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '노드 편집',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.muted,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AdminColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: NodeEditor(
                key: ObjectKey(node),
                node: node,
                dirty: dirty,
                isIdEditable: isIdEditable,
                images: images,
                sfxLibrary: sfxLibrary,
                bgmLibrary: bgmLibrary,
                ttsVoices: ttsVoices,
                onRefreshTtsVoices: onRefreshTtsVoices,
                refreshingTtsVoices: refreshingTtsVoices,
                ttsVoiceRepository: ttsVoiceRepository,
                packId: packId,
                defaultTtsVoiceId: defaultTtsVoiceId,
                packType: packType,
                candidates: candidates,
                inheritedBackgroundImageId: inheritedBackgroundImageId,
                creationSourceId: creationSourceId,
                onChanged: onChanged,
                onSaveDraft: onSaveDraft,
                onCancelDeleteRequest: onCancelDeleteRequest,
              ),
            ),
          ],
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

/// STEP 1(선택지 만들기)과 "선택지 카드 본문 탭"(이름 바꾸기/삭제)이
/// 함께 쓰는 최소 팝업 — 문구 입력 + 템플릿 칩 + 저장뿐이다. 대상 노드는
/// 이 카드에 전혀 없다: 대상을 고르거나 바꾸는 건 이제 전적으로
/// [_ChoiceConnectPopoverCard](선택지 카드 자신의 "+")의 몫이다.
/// [connectedToHint]가 있으면(이미 대상이 연결된 선택지를 다시 열었을
/// 때) 그 사실만 읽기 전용 안내 줄로 보여준다 — 여기서 다시 고를 수는
/// 없다.
class _ChoiceLabelPopoverCard extends StatefulWidget {
  final String initialLabel;
  final bool autofocus;
  final String? connectedToHint;

  /// null이면 아직 존재하지 않는 선택지를 새로 만드는 중이라 지울 게
  /// 없다(STEP 1의 "빈" 흐름). non-null이면 이미 스테이징/저장된 선택지를
  /// 편집하는 중이라 삭제 버튼을 보여준다.
  final VoidCallback? onDelete;

  /// 저장 버튼을 눌러 검증(문구 비어있지 않음)을 통과했을 때만 호출된다.
  final ValueChanged<String> onSave;

  const _ChoiceLabelPopoverCard({
    required this.initialLabel,
    required this.autofocus,
    required this.connectedToHint,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<_ChoiceLabelPopoverCard> createState() =>
      _ChoiceLabelPopoverCardState();
}

class _ChoiceLabelPopoverCardState extends State<_ChoiceLabelPopoverCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLabel,
  );
  String? _validationHint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSavePressed() {
    final label = _controller.text.trim();
    if (label.isEmpty) {
      setState(() => _validationHint = '선택지 문구를 입력하세요');
      return;
    }
    setState(() => _validationHint = null);
    widget.onSave(label);
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
              '선택지 만들기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminColors.ivory,
              ),
            ),
            if (widget.connectedToHint != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 13, color: AdminColors.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '연결됨: ${widget.connectedToHint}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AdminColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: widget.autofocus,
              style: TextStyle(color: AdminColors.inputText, fontSize: 13),
              decoration: adminInputDecoration(hintText: '선택지 문구를 입력하세요'),
              onChanged: (_) {
                if (_validationHint != null) {
                  setState(() => _validationHint = null);
                }
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in kChoiceTemplateChips)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _controller.text = chip),
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
            const SizedBox(height: 12),
            if (_validationHint != null) ...[
              Text(
                _validationHint!,
                style: const TextStyle(fontSize: 13, color: AdminColors.danger),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.onDelete != null)
                  TextButton(
                    onPressed: widget.onDelete,
                    child: const Text(
                      '삭제',
                      style: TextStyle(color: AdminColors.danger),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                ElevatedButton(
                  onPressed: _handleSavePressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.gold,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// STEP 2 — 선택지를 기존 노드에 연결하거나, 그 자리에서 새 노드를 만들어
/// 연결한다. "+ 새 노드 만들기"가 목록 맨 위에 오고, 그 아래로 기존 노드
/// 카드 목록([ChoiceTargetPicker] 재사용)이 이어진다. 문구 입력은 여기
/// 없다 — 문구는 [_ChoiceLabelPopoverCard]의 몫이다.
class _ChoiceConnectPopoverCard extends StatelessWidget {
  final List<AdminStoryNodeSummary> candidates;
  final VoidCallback onCreateNewNode;
  final ValueChanged<String> onSelectExisting;

  const _ChoiceConnectPopoverCard({
    required this.candidates,
    required this.onCreateNewNode,
    required this.onSelectExisting,
  });

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
              '노드에 연결하기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminColors.ivory,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: onCreateNewNode,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AdminColors.gold,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                      color: AdminColors.gold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+ 새 노드 만들기',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '또는 기존 노드에 연결하기',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
            const SizedBox(height: 8),
            ChoiceTargetPicker(
              selectedId: null,
              candidates: candidates,
              maxListHeight: 200,
              onSelected: onSelectExisting,
            ),
          ],
        ),
      ),
    );
  }
}
