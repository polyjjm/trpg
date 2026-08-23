import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/admin_story_node_summary.dart';
import '../models/pack_submit_state.dart';
import 'admin_theme.dart';
import 'status_tag.dart';

/// sidebar — "+ 새 스토리 노드" 버튼 + 검색 + 드래그로 순서를 바꿀 수 있는
/// 노드 목록(순번 + 상태 배지).
///
/// 예전과 달라진 세 가지:
///
/// - **"변경사항 전체 승인요청" 버튼이 없다.** 팩 단위 액션인데 노드 목록
///   안에 있어서 묻혔다 — 상단 바로 올라갔다(author_tool_page.dart). 개수와
///   콜백은 여전히 [unsubmittedCount]/[onSubmitAllChanges]로 이 위젯에
///   들어오는데(story_tab_view.dart가 계산한다), 그 값을 전역
///   [packSubmitState]에 실어 상단 바로 흘려보낸다 — 호출부를 고치지 않고
///   버튼만 위로 옮기기 위한 통로다.
/// - **체크박스가 상시 노출되지 않는다.** 일괄 삭제는 드물게 쓰는 기능인데
///   모든 행 왼쪽을 체크박스가 차지하고 있었다. "선택"을 눌러 선택 모드로
///   들어갔을 때만 체크박스와 삭제 툴바가 나타난다.
/// - **검색과 순번이 있다.** 노드가 열 개만 넘어가도 본문 미리보기만으로는
///   찾기 어렵고, 순번이 없으면 지금 몇 번째를 보고 있는지 알 수 없었다.
///
/// 삭제 아이콘은 행에 마우스를 올렸을 때만 보인다 — 예전엔 모든 행에 빨간
/// 휴지통이 상시 노출돼서, 목록을 훑는 동안 시선을 계속 끌어당겼다.
class StoryNodeSidebar extends StatefulWidget {
  final List<AdminStoryNodeSummary> nodes;
  final String? selectedNodeId;

  /// 세션 캐시(node_edit_session_cache.dart)에 편집 내용이 있고, 그 내용이
  /// 실제로 라이브 버전과 다른 노드 id — 선택 여부와 무관하게 목록의 모든
  /// 노드에 "수정됨" 배지를 보여주는 데 쓴다.
  final Set<String> unsavedNodeIds;

  final VoidCallback onAddNode;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  /// 드래그로 노드 순서를 바꿨을 때 — ReorderableListView 관례 그대로
  /// (oldIndex, newIndex)를 넘긴다. story_tab_view.dart가 order 값을 다시
  /// 매겨 세션 캐시에 반영한다(즉시 Firestore에 쓰지 않는다).
  final void Function(int oldIndex, int newIndex) onReorder;

  /// 이 팩의 미제출 변경사항 수와 그 제출 콜백 — 버튼은 상단 바에 있지만
  /// 계산은 여전히 story_tab_view.dart가 한다. 여기서 [packSubmitState]에
  /// 실어 보낸다.
  final int unsubmittedCount;
  final VoidCallback? onSubmitAllChanges;

  /// 일괄 삭제 선택 상태 — story_tab_view.dart의 State가 들고 있는다.
  final Set<String> bulkSelectedIds;
  final ValueChanged<String> onToggleBulkSelect;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onBulkDelete;

  const StoryNodeSidebar({
    super.key,
    required this.nodes,
    required this.selectedNodeId,
    required this.unsavedNodeIds,
    required this.onAddNode,
    required this.onSelect,
    required this.onDelete,
    required this.onReorder,
    this.unsubmittedCount = 0,
    this.onSubmitAllChanges,
    required this.bulkSelectedIds,
    required this.onToggleBulkSelect,
    required this.onToggleSelectAll,
    required this.onBulkDelete,
  });

  @override
  State<StoryNodeSidebar> createState() => _StoryNodeSidebarState();
}

