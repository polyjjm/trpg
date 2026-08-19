import 'package:flutter/material.dart';

import '../models/admin_node_choice.dart';
import '../models/admin_story_node_summary.dart';
import 'admin_theme.dart';
import 'choice_edit_form.dart';

/// "선택지" 섹션 — storyPack.type == 'interactive'인 노드에서만 보인다.
/// 선택지마다 라벨 + 이동할 노드를 [ChoiceEditForm](choice_edit_form.dart)으로
/// 편집한다 — 스토리맵의 간선 편집 팝오버와 같은 위젯을 그대로 재사용한다.
class NodeChoiceEditor extends StatelessWidget {
  final List<AdminNodeChoice> choices;

  /// 이동 대상 후보 — 저장된 노드 + 세션 캐시 초안을 합친 목록
  /// (story_tab_view.dart의 displaySummaries)을 그대로 받는다.
  final List<AdminStoryNodeSummary> candidates;
  final VoidCallback onChanged;

  const NodeChoiceEditor({
    super.key,
    required this.choices,
    required this.candidates,
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
                ChoiceEditForm(
                  label: choices[i].label,
                  nextNodeId: choices[i].nextNodeId.isEmpty
                      ? null
                      : choices[i].nextNodeId,
                  candidates: candidates,
                  onLabelChanged: (value) {
                    choices[i].label = value;
                    onChanged();
                  },
                  onTargetChanged: (id) {
                    choices[i].nextNodeId = id;
                    onChanged();
                  },
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
