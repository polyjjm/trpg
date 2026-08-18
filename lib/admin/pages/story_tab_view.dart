import 'package:flutter/material.dart';

import '../../core/story/background_image_inheritance.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/node_id_suggestion.dart';
import '../models/admin_image.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/pending_action.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';
import '../widgets/bulk_node_writer.dart';
import '../widgets/node_editor.dart';
import '../widgets/story_node_sidebar.dart';

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

  const StoryTabView({
    super.key,
    required this.packId,
    required this.pack,
    required this.repository,
    required this.imageRepository,
  });

  @override
  State<StoryTabView> createState() => _StoryTabViewState();
}

class _StoryTabViewState extends State<StoryTabView> {
  /// State가 살아있는 동안(= 지금 이 packId로 고정된 동안, StoryTabView는
  /// author_tool_page.dart에서 packId별로 다른 Key를 받아 팩을 바꿀 때마다
  /// 통째로 재생성된다) 딱 한 번만 만든다. build()에서 매번 새로 호출하면
  /// (예전 코드가 그랬다) 키 입력 한 번마다(onChanged → setState(_dirty))
  /// watchNodeSummaries가 새 Firestore 리스너를 새로 열고 StreamBuilder가
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
  bool _dirty = false;

  /// 사이드바에서 "+ 새 스토리 노드"로 만든 뒤, 아직 한 번도 저장하지 않은 상태인지.
  /// true인 동안만 노드 ID를 직접 입력할 수 있다(저장된 뒤에는 Firestore 문서
  /// id를 그 자리에서 바꿀 수 없으므로 잠근다).
  bool _isNewUnsaved = false;
  bool _autoSelectAttempted = false;

  /// linear 팩에서만 의미가 있다 — "노드별로 쓰기"(기본, 사이드바+에디터) 대신
  /// "한 번에 쓰기"(BulkNodeWriter)로 전환됐는지.
  bool _bulkMode = false;

  /// 사이드바의 "선택 삭제" 체크박스 선택 상태 — 편집 중인 노드 선택
  /// (_selectedNodeId)과는 별개의 축이다(하나는 "지금 뭘 편집 중인가", 다른
  /// 하나는 "일괄 삭제 후보로 뭘 골랐는가").
  final Set<String> _bulkDeleteSelection = {};

