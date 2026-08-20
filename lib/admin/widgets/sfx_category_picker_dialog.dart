import 'package:flutter/material.dart';

import '../models/admin_sfx_category.dart';
import 'admin_theme.dart';

/// CategoryPickerDialog(이미지용)와 같은 라디오 선택 다이얼로그 — 효과음
/// 업로드 시("카테고리 선택") / 카드에서 다시 고를 때("카테고리 변경") 둘 다
/// 쓴다. 취소하면 null.
class SfxCategoryPickerDialog extends StatefulWidget {
  final AdminSfxCategory initial;
  final String title;
  final String confirmLabel;

  const SfxCategoryPickerDialog({
    super.key,
    required this.initial,
    required this.title,
    required this.confirmLabel,
  });

  @override
  State<SfxCategoryPickerDialog> createState() =>
      _SfxCategoryPickerDialogState();
}

class _SfxCategoryPickerDialogState extends State<SfxCategoryPickerDialog> {
  late AdminSfxCategory _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(
        widget.title,
        style: TextStyle(color: AdminColors.ivory, fontSize: 15),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final category in AdminSfxCategory.values)
            RadioListTile<AdminSfxCategory>(
              value: category,
              groupValue: _selected,
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AdminColors.gold,
              title: Text(
                category.label,
                style: TextStyle(color: AdminColors.ivory, fontSize: 13),
              ),
              onChanged: (value) => setState(() => _selected = value!),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(
            widget.confirmLabel,
            style: TextStyle(
              color: AdminColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
