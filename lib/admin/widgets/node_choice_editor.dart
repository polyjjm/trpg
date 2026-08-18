import 'package:flutter/material.dart';

import '../models/admin_node_choice.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';

/// "선택지" 섹션 — storyPack.type == 'interactive'인 노드에서만 보인다.
/// 선택지마다 라벨 텍스트 + 이동할 노드 id를 직접 입력하는 텍스트 필드뿐이다
/// — 노드 선택 드롭다운은 이번 패스에서 다루지 않는다(수동 입력으로 충분).
class NodeChoiceEditor extends StatelessWidget {
  final List<AdminNodeChoice> choices;
  final VoidCallback onChanged;

  const NodeChoiceEditor({
    super.key,
    required this.choices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '선택지',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AdminColors.ivory,
              ),
            ),
            TextButton(
              onPressed: () {
                choices.add(AdminNodeChoice());
                onChanged();
              },
              style: TextButton.styleFrom(
                foregroundColor: AdminColors.gold,
                backgroundColor: AdminColors.panel2,
                side: BorderSide(
                  color: AdminColors.border,
                  style: BorderStyle.solid,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: const Text('+ 선택지 추가', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < choices.length; i++)
          Container(
            key: ObjectKey(choices[i]),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AdminColors.panel,
              border: Border.all(color: AdminColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '선택지 ${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AdminColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        choices.removeAt(i);
                        onChanged();
                      },
                      child: const Text(
                        '삭제',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LabeledField(
                  label: '버튼에 표시될 텍스트',
                  child: TextFormField(
                    initialValue: choices[i].label,
                    style: TextStyle(
                      color: AdminColors.inputText,
                      fontSize: 13,
                    ),
                    decoration: adminInputDecoration(),
                    onChanged: (value) {
                      choices[i].label = value;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                LabeledField(
                  label: '이동할 노드 ID',
                  child: TextFormField(
                    initialValue: choices[i].nextNodeId,
                    style: TextStyle(
                      color: AdminColors.inputText,
                      fontSize: 13,
                    ),
                    decoration: adminInputDecoration(hintText: '예: node_02'),
                    onChanged: (value) {
                      choices[i].nextNodeId = value;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
        if (choices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '선택지가 없어요. "+ 선택지 추가"로 시작하세요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
          ),
      ],
    );
  }
}
