import 'package:flutter/material.dart';

import 'admin_theme.dart';
import 'labeled_field.dart';

/// "본문" 섹션 — 문단을 빈 줄로 구분해 한 번에 입력하는 단일 텍스트 필드.
/// 저장(임시저장/승인요청) 시점에 AdminStoryNode.applyBodyTextToBlocks가
/// 빈 줄 기준으로 잘라 paragraph 블록 배열로 바꾼다 — Firestore에 저장되는
/// blocks 구조 자체는 그대로고, 입력 UX만 "+ 문단 추가" 클릭 방식에서
/// 자연스러운 줄바꿈 타이핑으로 바뀐 것이다.
class NodeBodyEditor extends StatelessWidget {
  final String bodyText;
  final ValueChanged<String> onChanged;

  const NodeBodyEditor({
    super.key,
    required this.bodyText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: '본문 (문단 사이에 빈 줄을 하나 넣어 구분하세요 — 저장할 때 문단별로 나뉘어요)',
      child: TextFormField(
        initialValue: bodyText,
        minLines: 14,
        maxLines: 28,
        style: TextStyle(
          color: AdminColors.inputText,
          fontSize: 13,
          height: 1.6,
        ),
        decoration: adminInputDecoration(
          hintText: '문단을 입력하세요. 다음 문단은 빈 줄(엔터 두 번)로 구분해요.',
        ),
        onChanged: onChanged,
      ),
    );
  }
}
