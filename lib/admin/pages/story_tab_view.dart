import 'package:flutter/material.dart';

import '../../core/story/background_image_inheritance.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/node_edit_session_cache.dart';
import '../data/node_id_suggestion.dart';
import '../models/admin_image.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/pending_action.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';
import '../widgets/bulk_node_writer.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/labeled_field.dart';
import '../widgets/node_editor.dart';
import '../widgets/story_map_view.dart';
import '../widgets/story_node_sidebar.dart';

/// "노드별로 쓰기"(사이드바+에디터, 기본) / "한 번에 쓰기"(BulkNodeWriter,
/// linear 팩 전용) / "구조 보기"(StoryMapView) — 셋 중 하나만 보인다.
enum _ViewMode { single, bulk, map }

/// [AdminStoryNode](세션 캐시나 fetchNode로 얻은 전체 문서)를 사이드바용
/// 요약으로 압축한다 — 캐시에 있는 노드를 표시 목록에 끼워 넣을 때(신규
/// 초안이든, 손댄 기존 노드든) 공통으로 쓴다.
AdminStoryNodeSummary summaryFromNode(AdminStoryNode node) {
  return AdminStoryNodeSummary(
    id: node.id,
    preview: node.previewText,
    status: node.status,
    pendingAction: node.pendingAction,
    order: node.order,
    backgroundImageId: node.backgroundImageId,
    backgroundAppliesForward: node.backgroundAppliesForward,
    hasLiveSnapshot: !node.isNew,
    choices: node.choices,
    nextNodeId: node.nextNodeId,
  );
}

/// "스토리 노드" 탭. 사이드바(노드 목록) + 노드 편집 폼을 이어 붙이고,
/// 임시저장/승인요청/삭제/승인취소 같은 실제 Firestore 쓰기 동작을 담당한다.
///
/// 선택된 노드는 [_editingNode]에 로컬 가변 복사본으로 들고 있다가 명시적으로
/// 저장할 때만 Firestore에 반영한다 — 그 사이에 서버 스트림이 갱신돼도
/// 지금 타이핑 중인 내용을 덮어쓰지 않기 위해서다(story_editor_prototype.html이
/// 브라우저 메모리 하나만 썼던 것과 같은 이유).
class StoryTabView extends StatefulWidget {
  final String packId;

  /// pack.type에 따라 NodeEditor 하단이 선택지 목록/다음 노드 입력으로
  /// 갈리고, pack.defaultBackgroundImage는 어떤 노드도 배경을 명시적으로
  /// 안 골랐을 때의 최종 폴백이다(lib/core/story/
  /// background_image_inheritance.dart). 부모(AuthorToolPage)가 이미 들고
  /// 있는 AdminStoryPack을 통째로 내려받는다 — 팩 목록 스트림이 갱신되면
  /// 부모가 새 pack 값으로 이 위젯을 다시 만들어 준다.
  final AdminStoryPack pack;
  final AdminStoryRepository repository;
  final AdminImageRepository imageRepository;

  /// 저장 안 한 편집 내용의 세션 캐시 — AuthorToolPage가 소유해서 팩 전환/탭
  /// 전환에도 살아남는다(자세한 설명은 node_edit_session_cache.dart 참고).
  /// 이 위젯 자신은 팩이 바뀔 때마다 통째로 재생성되므로, 캐시를 여기 State
  /// 안에 두면 전환할 때마다 사라져 버린다 — 그래서 부모가 만든 걸 그대로
  /// 받아 쓴다.
  final NodeEditSessionCache sessionCache;

  const StoryTabView({
    super.key,
    required this.packId,
    required this.pack,
    required this.repository,
    required this.imageRepository,
    required this.sessionCache,
  });

  @override
  State<StoryTabView> createState() => _StoryTabViewState();
}

class _StoryTabViewState extends State<StoryTabView> {
  /// State가 살아있는 동안(= 지금 이 packId로 고정된 동안, StoryTabView는
  /// author_tool_page.dart에서 packId별로 다른 Key를 받아 팩을 바꿀 때마다
  /// 통째로 재생성된다) 딱 한 번만 만든다. build()에서 매번 새로 호출하면
  /// (예전 코드가 그랬다) 키 입력 한 번마다(onChanged → setState) watchNodeSummaries가
  /// 새 Firestore 리스너를 새로 열고 StreamBuilder가
  /// 구독을 끊었다 다시 맺으면서 사이드바가 깜빡였다 — author_tool_page.dart의
  /// _packsStream, approvals_tab.dart의 _pendingStream과 같은 이유로 같은
  /// 패턴을 따른다.
  late final Stream<List<AdminStoryNodeSummary>> _nodeSummariesStream = widget
      .repository
      .watchNodeSummaries(widget.packId);

