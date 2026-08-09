import 'package:flutter/material.dart';

import '../models/admin_story_node_summary.dart';
import 'admin_theme.dart';

/// 같은 스토리팩 안의 다른 노드 중 하나를 고르는 드롭다운.
/// 선택지의 target/winNode/loseNode/escapeNode 등에서 공용으로 쓴다.
class NodeDropdown extends StatelessWidget {
  final String currentId;
  final List<AdminStoryNodeSummary> options;
  final ValueChanged<String> onChanged;

  const NodeDropdown({
    super.key,
    required this.currentId,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final validValue = options.any((o) => o.id == currentId) ? currentId : null;

    return DropdownButtonFormField<String>(
      initialValue: validValue,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AdminColors.panel2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
      ),
      dropdownColor: AdminColors.panel2,
      style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
      hint: const Text('(선택)', style: TextStyle(color: AdminColors.muted, fontSize: 13)),
      items: options
          .map((o) => DropdownMenuItem<String>(
                value: o.id,
                child: Text('${o.title} (${o.id})', overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) => onChanged(value ?? ''),
    );
  }
}
