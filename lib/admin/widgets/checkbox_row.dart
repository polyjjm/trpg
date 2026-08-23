import 'package:flutter/material.dart';

import 'admin_theme.dart';

/// 체크박스 + 라벨 한 줄 — node_editor.dart의 배경 인계 체크박스와 같은
/// 스타일(AdminColors 체크박스 3종)을 라벨을 붙인 재사용 가능한 형태로
/// 뽑아 둔 것. author_management_section.dart의 자격 회수 다이얼로그와
/// account_disable_dialog.dart의 계정 정지 다이얼로그가 함께 쓴다 — 둘 다
/// "이 작가의 작품도 함께 비공개 처리" 체크박스가 필요해서 원래 한 파일
/// 안에 있던 private 위젯을 공용으로 옮겼다.
class CheckboxRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const CheckboxRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
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
            onChanged: (checked) => onChanged(checked ?? true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: AdminColors.ivory),
          ),
        ),
      ],
    );
  }
}