  /// 이미지 라이브러리는 팩과 무관하게 공유되지만(FIRESTORE_SCHEMA.md), 같은
  /// 이유로 build()에서 매번 새로 구독하지 않는다.
  late final Stream<List<AdminImage>> _imagesStream = widget.imageRepository
      .watchImages();

  String? _selectedNodeId;
  AdminStoryNode? _editingNode;
  bool _autoSelectAttempted = false;

  _ViewMode _viewMode = _ViewMode.single;

  /// 스토리맵에서 "+" 드래그로 빈 캔버스에 놓아 지금 편집 중인 노드가 방금
  /// 만들어졌을 때만 값이 있다 — 그 출발 노드 id. NodeEditor 헤더의 컨텍스트
  /// 라인에 쓰인다. [_creationSourceChoiceIndex]와 짝을 이룬다(interactive
  /// 팩에서만 값이 있다 — 그 출발 노드의 choices 배열 안, 이 노드를 향해
  /// 방금 만들어진 선택지의 인덱스). 둘 다 [_selectNode]가 명시적으로
  /// 넘겨줄 때만 세팅되고, 다른 경로(사이드바 클릭, 맵에서 노드 박스 탭 등)로
  /// 노드를 선택하면 자동으로 null로 리셋된다.
  String? _creationSourceId;
  int? _creationSourceChoiceIndex;

  /// 사이드바의 "선택 삭제" 체크박스 선택 상태 — 편집 중인 노드 선택
  /// (_selectedNodeId)과는 별개의 축이다(하나는 "지금 뭘 편집 중인가", 다른
  /// 하나는 "일괄 삭제 후보로 뭘 골랐는가").
  final Set<String> _bulkDeleteSelection = {};

  /// 세션 캐시(widget.sessionCache)에 이 노드의 저장 안 한 편집 내용이
  /// 있으면 그걸 그대로 복원한다 — Firestore에서 새로 읽어오면 방금까지
  /// 타이핑하던 내용이 사라진다. 캐시에 없을 때만 실제로 fetchNode()한다.
  Future<void> _selectNode(
    String nodeId, {
    String? creationSourceId,
    int? creationSourceChoiceIndex,
  }) async {
    final cached = widget.sessionCache.get(widget.packId, nodeId);
    if (cached != null) {
      setState(() {
        _selectedNodeId = nodeId;
        _editingNode = cached;
        _creationSourceId = creationSourceId;
        _creationSourceChoiceIndex = creationSourceChoiceIndex;
      });
      return;
    }

    final node = await widget.repository.fetchNode(widget.packId, nodeId);
    if (!mounted || node == null) return;
    setState(() {
      _selectedNodeId = nodeId;
      _editingNode = node;
      _creationSourceId = creationSourceId;
      _creationSourceChoiceIndex = creationSourceChoiceIndex;
    });
  }

