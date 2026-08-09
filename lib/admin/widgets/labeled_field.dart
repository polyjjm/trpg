import 'package:flutter/material.dart';

import 'admin_theme.dart';

/// `.field-group` — 위에 작은 회색 라벨, 아래 입력 위젯.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const LabeledField({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AdminColors.muted),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// 편집기 전반에서 쓰는 다크 테마 텍스트 필드 스타일.
InputDecoration adminInputDecoration({String? hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: AdminColors.muted, fontSize: 13),
    filled: true,
    fillColor: AdminColors.panel2,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AdminColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AdminColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AdminColors.gold),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AdminColors.border.withOpacity(0.5)),
    ),
  );
}
