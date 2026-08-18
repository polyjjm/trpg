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
        Text(label, style: TextStyle(fontSize: 12, color: AdminColors.muted)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// 편집기 전반에서 쓰는 텍스트 필드 스타일 — 라이트/다크에 따라 채움/테두리
/// 색이 바뀐다(AdminColors.inputFill/inputBorder, admin_theme.dart 참고).
InputDecoration adminInputDecoration({String? hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: AdminColors.muted, fontSize: 13),
    filled: true,
    fillColor: AdminColors.inputFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      borderSide: const BorderSide(color: AdminColors.gold, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AdminColors.inputDisabledBorder),
    ),
  );
}