  /// [_editingNode]는 명시적으로 저장할 때만 Firestore에 반영되는 로컬 가변
  /// 복사본이다(클래스 상단 doc 참고) — 그래서 다른 화면(admin 승인 대기함)에서
  /// 이 노드를 승인/반려해도 [_nodeSummariesStream]은 라이브로 갱신되지만
  /// [_editingNode].status/pendingAction/liveSnapshot은 이 메서드가 없으면
  /// F5 전까지 계속 낡은 값을 들고 있는다.
  ///
  /// status/pendingAction만 부분적으로 덮어쓰는 대신 [_selectNode]로 통째로
  /// 다시 읽어오는 이유: liveSnapshot의 실제 내용(승인 시점 콘텐츠 스냅샷)은
  /// 다음 saveNode() 호출이 Firestore 규칙의 "liveSnapshot 불변" 조건을
  /// 통과하려면 서버 값과 정확히 같아야 한다 — 목록 스트림은 liveSnapshot
  /// 유무만 알고 내용은 모르므로, 내용까지 필요한 경우엔 결국 fetchNode()가
  /// 필요하다. 요약과 어긋난 게 없으면(가장 흔한 경우) 아무 것도 하지 않는다.
  ///
  /// 세션 캐시에 저장 안 한 편집 내용이 있으면 건너뛴다 — 그 사이 서버
  /// 스냅샷이 와도 편집 중인 내용을 덮어쓰지 않기 위해서다. 캐시가 비워지는
  /// 다음 빌드(저장하거나, 다른 노드로 옮겼다 돌아오거나)에서 다시 시도된다.
  void _syncEditingNodeWithLiveSummary(
    AdminStoryNode? editingNode,
    List<AdminStoryNodeSummary> summaries,
  ) {
    if (editingNode == null) return;
    // 세션 캐시에 있으면 건너뛴다 — 저장 안 한 편집 내용이 있다는 뜻이고,
    // 한 번도 저장 안 한 신규 초안(_handleAddNode가 만들자마자 캐시에 넣는다)도
    // 항상 여기 걸린다.
    if (widget.sessionCache.has(widget.packId, editingNode.id)) return;

    AdminStoryNodeSummary? liveSummary;
    for (final summary in summaries) {
      if (summary.id == editingNode.id) {
        liveSummary = summary;
        break;
      }
    }

    if (liveSummary == null) {
      // 다른 화면에서 삭제 요청이 승인되어 노드 자체가 사라졌다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _selectedNodeId != editingNode.id ||
            widget.sessionCache.has(widget.packId, editingNode.id)) {
          return;
        }
        setState(() {
          _selectedNodeId = null;
          _editingNode = null;
        });
      });
      return;
    }

    final outOfSync =
        liveSummary.status != editingNode.status ||
        liveSummary.pendingAction != editingNode.pendingAction ||
        liveSummary.hasLiveSnapshot == editingNode.isNew;
    if (!outOfSync) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selectedNodeId != editingNode.id ||
          widget.sessionCache.has(widget.packId, editingNode.id)) {
        return;
      }
      _selectNode(editingNode.id);
    });
  }

  /// [existing]은 반드시 Firestore에 실제로 저장된 노드 목록(rawSummaries)이어야
  /// 한다 — 사이드바 표시용으로 미저장 초안을 끼워 넣은 목록을 넘기면,
  /// suggestSequentialNodeIds가 그 초안을 이미 존재하는 노드로 세어 다음
  /// "+" 클릭 때 번호를 하나 건너뛴다(실제로 겪은 버그 — story_tab_view.dart의
  /// build()에서 rawSummaries/displaySummaries를 분리해 두는 이유). 세션
  /// 캐시에만 있는(아직 저장 안 한) 신규 노드 id도 같이 피해야 한다 — 안
  /// 그러면 "+"를 두 번 눌렀을 때 첫 번째로 만든 미저장 초안과 같은 id를
  /// 다시 제안해서 그 초안을 덮어써 버린다.
  Future<void> _handleAddNode(List<AdminStoryNodeSummary> existing) async {
    final takenIds = {
      ...existing.map((n) => n.id),
      ...widget.sessionCache.nodeIdsForPack(widget.packId),
    };
    final candidateId = suggestSequentialNodeIds(takenIds, 1).first;

    // 새 노드는 기본적으로 맨 뒤에 이어 쓰는 경우가 대부분이라, 다음 순서로
    // 자동 배정한다 — 배경 이미지 인계가 바로 동작하게 하려는 것(0으로
    // 고정하면 항상 맨 앞으로 끼어들어 인계 규칙이 매번 어긋난다).
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;

    final node = AdminStoryNode(id: candidateId, order: nextOrder);
    // 만들자마자 세션 캐시에 넣는다 — 아무것도 안 쳐도 이 초안은 "존재"하고,
    // 다른 노드로 옮겼다 돌아와도(또는 팩/탭을 오가도) 그대로 남아있어야 한다.
    widget.sessionCache.put(widget.packId, node);
    setState(() {
      _selectedNodeId = node.id;
      _editingNode = node;
    });
  }

  /// 사이드바 드래그 재정렬 — [displayed]는 지금 화면에 보이는 순서 그대로의
  /// 목록(order로 정렬된 displaySummaries)이다. 옮긴 자리를 반영해 순서를
  /// 다시 매기고, order가 실제로 바뀐 노드만 세션 캐시에 반영한다 — 다른
  /// 편집과 똑같이 "임시저장"/"승인 요청 보내기"를 눌러야 Firestore에
  /// 반영되는 초안일 뿐, 드래그만으로 즉시 쓰지 않는다.
  ///
  /// 배경 이미지 인계 체인(lib/core/story/background_image_inheritance.dart)은
  /// order를 기준으로 매 build마다 다시 계산되므로, 여기서 order만 바꿔
  /// 두면 재정렬 직후 미리보기에 곧바로 반영된다 — 별도로 인계 값을
  /// 다시 계산해 넣을 필요가 없다.
  Future<void> _handleReorder(
    List<AdminStoryNodeSummary> displayed,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView의 관례: 아래로 옮길 때 newIndex는 옮기는 항목을
    // 뺀 목록 기준이라, oldIndex보다 크면 1을 빼야 실제 삽입 위치가 된다.
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final reordered = List<AdminStoryNodeSummary>.from(displayed);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    var changed = false;
    for (var i = 0; i < reordered.length; i++) {
      final summary = reordered[i];
      if (summary.order == i) continue;

      // 지금 편집 중인 바로 그 객체라면 그 인스턴스를 그대로 고친다 —
      // 그래야 에디터가 들고 있는 참조와 캐시에 들어가는 참조가 갈라지지
      // 않는다. 아니라면 캐시에서, 그것도 없으면 Firestore에서 가져온다.
      AdminStoryNode? node = _editingNode?.id == summary.id
          ? _editingNode
          : null;
      node ??= widget.sessionCache.get(widget.packId, summary.id);
      node ??= await widget.repository.fetchNode(widget.packId, summary.id);
      if (!mounted) return;
      if (node == null) continue;

      node.order = i;
      widget.sessionCache.put(widget.packId, node);
      changed = true;
    }

    if (!mounted || !changed) return;
    setState(() {});
  }

  /// "한 번에 쓰기" 저장 — 페이지 수만큼 초안 노드를 만들어 순서대로
  /// nextNodeId로 이어 붙이고, 한 번의 배치 쓰기로 전부 만든 뒤 바로 승인
  /// 요청까지 보낸다("승인 없이 반영되지 않는다"는 원칙은 그대로 유지 —
  /// pendingAction: create일 뿐 status는 여전히 draft다).
  Future<void> _handleBulkSave(
    List<BulkPagePreview> pages,
    List<AdminStoryNodeSummary> existing,
  ) async {
    if (pages.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      '${pages.length}개 노드를 만들어 승인 요청을 보낼까요? 상위 관리자가 승인해야 플레이어에게 보여요.',
    );
    if (!confirmed || !mounted) return;

    final ids = suggestSequentialNodeIds(
      existing.map((n) => n.id),
      pages.length,
    );
    final startOrder = existing.isEmpty
        ? 0
        : existing.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;

    final nodes = <AdminStoryNode>[];
    for (var i = 0; i < pages.length; i++) {
      final node = AdminStoryNode(
        id: ids[i],
        order: startOrder + i,
        bodyText: pages[i].text,
        nextNodeId: i < pages.length - 1 ? ids[i + 1] : null,
        pendingAction: PendingAction.create,
      );
      node.applyBodyTextToBlocks();
      nodes.add(node);
    }

    await widget.repository.saveNodesBatch(widget.packId, nodes);
    if (!mounted) return;

    setState(() => _viewMode = _ViewMode.single);
    _showToast(context, '${nodes.length}개 노드를 만들어 승인 요청을 보냈어요 ✓');
  }

  /// [rawSummaries]는 반드시 Firestore에 실제로 저장된 노드 목록이어야 한다
  /// — "이 nodeId가 한 번이라도 저장된 적 있는지"를 여기서 직접 판단하기
  /// 때문이다(세션 캐시에만 있는 신규 초안은 지울 Firestore 문서 자체가
  /// 없다). 지금 편집 화면에 열려 있는 것이든, 다른 노드로 옮겼다가 사이드바
  /// 목록에서 바로 지우는 것이든 똑같이 다룬다.
  Future<void> _handleDeleteNode(
    String nodeId,
    List<AdminStoryNodeSummary> rawSummaries,
  ) async {
    final isPersisted = rawSummaries.any((s) => s.id == nodeId);

    if (!isPersisted) {
      final confirmed = await showConfirmDialog(
        context,
        '아직 발행된 적 없는 초안이에요. 바로 삭제할까요?',
      );
      if (!confirmed || !mounted) return;
      widget.sessionCache.remove(widget.packId, nodeId);
      if (_selectedNodeId == nodeId) {
        setState(() {
          _selectedNodeId = null;
          _editingNode = null;
        });
      } else {
        setState(() {});
      }
      return;
    }

    // 지금 편집 화면에 없더라도, 예전에 열어서 손대 놓고 저장 안 한 채로 지우는
    // 경우일 수 있다 — 캐시에 남아있으면 지운 노드가 다시 "수정됨"으로
    // 보이는 유령 항목이 된다.
    widget.sessionCache.remove(widget.packId, nodeId);

    final node = await widget.repository.fetchNode(widget.packId, nodeId);
    if (!mounted || node == null) return;

    if (node.liveSnapshot == null) {
      final confirmed = await showConfirmDialog(
        context,
        '아직 발행된 적 없는 초안이에요. 바로 삭제할까요?',
      );
      if (!confirmed || !mounted) return;
      await widget.repository.deleteNodeDoc(widget.packId, nodeId);
      if (!mounted) return;
      if (_selectedNodeId == nodeId) {
        setState(() {
          _selectedNodeId = null;
          _editingNode = null;
        });
      }
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      '이미 연재 중인 노드예요. 삭제 요청을 보낼까요? 상위 관리자가 승인하기 전까지는 계속 플레이어에게 그대로 보여요.',
    );
    if (!confirmed || !mounted) return;

    node.pendingAction = PendingAction.delete;
    node.dirty = false;
    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;

    if (_selectedNodeId == nodeId) {
      setState(() {
        _editingNode = node;
      });
    }
  }

  void _toggleBulkDeleteSelect(String id) {
    setState(() {
      if (!_bulkDeleteSelection.remove(id)) _bulkDeleteSelection.add(id);
    });
  }

  void _toggleBulkDeleteSelectAll(List<AdminStoryNodeSummary> summaries) {
    setState(() {
      if (summaries.isNotEmpty &&
          _bulkDeleteSelection.length == summaries.length) {
        _bulkDeleteSelection.clear();
      } else {
        _bulkDeleteSelection
          ..clear()
          ..addAll(summaries.map((s) => s.id));
      }
    });
  }

  /// 선택 중에 발행된 적 없는 초안과 이미 연재 중인 노드가 섞여 있으면 자동으로
  /// 나눠 처리한다 — 초안은 그 자리에서 바로 지우고, 연재 중인 노드는 단건
  /// 삭제 버튼과 같은 삭제 요청(pendingAction: delete)만 걸어 둔다. 혼재된
  /// 선택을 통째로 막는 대신 이렇게 자동으로 나누는 쪽을 택했다 — "일부는 요청이
  /// 필요하다"는 이유로 이미 발행된 적 없는 나머지 노드까지 못 지우게 막는 건
  /// 불필요한 마찰이라고 판단했다. 대신 끝나고 나서 뭐가 즉시 지워졌고 뭐가
  /// 요청만 걸렸는지 요약으로 보여준다.
  Future<void> _handleBulkDelete() async {
    final ids = _bulkDeleteSelection.toList();
    if (ids.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      '${ids.length}개 노드를 삭제할까요? 발행된 적 없는 노드는 즉시 삭제되고, 이미 연재 중인 노드는 '
      '삭제 요청이 들어가 상위 관리자 승인 후 삭제돼요.',
    );
    if (!confirmed || !mounted) return;

    var deletedImmediately = 0;
    var requestedForApproval = 0;
    var failed = 0;
    var clearedEditingSelection = false;

    for (final id in ids) {
      try {
        widget.sessionCache.remove(widget.packId, id);

        // 세션 캐시에만 있던(한 번도 저장 안 한) 초안이면 fetchNode가
        // null을 반환한다 — 지울 Firestore 문서 자체가 없으니 그걸로 끝.
        final node = await widget.repository.fetchNode(widget.packId, id);
        if (node == null) {
          deletedImmediately += 1;
          if (_selectedNodeId == id) clearedEditingSelection = true;
          continue;
        }

        if (node.liveSnapshot == null) {
          await widget.repository.deleteNodeDoc(widget.packId, id);
          deletedImmediately += 1;
        } else {
          node.pendingAction = PendingAction.delete;
          node.dirty = false;
          await widget.repository.saveNode(widget.packId, node);
          requestedForApproval += 1;
        }

        if (_selectedNodeId == id) clearedEditingSelection = true;
      } catch (_) {
        failed += 1;
      }
    }

    if (!mounted) return;
    setState(() {
      _bulkDeleteSelection.clear();
      if (clearedEditingSelection) {
        _selectedNodeId = null;
        _editingNode = null;
      }
    });

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminColors.panel,
        title: Text('일괄 삭제 완료', style: TextStyle(color: AdminColors.ivory)),
        content: Text(
          '즉시 삭제 $deletedImmediately개 · 삭제 요청 $requestedForApproval개'
          '${failed > 0 ? ' · 실패 $failed개' : ''}',
          style: TextStyle(color: AdminColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인', style: TextStyle(color: AdminColors.gold)),
          ),
        ],
      ),
    );
  }

  /// 스토리맵에서 "+" 드래그로 빈 캔버스에 놓아 만들어진 노드를 저장할
  /// 때만 동작한다([_creationSourceId]/[_creationSourceChoiceIndex]가 둘 다
  /// 있을 때) — 드롭 순간엔 타이핑할 틈이 없어서 출발 노드에 걸린 선택지의
  /// 문구가 비어 있을 수 있다(story_map_choice_popover_spec.md). 그 문구가
  /// 아직 비어 있으면 저장 직전에 한 번 물어본다. "나중에"를 골라도 저장은
  /// 그대로 진행된다 — 저장을 막는 관문이 아니라 놓치기 쉬운 빈칸을 짚어
  /// 주는 안내일 뿐이다.
  Future<void> _fillCreationChoiceLabelIfNeeded() async {
    final sourceId = _creationSourceId;
    final choiceIndex = _creationSourceChoiceIndex;
    if (sourceId == null || choiceIndex == null) return;

    final sourceNode =
        widget.sessionCache.get(widget.packId, sourceId) ??
        await widget.repository.fetchNode(widget.packId, sourceId);
    if (!mounted ||
        sourceNode == null ||
        choiceIndex >= sourceNode.choices.length) {
      return;
    }
    if (sourceNode.choices[choiceIndex].label.trim().isNotEmpty) return;

    final label = await _promptChoiceLabel();
    if (!mounted || label == null || label.trim().isEmpty) return;

    sourceNode.choices[choiceIndex].label = label.trim();
    widget.sessionCache.put(widget.packId, sourceNode);
  }

  Future<String?> _promptChoiceLabel() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminColors.panel,
        title: Text(
          '이 노드로 연결한 선택지 문구를 입력해주세요',
          style: TextStyle(color: AdminColors.ivory, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AdminColors.inputText),
          decoration: adminInputDecoration(hintText: '예: 문을 연다'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('나중에', style: TextStyle(color: AdminColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.gold,
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSaveDraft() async {
    final node = _editingNode;
    if (node == null) return;

    await _fillCreationChoiceLabelIfNeeded();
    if (!mounted) return;

    node.dirty = false;

    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;

    // 저장됐으니 이제 Firestore가 최신이다 — 캐시에 남겨 두면 다음에 열 때
    // 방금 저장한 내용을 "아직 저장 안 된 것"처럼 잘못 보여주게 된다.
    widget.sessionCache.remove(widget.packId, node.id);
    _creationSourceId = null;
    _creationSourceChoiceIndex = null;
    setState(() {});

    _showToast(context, '임시저장됨 ✓ (승인 요청 전까지는 아무한테도 안 보여요)');
  }

  Future<void> _handleRequestApproval() async {
    final node = _editingNode;
    if (node == null) return;

    await _fillCreationChoiceLabelIfNeeded();
    if (!mounted) return;

    final isNew = node.isNew;
    final message = isNew
        ? '신규 등록 승인 요청을 보낼까요? 상위 관리자가 승인해야 플레이어에게 보여요.'
        : '수정 승인 요청을 보낼까요? 상위 관리자가 승인하기 전까지는 지금 연재 중인 이전 버전이 그대로 보여요.';
    final confirmed = await showConfirmDialog(context, message);
    if (!confirmed || !mounted) return;

    node.pendingAction = isNew ? PendingAction.create : PendingAction.edit;
    node.dirty = false;

    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;

    widget.sessionCache.remove(widget.packId, node.id);
    _creationSourceId = null;
    _creationSourceChoiceIndex = null;
    setState(() {});

    _showToast(context, '승인 요청 보냄 ✓ 상위 관리자 승인 대기 중');
  }

  Future<void> _handleCancelDeleteRequest() async {
    final node = _editingNode;
    if (node == null) return;

    node.pendingAction = null;
    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminStoryNodeSummary>>(
      stream: _nodeSummariesStream,
      builder: (context, snapshot) {
        // Firestore에 실제로 저장된 노드만 담는다 — id 자동 제안
        // (suggestSequentialNodeIds)과 "한 번에 쓰기"의 순서 계산은 반드시
        // 이 목록만 봐야 한다. 아래 displaySummaries(사이드바 표시용, 아직
        // 저장 안 한 초안까지 포함)를 여기 섞어 넘기면, 방금 만든 미저장
        // 초안이 이미 존재하는 노드로 카운트되어 다음 "+" 클릭 때 번호를
        // 하나 건너뛴다(실제로 겪은 버그).
        final rawSummaries = List<AdminStoryNodeSummary>.from(
          snapshot.data ?? const [],
        );

        // 프로토타입(selectedIndex = 0)과 맞춰, 처음 목록이 들어오면 첫 노드를
        // 자동으로 선택한다 — 한 번만 시도해서 사용자가 명시적으로 선택 해제한
        // 뒤(예: 새 노드 삭제) 다시 자동 선택되지 않게 한다.
        if (!_autoSelectAttempted &&
            _selectedNodeId == null &&
            rawSummaries.isNotEmpty) {
          _autoSelectAttempted = true;
          final firstId = rawSummaries.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedNodeId == null) _selectNode(firstId);
          });
        }

        final editingNode = _editingNode;

        // "+ 새 스토리 노드"로 만든 뒤 아직 한 번도 저장하지 않은 상태인지 —
        // rawSummaries(Firestore에 실제로 저장된 목록)에 이 id가 없으면
        // 아직 저장 전이라는 뜻이다. 별도 필드로 직접 관리하지 않는 이유:
        // 캐시에서 복원한 신규 초안을 다시 선택할 때 값을 깜빡 false로
        // 고정해 버리는 버그가 있었다(실제로 겪음) — rawSummaries 기준으로
        // 매 build마다 다시 계산하면 그런 수동 동기화 실수 자체가 없어진다.
        final isNewUnsaved =
            editingNode != null &&
            !rawSummaries.any((s) => s.id == editingNode.id);

        // 사이드바 표시 전용 목록. 세션 캐시에 있는 노드는(이미 저장된 적
        // 있는 노드를 손댄 것이든, 한 번도 저장 안 한 신규 초안이든) 항상
        // rawSummaries 대신 캐시 값을 쓴다 — 그래야 순서를 드래그로 바꾸거나
        // 본문을 고친 게 저장 전에도 미리보기(순서, 배경 이미지 인계 계산)에
        // 바로 반영된다. rawSummaries 자체는 절대 건드리지 않는다.
        final displaySummaries = <AdminStoryNodeSummary>[];
        final coveredIds = <String>{};

        for (final raw in rawSummaries) {
          final cached = widget.sessionCache.get(widget.packId, raw.id);
          displaySummaries.add(cached == null ? raw : summaryFromNode(cached));
          coveredIds.add(raw.id);
        }
        for (final cachedId in widget.sessionCache.nodeIdsForPack(
          widget.packId,
        )) {
          if (coveredIds.contains(cachedId)) continue;
          final cached = widget.sessionCache.get(widget.packId, cachedId);
          if (cached == null) continue;
          displaySummaries.add(summaryFromNode(cached));
          coveredIds.add(cachedId);
        }
        displaySummaries.sort((a, b) => a.order.compareTo(b.order));

        // "수정됨" 배지 — 세션 캐시에 항목이 있는 노드 id 전부(저장된 적
        // 있는 노드를 손댔든, 한 번도 저장 안 한 신규 초안이든).
        final unsavedNodeIds = widget.sessionCache
            .nodeIdsForPack(widget.packId)
            .toSet();

        _syncEditingNodeWithLiveSummary(editingNode, rawSummaries);

        // 다른 화면에서 승인/삭제되어 목록에서 사라진 노드는 일괄 삭제 선택에서도
        // 같이 걷어낸다 — 안 그러면 "선택 삭제 (N)" 숫자가 더 이상 존재하지
        // 않는 노드까지 세게 된다.
        _bulkDeleteSelection.removeWhere(
          (id) => !displaySummaries.any((s) => s.id == id),
        );

        final inheritedBackgroundImageId = editingNode == null
            ? null
            : resolveInheritedBackgroundImage(
                nodes: displaySummaries.map(
                  (s) => (
                    order: s.order,
                    backgroundImage: s.backgroundImageId,
                    backgroundAppliesForward: s.backgroundAppliesForward,
                  ),
                ),
                targetOrder: editingNode.order,
                packDefaultBackgroundImage: widget.pack.defaultBackgroundImage,
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ViewModeToggle(
              mode: _viewMode,
              showBulkOption: widget.pack.type == StoryPackType.linear,
              onChanged: (mode) => setState(() => _viewMode = mode),
            ),
            Expanded(
              child: switch (_viewMode) {
                _ViewMode.bulk => BulkNodeWriter(
                  onSave: (pages) => _handleBulkSave(pages, rawSummaries),
                ),
                _ViewMode.map => StoryMapView(
                  packId: widget.packId,
                  packType: widget.pack.type,
                  nodes: displaySummaries,
                  unsavedNodeIds: unsavedNodeIds,
                  sessionCache: widget.sessionCache,
                  repository: widget.repository,
                  onOpenNode: (id) {
                    setState(() => _viewMode = _ViewMode.single);
                    _selectNode(id);
                  },
                  onNodeCreatedFromDrag: (newNodeId, sourceId, choiceIndex) {
                    setState(() => _viewMode = _ViewMode.single);
                    _selectNode(
                      newNodeId,
                      creationSourceId: sourceId,
                      creationSourceChoiceIndex: choiceIndex,
                    );
                  },
                  onChanged: () => setState(() {}),
                ),
                _ViewMode.single => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StoryNodeSidebar(
                      nodes: displaySummaries,
                      selectedNodeId: _selectedNodeId,
                      unsavedNodeIds: unsavedNodeIds,
                      onAddNode: () => _handleAddNode(rawSummaries),
                      onSelect: (id) {
                        if (id == _selectedNodeId) return;
                        _selectNode(id);
                      },
                      onDelete: (id) => _handleDeleteNode(id, rawSummaries),
                      onReorder: (oldIndex, newIndex) =>
                          _handleReorder(displaySummaries, oldIndex, newIndex),
                      bulkSelectedIds: _bulkDeleteSelection,
                      onToggleBulkSelect: _toggleBulkDeleteSelect,
                      onToggleSelectAll: () =>
                          _toggleBulkDeleteSelectAll(displaySummaries),
                      onBulkDelete: _handleBulkDelete,
                    ),
                    Expanded(
                      child: editingNode == null
                          ? Center(
                              child: Text(
                                '노드를 선택하거나 새로 만들어주세요.',
                                style: TextStyle(color: AdminColors.muted),
                              ),
                            )
                          : StreamBuilder<List<AdminImage>>(
                              stream: _imagesStream,
                              builder: (context, imgSnapshot) {
                                final images =
                                    imgSnapshot.data ?? const <AdminImage>[];
                                return NodeEditor(
                                  // id 문자열이 아니라 객체 identity로
                                  // 키를 잡는다 — "새 스토리 노드"를 두
                                  // 번 누르면 두 번째도 같은 id를
                                  // 제안할 수 있어서(취소된 적 없는
                                  // 세션 캐시 기준 재확인), _selectedNodeId
                                  // 문자열만으로는 항상 다른 값이라는
                                  // 보장이 없다. ValueKey(id)를 쓰면
                                  // Flutter가 "같은 위젯"으로 보고
                                  // NodeBodyEditor의 TextFormField를
                                  // 다시 만들지 않아 화면에 이전 내용이
                                  // 남는다. editingNode는 세션이 바뀔
                                  // 때마다 다른 인스턴스이므로 ObjectKey는
                                  // id 충돌과 무관하게 항상 다시 마운트한다.
                                  key: ObjectKey(editingNode),
                                  node: editingNode,
                                  dirty: widget.sessionCache.has(
                                    widget.packId,
                                    editingNode.id,
                                  ),
                                  isIdEditable: isNewUnsaved,
                                  images: images,
                                  packType: widget.pack.type,
                                  candidates: displaySummaries,
                                  inheritedBackgroundImageId:
                                      inheritedBackgroundImageId,
                                  creationSourceId:
                                      _selectedNodeId == editingNode.id
                                      ? _creationSourceId
                                      : null,
                                  onChanged: () {
                                    // 노드 ID 입력칸은 신규 초안일 때만
                                    // 편집 가능하고(isIdEditable), 그
                                    // 동안 사용자가 id를 바꿨을 수 있다
                                    // — 그러면 캐시 키도 옮겨야 예전
                                    // id로 캐시된 항목이 유령으로
                                    // 남지 않는다.
                                    if (_selectedNodeId != null &&
                                        _selectedNodeId != editingNode.id) {
                                      widget.sessionCache.remove(
                                        widget.packId,
                                        _selectedNodeId!,
                                      );
                                    }
                                    widget.sessionCache.put(
                                      widget.packId,
                                      editingNode,
                                    );
                                    setState(
                                      () => _selectedNodeId = editingNode.id,
                                    );
                                  },
                                  onSaveDraft: _handleSaveDraft,
                                  onRequestApproval: _handleRequestApproval,
                                  onCancelDeleteRequest:
                                      _handleCancelDeleteRequest,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              },
            ),
          ],
        );
      },
    );
  }
}

/// "노드별로 쓰기"/"한 번에 쓰기"(linear 팩만)/"구조 보기" 3방향 토글.
class _ViewModeToggle extends StatelessWidget {
  final _ViewMode mode;
  final bool showBulkOption;
  final ValueChanged<_ViewMode> onChanged;

  const _ViewModeToggle({
    required this.mode,
    required this.showBulkOption,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AdminColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _ModeButton(
            label: '노드별로 쓰기',
            selected: mode == _ViewMode.single,
            onTap: () => onChanged(_ViewMode.single),
          ),
          if (showBulkOption) ...[
            const SizedBox(width: 8),
            _ModeButton(
              label: '한 번에 쓰기',
              selected: mode == _ViewMode.bulk,
              onTap: () => onChanged(_ViewMode.bulk),
            ),
          ],
          const SizedBox(width: 8),
          _ModeButton(
            label: '구조 보기',
            selected: mode == _ViewMode.map,
            onTap: () => onChanged(_ViewMode.map),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : AdminColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

void _showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AdminColors.panel2,
      duration: const Duration(seconds: 2),
    ),
  );
}
