import 'package:flutter/material.dart';

import '../models/admin_story_node_summary.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';

/// 선택지/다음 노드가 가리킬 대상을 고르는 공용 위젯 — 노드 에디터의 선택지
/// 목록(choice_edit_form.dart 경유)과 스토리맵(story_map_view.dart)의 간선
/// 편집 팝오버 양쪽에서 재사용한다. id를 직접 타이핑하는 대신 각 후보 노드의
/// 첫 줄 미리보기로 찾게 해서, 작가가 노드 id를 외우고 있을 필요가 없다.
///
/// [candidates]는 반드시 저장된 노드 + 세션 캐시에 있는 초안까지 합친 목록
/// (story_tab_view.dart의 displaySummaries)이어야 한다 — suggestSequentialNodeIds와
/// 같은 "부분적으로만 섞인 목록을 넘기지 않는다"는 규칙을 그대로 따른다.
class ChoiceTargetPicker extends StatefulWidget {
  final String? selectedId;
  final List<AdminStoryNodeSummary> candidates;
  final ValueChanged<String> onSelected;

  /// 팝오버처럼 높이가 제한된 곳에서 쓸 때 목록에 최대 높이를 준다.
  final double maxListHeight;

  const ChoiceTargetPicker({
    super.key,
    required this.selectedId,
    required this.candidates,
    required this.onSelected,
    this.maxListHeight = 240,
  });

  @override
  State<ChoiceTargetPicker> createState() => _ChoiceTargetPickerState();
}

class _ChoiceTargetPickerState extends State<ChoiceTargetPicker> {
  final _filterController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _filter.trim().toLowerCase();
    final filtered = needle.isEmpty
        ? widget.candidates
        : widget.candidates
              .where(
                (c) =>
                    c.preview.toLowerCase().contains(needle) ||
                    c.id.toLowerCase().contains(needle),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.candidates.length > 6)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _filterController,
              style: TextStyle(color: AdminColors.inputText, fontSize: 12.5),
              decoration: adminInputDecoration(hintText: '노드 내용/ID로 검색')
                  .copyWith(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  ),
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
        Container(
          constraints: BoxConstraints(maxHeight: widget.maxListHeight),
          decoration: BoxDecoration(
            border: Border.all(color: AdminColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    widget.candidates.isEmpty
                        ? '이동할 수 있는 노드가 없어요.'
                        : '일치하는 노드가 없어요.',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(4),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final candidate = filtered[index];
                    final selected = candidate.id == widget.selectedId;
                    return InkWell(
                      onTap: () => widget.onSelected(candidate.id),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AdminColors.panel2
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: selected
                              ? Border.all(color: AdminColors.gold)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    candidate.preview.isEmpty
                                        ? '(내용 없음)'
                                        : candidate.preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AdminColors.ivory,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '노드 ${candidate.id} · ${candidate.shortLabel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AdminColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.link_rounded,
                              size: 15,
                              color: selected
                                  ? AdminColors.gold
                                  : AdminColors.muted,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
