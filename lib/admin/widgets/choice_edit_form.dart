import 'package:flutter/material.dart';

import '../models/admin_story_node_summary.dart';
import 'admin_theme.dart';
import 'choice_target_picker.dart';
import 'labeled_field.dart';

/// 자주 쓰는 선택지 문구 — 그냥 고정 const 목록이다. Firestore로 관리되는
/// 프리셋이 아니다 — 나중에 관리자가 직접 편집할 수 있게 만들 후보이긴
/// 하지만, 지금 당장 그렇게까지 만들 필요는 없다고 판단해 보류한다.
const List<String> kChoiceTemplateChips = ['다시 시도', '돌아가기', '계속하기', '주변을 살핀다'];

/// 선택지 하나(라벨 + 이동 대상)를 편집하는 공용 폼 — 노드 에디터의 선택지
/// 목록(node_choice_editor.dart)과 스토리맵 간선 편집 팝오버
/// (story_map_view.dart) 양쪽에서 그대로 재사용한다. 두 자리에서 서로 다른
/// UI를 만들면 "선택지를 고치는 방법이 두 가지"가 되어버리는 걸 피하려고
/// 여기 하나로 합쳤다.
class ChoiceEditForm extends StatefulWidget {
  final String label;
  final String? nextNodeId;
  final List<AdminStoryNodeSummary> candidates;
  final ValueChanged<String> onLabelChanged;
  final ValueChanged<String> onTargetChanged;

  /// 스토리맵에서 방금 만든 간선을 열 때 — 대상은 이미 드래그로 정해졌으니
  /// 커서를 라벨 입력칸에 바로 두고, 대상 선택기는 접어 둔다.
  final bool autofocusLabel;

  /// 대상 선택기를 처음부터 펼쳐서 보여줄지. 노드 에디터의 선택지 목록에서는
  /// 항상 펼쳐 두는 쪽이 자연스럽고, 스토리맵 팝오버에서는 접어 두는 쪽이
  /// 자연스러워서 호출부가 고른다.
  final bool initiallyExpandTarget;

  const ChoiceEditForm({
    super.key,
    required this.label,
    required this.nextNodeId,
    required this.candidates,
    required this.onLabelChanged,
    required this.onTargetChanged,
    this.autofocusLabel = false,
    this.initiallyExpandTarget = true,
  });

  @override
  State<ChoiceEditForm> createState() => _ChoiceEditFormState();
}

class _ChoiceEditFormState extends State<ChoiceEditForm> {
  late final TextEditingController _labelController = TextEditingController(
    text: widget.label,
  );
  late bool _pickerExpanded = widget.initiallyExpandTarget;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.nextNodeId;
    final targetSummary = target == null
        ? null
        : widget.candidates.where((c) => c.id == target).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final chip in kChoiceTemplateChips)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  _labelController.text = chip;
                  widget.onLabelChanged(chip);
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
                    style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _labelController,
          autofocus: widget.autofocusLabel,
          style: TextStyle(color: AdminColors.inputText, fontSize: 13),
          decoration: adminInputDecoration(hintText: '버튼에 표시될 텍스트'),
          onChanged: widget.onLabelChanged,
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => setState(() => _pickerExpanded = !_pickerExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AdminColors.panel2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AdminColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 14, color: AdminColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    targetSummary != null
                        ? (targetSummary.preview.isEmpty
                              ? '(내용 없음)'
                              : targetSummary.preview)
                        : (target == null || target.isEmpty
                              ? '이동할 노드를 고르세요'
                              : '$target (찾을 수 없음)'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: targetSummary == null
                          ? AdminColors.muted
                          : AdminColors.ivory,
                    ),
                  ),
                ),
                Icon(
                  _pickerExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AdminColors.muted,
                ),
              ],
            ),
          ),
        ),
        if (_pickerExpanded) ...[
          const SizedBox(height: 8),
          ChoiceTargetPicker(
            selectedId: widget.nextNodeId,
            candidates: widget.candidates,
            onSelected: widget.onTargetChanged,
          ),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