class _StoryNodeSidebarState extends State<StoryNodeSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// 선택 모드(일괄 삭제)에 들어와 있는지 — 이 안에서만 체크박스가 보인다.
  bool _selectMode = false;

  @override
  void initState() {
    super.initState();
    _publishSubmitState();
  }

  @override
  void didUpdateWidget(covariant StoryNodeSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unsubmittedCount != widget.unsubmittedCount ||
        oldWidget.onSubmitAllChanges != widget.onSubmitAllChanges) {
      _publishSubmitState();
    }
  }

  @override
  void dispose() {
    // 팩을 바꾸면 이 위젯이 통째로 새로 만들어진다 — 이전 팩의 개수가 상단
    // 바에 남아 있지 않게 비운다.
    packSubmitState.value = null;
    _searchController.dispose();
    super.dispose();
  }

  /// 상단 바 버튼이 읽는 값을 채운다.
  ///
  /// build() 안에서 직접 쓰면 "빌드 도중 다른 위젯을 다시 빌드시키는" 오류가
  /// 나므로(상단 바의 ValueListenableBuilder가 그 즉시 rebuild된다) 프레임이
  /// 끝난 뒤로 미룬다.
  void _publishSubmitState() {
    final onSubmit = widget.onSubmitAllChanges;
    final count = widget.unsubmittedCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      packSubmitState.value = (onSubmit == null || count == 0)
          ? null
          : PackSubmitState(unsubmittedCount: count, onSubmitAll: onSubmit);
    });
  }

  void _exitSelectMode() {
    setState(() => _selectMode = false);
    // 선택은 story_tab_view.dart가 들고 있으니, 남아 있던 선택을 비운다 —
    // 안 그러면 선택 모드를 나갔는데도 "삭제 N"이 살아있는 상태가 된다.
    if (widget.bulkSelectedIds.isNotEmpty) widget.onToggleSelectAll();
  }

  /// 검색어에 걸리는 노드만 — 본문 미리보기와 노드 id 둘 다 본다.
  List<AdminStoryNodeSummary> get _visibleNodes {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.nodes;
    return widget.nodes
        .where(
          (n) =>
      n.preview.toLowerCase().contains(query) ||
          n.id.toLowerCase().contains(query),
    )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.nodes;
    final visible = _visibleNodes;
    final searching = _query.trim().isNotEmpty;
    final allSelected =
        nodes.isNotEmpty && widget.bulkSelectedIds.length == nodes.length;

    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border(right: BorderSide(color: AdminColors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onAddNode,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      '새 스토리 노드',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.coralSoftBg,
                      foregroundColor: AdminColors.coralSoftText,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _SearchField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                ),
              ],
            ),
          ),
          _ListHeader(
            total: nodes.length,
            matched: searching ? visible.length : null,
            selectMode: _selectMode,
            onEnterSelectMode: nodes.isEmpty
                ? null
                : () => setState(() => _selectMode = true),
            onExitSelectMode: _exitSelectMode,
          ),
          if (_selectMode)
            _BulkToolbar(
              allSelected: allSelected,
              selectedCount: widget.bulkSelectedIds.length,
              onToggleSelectAll: nodes.isEmpty
                  ? null
                  : widget.onToggleSelectAll,
              onBulkDelete: widget.bulkSelectedIds.isEmpty
                  ? null
                  : widget.onBulkDelete,
            ),
          Expanded(
            child: visible.isEmpty
                ? _EmptyState(searching: searching)
                : _buildList(visible, searching),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<AdminStoryNodeSummary> visible, bool searching) {
    // 검색 중에는 드래그 순서 변경을 막는다 — 화면에 보이는 인덱스와 실제
    // 목록의 인덱스가 달라서, 그대로 onReorder에 넘기면 엉뚱한 노드가
    // 움직인다. 순서를 바꾸려면 검색을 비우면 된다.
    if (searching) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        itemCount: visible.length,
        itemBuilder: (context, i) => _buildItem(visible[i], null),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      onReorder: widget.onReorder,
      // 기본값 true면 우리가 직접 넣은 드래그 핸들 말고도 Flutter가 각 항목
      // 끝에 자기 기본 핸들을 하나 더 겹쳐 그린다 — 삭제 아이콘 아래에 뜬
      // 정체불명의 "≡"가 그 기본 핸들이었다(실제로 겪은 버그).
      buildDefaultDragHandles: false,
      itemCount: visible.length,
      itemBuilder: (context, i) => _buildItem(visible[i], i),
    );
  }

  /// [dragIndex]가 null이면 드래그 핸들을 그리지 않는다(검색 중).
  Widget _buildItem(AdminStoryNodeSummary node, int? dragIndex) {
    // 순번은 검색 여부와 무관하게 "전체 목록에서 몇 번째인지"를 보여준다 —
    // 검색 결과 안에서의 1, 2, 3은 아무 의미가 없다.
    final orderIndex = widget.nodes.indexWhere((n) => n.id == node.id);

    return _NodeItem(
      key: ValueKey(node.id),
      index: orderIndex >= 0 ? orderIndex + 1 : 0,
      dragIndex: dragIndex,
      node: node,
      active: node.id == widget.selectedNodeId,
      hasUnsavedEdits: widget.unsavedNodeIds.contains(node.id),
      selectMode: _selectMode,
      checked: widget.bulkSelectedIds.contains(node.id),
      onTap: () => widget.onSelect(node.id),
      onDelete: () => widget.onDelete(node.id),
      onToggleChecked: () => widget.onToggleBulkSelect(node.id),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 12.5, color: AdminColors.inputText),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AdminColors.inputFill,
          hintText: '본문·노드 id 검색',
          hintStyle: TextStyle(fontSize: 12.5, color: AdminColors.muted),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 17,
            color: AdminColors.muted,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 9,
            horizontal: 4,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AdminColors.inputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AdminColors.inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AdminColors.gold),
          ),
        ),
      ),
    );
  }
}

