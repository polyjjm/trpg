import 'package:flutter/material.dart';

import '../models/admin_node_block.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';

/// "본문" 섹션 — 블록마다 따로 자라나는(auto-grow) 텍스트 필드 하나씩,
/// 세로로 쌓아 보여준다. 예전엔 문단 사이에 빈 줄을 넣어 구분하는 텍스트
/// 필드 하나(NodeBodyEditor, bodyText → applyBodyTextToBlocks)였는데,
/// "글쓰기에 더 가깝게" 만들기 위해 Firestore에 실제로 저장되는 blocks
/// 배열을 편집 중에도 그대로 직접 건드리는 방식으로 되돌렸다 — 저장 시점에
/// 따로 나눌 필요가 없다.
class NodeBodyBlocksEditor extends StatelessWidget {
  final List<AdminNodeBlock> blocks;
  final VoidCallback onChanged;

  const NodeBodyBlocksEditor({
    super.key,
    required this.blocks,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BlockField(
              key: ObjectKey(blocks[i]),
              block: blocks[i],
              onChanged: onChanged,
              onDelete: blocks.length <= 1
                  ? null
                  : () {
                      blocks.removeAt(i);
                      onChanged();
                    },
            ),
          ),
        TextButton.icon(
          onPressed: () {
            blocks.add(AdminNodeBlock());
            onChanged();
          },
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('문단 추가', style: TextStyle(fontSize: 12.5)),
          style: TextButton.styleFrom(foregroundColor: AdminColors.gold),
        ),
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              '아직 문단이 없어요. "문단 추가"로 시작하세요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
          ),
      ],
    );
  }
}

/// 블록 하나 — hover/focus 중일 때만 우측 상단에 삭제 아이콘이 뜬다.
class _BlockField extends StatefulWidget {
  final AdminNodeBlock block;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  const _BlockField({
    required super.key,
    required this.block,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_BlockField> createState() => _BlockFieldState();
}

class _BlockFieldState extends State<_BlockField> {
  final _focusNode = FocusNode();
  bool _hovering = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showDelete = widget.onDelete != null && (_hovering || _focused);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        children: [
          TextFormField(
            focusNode: _focusNode,
            initialValue: widget.block.text,
            minLines: 2,
            maxLines: null,
            style: TextStyle(
              color: AdminColors.inputText,
              fontSize: 13.5,
              height: 1.6,
            ),
            decoration: adminInputDecoration(hintText: '문단을 입력하세요.').copyWith(
              contentPadding: const EdgeInsets.fromLTRB(10, 10, 34, 10),
            ),
            onChanged: (value) {
              widget.block.text = value;
              widget.onChanged();
            },
          ),
          if (showDelete)
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: widget.onDelete,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AdminColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
