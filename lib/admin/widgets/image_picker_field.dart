import 'package:flutter/material.dart';

import '../models/admin_image.dart';
import 'admin_theme.dart';

/// renderImagePicker() — 썸네일 + 드롭다운으로 업로드된 이미지 중 하나를 고른다.
class ImagePickerField extends StatelessWidget {
  final String? currentId;
  final List<AdminImage> images;
  final ValueChanged<String?> onChanged;

  const ImagePickerField({
    super.key,
    required this.currentId,
    required this.images,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = images.where((img) => img.id == currentId).firstOrNull;

    return Row(
      children: [
        Container(
          width: 54,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AdminColors.border),
            color: AdminColors.panel2,
          ),
          clipBehavior: Clip.antiAlias,
          child: selected == null
              ? null
              : Image.network(selected.url, fit: BoxFit.cover),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue:
                currentId != null && images.any((img) => img.id == currentId)
                ? currentId
                : null,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AdminColors.inputFill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AdminColors.inputBorder),
              ),
            ),
            dropdownColor: AdminColors.inputDropdownMenuBg,
            style: TextStyle(color: AdminColors.inputText, fontSize: 13),
            hint: Text(
              '(선택 안 함)',
              style: TextStyle(color: AdminColors.muted, fontSize: 13),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('(선택 안 함)'),
              ),
              ...images.map(
                (img) => DropdownMenuItem<String>(
                  value: img.id,
                  child: Text(img.name),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
        if (images.isEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '→ 이미지 라이브러리에서 먼저 업로드하세요',
              style: TextStyle(fontSize: 11, color: AdminColors.muted),
            ),
          ),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
