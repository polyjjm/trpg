import 'package:flutter/material.dart';

import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/admin_image.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/choice_type.dart';
import '../models/move_mode.dart';
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
  final AdminStoryRepository repository;
  final AdminImageRepository imageRepository;

  const StoryTabView({
    super.key,
    required this.packId,
    required this.repository,
    required this.imageRepository,
  });

  @override
  State<StoryTabView> createState() => _StoryTabViewState();
}

class _StoryTabViewState extends State<StoryTabView> {
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

    final node = AdminStoryNode(id: candidateId);
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

  String? _validate(AdminStoryNode node) {
    for (final choice in node.choices) {
      if (choice.type == ChoiceType.move && choice.mode == MoveMode.random) {
        final total = choice.random.fold<int>(0, (sum, r) => sum + r.pct);
        if (total != 100) {
          return '"${choice.text}" 선택지의 확률 합계가 $total%예요. 100%로 맞춰주세요.';
        }
      }
    }
    return null;
  }

  Future<void> _handleSaveDraft() async {
    final node = _editingNode;
    if (node == null) return;

    final error = _validate(node);
    if (error != null) {
      _showAlert(context, error);
      return;
    }

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

    final error = _validate(node);
    if (error != null) {
      _showAlert(context, error);
      return;
    }

    final isNew = node.isNew;
    final message = isNew
        ? '신규 등록 승인 요청을 보낼까요? 상위 관리자가 승인해야 플레이어에게 보여요.'
        : '수정 승인 요청을 보낼까요? 상위 관리자가 승인하기 전까지는 지금 연재 중인 이전 버전이 그대로 보여요.';
    final confirmed = await _confirm(context, message);
    if (!confirmed || !mounted) return;

    node.pendingAction = isNew ? PendingAction.create : PendingAction.edit;
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
      stream: widget.repository.watchNodeSummaries(widget.packId),
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
            title: editingNode.title,
            status: editingNode.status,
            pendingAction: editingNode.pendingAction,
          ));
        }

        final nodeOptions = summaries.where((s) => s.id != _selectedNodeId).toList();

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
                      stream: widget.imageRepository.watchImages(),
                      builder: (context, imgSnapshot) {
                        final images = imgSnapshot.data ?? const <AdminImage>[];
                        return NodeEditor(
                          key: ValueKey(_selectedNodeId),
                          node: editingNode,
                          dirty: _dirty,
                          isIdEditable: _isNewUnsaved,
                          images: images,
                          nodeOptions: nodeOptions,
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

void _showAlert(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AdminColors.panel,
      content: Text(message, style: const TextStyle(color: AdminColors.ivory)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('확인', style: TextStyle(color: AdminColors.gold)),
        ),
      ],
    ),
  );
}

void _showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AdminColors.panel2, duration: const Duration(seconds: 2)),
  );
}