/// "노드 8" + "선택"/"완료" — 목록과 툴바 사이의 얇은 줄.
class _ListHeader extends StatelessWidget {
  final int total;

  /// 검색 중일 때만 값이 있다 — "3 / 8"처럼 걸린 개수를 함께 보여준다.
  final int? matched;

  final bool selectMode;
  final VoidCallback? onEnterSelectMode;
  final VoidCallback onExitSelectMode;

  const _ListHeader({
    required this.total,
    required this.matched,
    required this.selectMode,
    required this.onEnterSelectMode,
    required this.onExitSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    final matched = this.matched;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
              children: [
                const TextSpan(text: '노드 '),
                TextSpan(
                  text: matched == null ? '$total' : '$matched',
                  style: TextStyle(
                    color: AdminColors.ivory,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (matched != null) TextSpan(text: ' / $total'),
              ],
            ),
          ),
          const Spacer(),
          if (selectMode)
            InkWell(
              onTap: onExitSelectMode,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '완료',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.gold,
                  ),
                ),
              ),
            )
          else
            InkWell(
              onTap: onEnterSelectMode,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                child: Text(
                  '선택',
                  style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 선택 모드에서만 보이는 툴바 — 전체 선택 + "삭제 N".
class _BulkToolbar extends StatelessWidget {
  final bool allSelected;
  final int selectedCount;
  final VoidCallback? onToggleSelectAll;
  final VoidCallback? onBulkDelete;

  const _BulkToolbar({
    required this.allSelected,
    required this.selectedCount,
    required this.onToggleSelectAll,
    required this.onBulkDelete,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onBulkDelete != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: allSelected,
              fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                    ? AdminColors.gold
                    : AdminColors.checkboxUncheckedFill,
              ),
              checkColor: AdminColors.checkboxCheckColor,
              side: BorderSide(
                color: AdminColors.checkboxUncheckedBorder,
                width: 1.5,
              ),
              onChanged: onToggleSelectAll == null
                  ? null
                  : (_) => onToggleSelectAll!(),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '전체 선택',
            style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
          ),
          const Spacer(),
          InkWell(
            onTap: onBulkDelete,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: enabled ? AdminColors.rejectBg : AdminColors.panel2,
                border: Border.all(
                  color: enabled
                      ? AdminColors.rejectBorder
                      : AdminColors.border,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '삭제 $selectedCount',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: enabled ? AdminColors.rejectText : AdminColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;

  const _EmptyState({required this.searching});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        searching ? '검색 결과가 없어요.' : '아직 노드가 없어요.',
        style: TextStyle(fontSize: 12, color: AdminColors.muted),
      ),
    );
  }
}

class _NodeItem extends StatefulWidget {
  /// 전체 목록에서 몇 번째인지(1부터).
  final int index;

  /// ReorderableDragStartListener에 넘길 인덱스 — null이면 핸들을 안 그린다.
  final int? dragIndex;

  final AdminStoryNodeSummary node;
  final bool active;
  final bool hasUnsavedEdits;
  final bool selectMode;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleChecked;

  const _NodeItem({
    required super.key,
    required this.index,
    required this.dragIndex,
    required this.node,
    required this.active,
    required this.hasUnsavedEdits,
    required this.selectMode,
    required this.checked,
    required this.onTap,
    required this.onDelete,
    required this.onToggleChecked,
  });

  @override
  State<_NodeItem> createState() => _NodeItemState();
}

class _NodeItemState extends State<_NodeItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final active = widget.active;
    final dragIndex = widget.dragIndex;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.selectMode ? widget.onToggleChecked : widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? AdminColors.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? AdminColors.gold
                  : (_hovering ? AdminColors.border : Colors.transparent),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.selectMode)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: widget.checked,
                    fillColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                          ? AdminColors.gold
                          : AdminColors.checkboxUncheckedFill,
                    ),
                    checkColor: AdminColors.checkboxCheckColor,
                    side: BorderSide(
                      color: AdminColors.checkboxUncheckedBorder,
                      width: 1.5,
                    ),
                    onChanged: (_) => widget.onToggleChecked(),
                  ),
                )
              else
                SizedBox(
                  width: 22,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '${widget.index}'.padLeft(2, '0'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: active
                            ? AdminColors.gold
                            : AdminColors.inputDisabledBorder,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.preview.isEmpty ? '(내용 없음)' : node.preview,
                        style: TextStyle(
                          fontSize: 13,
                          color: active
                              ? AdminColors.ivory
                              : AdminColors.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          StatusTag(
                            status: node.status,
                            pendingAction: node.pendingAction,
                            rejectionReason: node.rejectionReason,
                          ),
                          if (widget.hasUnsavedEdits) ...[
                            const SizedBox(width: 4),
                            const _UnsavedBadge(),
                          ],
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              node.id,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AdminColors.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 드래그 핸들과 삭제는 마우스를 올렸을 때만 — 목록을 훑는 동안
              // 빨간 휴지통이 시선을 끌지 않게 한다. 선택 모드에서는 삭제가
              // 툴바로 가므로 둘 다 숨긴다.
              if (!widget.selectMode && _hovering) ...[
                const SizedBox(width: 2),
                if (dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 17,
                        color: AdminColors.muted,
                      ),
                    ),
                  ),
                InkWell(
                  onTap: widget.onDelete,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: AdminColors.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// StatusTag 옆에 붙는 작은 표시 — 실제 발행 상태(초안/연재중/승인대기)와는
/// 별개로, 이 노드에 세션 캐시(브라우저 탭 한정, Firestore에 아직 안 반영된)
/// 편집 내용이 있음을 알려준다.
class _UnsavedBadge extends StatelessWidget {
  const _UnsavedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AdminColors.gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AdminColors.gold.withOpacity(0.55)),
      ),
      child: const Text(
        '수정됨',
        style: TextStyle(
          fontSize: 9.5,
          color: AdminColors.gold,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
