import 'package:flutter/material.dart';

import '../../core/story/background_image_inheritance.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/admin_image.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/pending_action.dart';
import '../widgets/admin_theme.dart';
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
  late final Stream<List<AdminStoryNodeSummary>> _nodeSummariesStream =
      widget.repository.watchNodeSummaries(widget.packId);

  /// 이미지 라이브러리는 팩과 무관하게 공유되지만(FIRESTORE_SCHEMA.md), 같은
  /// 이유로 build()에서 매번 새로 구독하지 않는다.
  late final Stream<List<AdminImage>> _imagesStream = widget.imageRepository.watchImages();

  String? _selectedNodeId;
  AdminStoryNode? _editingNode;
  bool _dirty = false;

  /// 사이드바에서 "+ 새 스토리 노드"로 만든 뒤, 아직 한 번도 저장하지 않은 상태인지.
  /// true인 동안만 노드 ID를 직접 입력할 수 있다(저장된 뒤에는 Firestore 문서
  /// id를 그 자리에서 바꿀 수 없으므로 잠근다).
  bool _isNewUnsaved = false;
  int _newNodeCounter = 0;
  bool _autoSelectAttempted = false;

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

  void _handleAddNode(List<AdminStoryNodeSummary> existing) {
    _newNodeCounter += 1;
    var candidateId = 'new_node_$_newNodeCounter';
    while (existing.any((n) => n.id == candidateId)) {
      _newNodeCounter += 1;
      candidateId = 'new_node_$_newNodeCounter';
    }

    // 새 노드는 기본적으로 맨 뒤에 이어 쓰는 경우가 대부분이라, 다음 순서로
    // 자동 배정한다 — 배경 이미지 인계가 바로 동작하게 하려는 것(0으로
    // 고정하면 항상 맨 앞으로 끼어들어 인계 규칙이 매번 어긋난다).
    final nextOrder = existing.isEmpty ? 0 : existing.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;

    final node = AdminStoryNode(id: candidateId, order: nextOrder);
    setState(() {
      _selectedNodeId = node.id;
      _editingNode = node;
      _dirty = false;
      _isNewUnsaved = true;
    });
  }

  Future<void> _handleDeleteNode(String nodeId, List<AdminStoryNodeSummary> summaries) async {
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
        final summaries = List<AdminStoryNodeSummary>.from(snapshot.data ?? const []);

        // 프로토타입(selectedIndex = 0)과 맞춰, 처음 목록이 들어오면 첫 노드를
        // 자동으로 선택한다 — 한 번만 시도해서 사용자가 명시적으로 선택 해제한
        // 뒤(예: 새 노드 삭제) 다시 자동 선택되지 않게 한다.
        if (!_autoSelectAttempted && _selectedNodeId == null && summaries.isNotEmpty) {
          _autoSelectAttempted = true;
          final firstId = summaries.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedNodeId == null) _selectNode(firstId);
          });
        }

        final editingNode = _editingNode;
        if (_isNewUnsaved && editingNode != null && !summaries.any((s) => s.id == editingNode.id)) {
          summaries.add(AdminStoryNodeSummary(
            id: editingNode.id,
            preview: editingNode.previewText,
            status: editingNode.status,
            pendingAction: editingNode.pendingAction,
            order: editingNode.order,
            backgroundImageId: editingNode.backgroundImageId,
          ));
        }

        final inheritedBackgroundImageId = editingNode == null
            ? null
            : resolveInheritedBackgroundImage(
                nodes: summaries.map((s) => (order: s.order, backgroundImage: s.backgroundImageId)),
                targetOrder: editingNode.order,
                packDefaultBackgroundImage: widget.pack.defaultBackgroundImage,
              );

        return Row(
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
            ),
            Expanded(
              child: editingNode == null
                  ? const Center(
                      child: Text('노드를 선택하거나 새로 만들어주세요.', style: TextStyle(color: AdminColors.muted)),
                    )
                  : StreamBuilder<List<AdminImage>>(
                      stream: _imagesStream,
                      builder: (context, imgSnapshot) {
                        final images = imgSnapshot.data ?? const <AdminImage>[];
                        return NodeEditor(
                          key: ValueKey(_selectedNodeId),
                          node: editingNode,
                          dirty: _dirty,
                          isIdEditable: _isNewUnsaved,
                          images: images,
                          packType: widget.pack.type,
                          inheritedBackgroundImageId: inheritedBackgroundImageId,
                          onChanged: () => setState(() => _dirty = true),
                          onSaveDraft: _handleSaveDraft,
                          onRequestApproval: _handleRequestApproval,
                          onCancelDeleteRequest: _handleCancelDeleteRequest,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

Future<bool> _confirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AdminColors.panel,
      content: Text(message, style: const TextStyle(color: AdminColors.ivory)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('취소', style: TextStyle(color: AdminColors.muted)),
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
    SnackBar(content: Text(message), backgroundColor: AdminColors.panel2, duration: const Duration(seconds: 2)),
  );
}