  Future<void> _selectNode(String nodeId) async {
    final node = await widget.repository.fetchNode(widget.packId, nodeId);
    if (!mounted || node == null) return;
    setState(() {
      _selectedNodeId = nodeId;
      _editingNode = node;
      _dirty = false;
      _isNewUnsaved = false;
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
  /// 지금 타이핑 중인 내용(dirty)이 있으면 건너뛴다 — 그 사이 서버 스냅샷이
  /// 와도 편집 중인 내용을 덮어쓰지 않기 위해서다. dirty가 풀리는 다음
  /// 빌드(저장하거나, 다른 노드로 옮겼다 돌아오거나)에서 다시 시도된다.
  void _syncEditingNodeWithLiveSummary(
    AdminStoryNode? editingNode,
    List<AdminStoryNodeSummary> summaries,
  ) {
    if (editingNode == null || _isNewUnsaved || _dirty) return;

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
        if (!mounted || _selectedNodeId != editingNode.id || _dirty) return;
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
      if (!mounted || _selectedNodeId != editingNode.id || _dirty) return;
      _selectNode(editingNode.id);
    });
  }

  void _handleAddNode(List<AdminStoryNodeSummary> existing) {
    final candidateId = suggestSequentialNodeIds(
      existing.map((n) => n.id),
      1,
    ).first;

    // 새 노드는 기본적으로 맨 뒤에 이어 쓰는 경우가 대부분이라, 다음 순서로
    // 자동 배정한다 — 배경 이미지 인계가 바로 동작하게 하려는 것(0으로
    // 고정하면 항상 맨 앞으로 끼어들어 인계 규칙이 매번 어긋난다).
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;

    final node = AdminStoryNode(id: candidateId, order: nextOrder);
    setState(() {
      _selectedNodeId = node.id;
      _editingNode = node;
      _dirty = false;
      _isNewUnsaved = true;
    });
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

    final confirmed = await _confirm(
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

    setState(() => _bulkMode = false);
    _showToast(context, '${nodes.length}개 노드를 만들어 승인 요청을 보냈어요 ✓');
  }

  Future<void> _handleDeleteNode(
    String nodeId,
    List<AdminStoryNodeSummary> summaries,
  ) async {
    // 지금 편집 중인 미저장 신규 노드를 지우는 경우 서버에 문서가 없으니 로컬에서만 치운다.
    if (_isNewUnsaved && _editingNode?.id == nodeId) {
      final confirmed = await _confirm(context, '아직 발행된 적 없는 초안이에요. 바로 삭제할까요?');
      if (!confirmed || !mounted) return;
      setState(() {
        _selectedNodeId = null;
        _editingNode = null;
        _dirty = false;
        _isNewUnsaved = false;
      });
      return;
    }

    final node = await widget.repository.fetchNode(widget.packId, nodeId);
    if (!mounted || node == null) return;

    if (node.liveSnapshot == null) {
      final confirmed = await _confirm(context, '아직 발행된 적 없는 초안이에요. 바로 삭제할까요?');
      if (!confirmed || !mounted) return;
      await widget.repository.deleteNodeDoc(widget.packId, nodeId);
      if (!mounted) return;
      if (_selectedNodeId == nodeId) {
        setState(() {
          _selectedNodeId = null;
          _editingNode = null;
          _dirty = false;
        });
      }
      return;
    }

    final confirmed = await _confirm(
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
        _dirty = false;
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

    final confirmed = await _confirm(
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
        if (_isNewUnsaved && _editingNode?.id == id) {
          deletedImmediately += 1;
          clearedEditingSelection = true;
          continue;
        }

        final node = await widget.repository.fetchNode(widget.packId, id);
        if (node == null) {
          deletedImmediately += 1;
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
        _dirty = false;
        _isNewUnsaved = false;
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

  Future<void> _handleSaveDraft() async {
    final node = _editingNode;
    if (node == null) return;

    node.applyBodyTextToBlocks();
    node.dirty = false;

    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;

    setState(() {
      _isNewUnsaved = false;
      _dirty = false;
    });

    _showToast(context, '임시저장됨 ✓ (승인 요청 전까지는 아무한테도 안 보여요)');
  }

  Future<void> _handleRequestApproval() async {
    final node = _editingNode;
    if (node == null) return;

    final isNew = node.isNew;
    final message = isNew
        ? '신규 등록 승인 요청을 보낼까요? 상위 관리자가 승인해야 플레이어에게 보여요.'
        : '수정 승인 요청을 보낼까요? 상위 관리자가 승인하기 전까지는 지금 연재 중인 이전 버전이 그대로 보여요.';
    final confirmed = await _confirm(context, message);
    if (!confirmed || !mounted) return;

    node.pendingAction = isNew ? PendingAction.create : PendingAction.edit;
    node.applyBodyTextToBlocks();
    node.dirty = false;

    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;

    setState(() {
      _isNewUnsaved = false;
      _dirty = false;
    });

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
        final summaries = List<AdminStoryNodeSummary>.from(
          snapshot.data ?? const [],
        );

        // 프로토타입(selectedIndex = 0)과 맞춰, 처음 목록이 들어오면 첫 노드를
        // 자동으로 선택한다 — 한 번만 시도해서 사용자가 명시적으로 선택 해제한
        // 뒤(예: 새 노드 삭제) 다시 자동 선택되지 않게 한다.
        if (!_autoSelectAttempted &&
            _selectedNodeId == null &&
            summaries.isNotEmpty) {
          _autoSelectAttempted = true;
          final firstId = summaries.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedNodeId == null) _selectNode(firstId);
          });
        }

        final editingNode = _editingNode;
        if (_isNewUnsaved &&
            editingNode != null &&
            !summaries.any((s) => s.id == editingNode.id)) {
          summaries.add(
            AdminStoryNodeSummary(
              id: editingNode.id,
              preview: editingNode.previewText,
              status: editingNode.status,
              pendingAction: editingNode.pendingAction,
              order: editingNode.order,
              backgroundImageId: editingNode.backgroundImageId,
              backgroundAppliesForward: editingNode.backgroundAppliesForward,
              hasLiveSnapshot: !editingNode.isNew,
            ),
          );
        }

        _syncEditingNodeWithLiveSummary(editingNode, summaries);

        // 다른 화면에서 승인/삭제되어 목록에서 사라진 노드는 일괄 삭제 선택에서도
        // 같이 걷어낸다 — 안 그러면 "선택 삭제 (N)" 숫자가 더 이상 존재하지
        // 않는 노드까지 세게 된다.
        _bulkDeleteSelection.removeWhere(
          (id) => !summaries.any((s) => s.id == id),
        );

        final inheritedBackgroundImageId = editingNode == null
            ? null
            : resolveInheritedBackgroundImage(
                nodes: summaries.map(
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
            if (widget.pack.type == StoryPackType.linear)
              _BulkModeToggle(
                bulkMode: _bulkMode,
                onChanged: (value) => setState(() => _bulkMode = value),
              ),
            Expanded(
              child: _bulkMode
                  ? BulkNodeWriter(
                      onSave: (pages) => _handleBulkSave(pages, summaries),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StoryNodeSidebar(
                          nodes: summaries,
                          selectedNodeId: _selectedNodeId,
                          selectedNodeDirty: _dirty,
                          onAddNode: () => _handleAddNode(summaries),
                          onSelect: (id) {
                            if (_isNewUnsaved && editingNode?.id == id) return;
                            if (id == _selectedNodeId && !_isNewUnsaved) return;
                            _selectNode(id);
                          },
                          onDelete: (id) => _handleDeleteNode(id, summaries),
                          bulkSelectedIds: _bulkDeleteSelection,
                          onToggleBulkSelect: _toggleBulkDeleteSelect,
                          onToggleSelectAll: () =>
                              _toggleBulkDeleteSelectAll(summaries),
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
                                        imgSnapshot.data ??
                                        const <AdminImage>[];
                                    return NodeEditor(
                                      key: ValueKey(_selectedNodeId),
                                      node: editingNode,
                                      dirty: _dirty,
                                      isIdEditable: _isNewUnsaved,
                                      images: images,
                                      packType: widget.pack.type,
                                      inheritedBackgroundImageId:
                                          inheritedBackgroundImageId,
                                      onChanged: () =>
                                          setState(() => _dirty = true),
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
            ),
          ],
        );
      },
    );
  }
}

class _BulkModeToggle extends StatelessWidget {
  final bool bulkMode;
  final ValueChanged<bool> onChanged;

  const _BulkModeToggle({required this.bulkMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AdminColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _ModeButton(
            label: '노드별로 쓰기',
            selected: !bulkMode,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 8),
          _ModeButton(
            label: '한 번에 쓰기',
            selected: bulkMode,
            onTap: () => onChanged(true),
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

Future<bool> _confirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AdminColors.panel,
      content: Text(message, style: TextStyle(color: AdminColors.ivory)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('확인', style: TextStyle(color: AdminColors.gold)),
        ),
      ],
    ),
  );
  return result ?? false;
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
