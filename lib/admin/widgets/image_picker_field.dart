import 'package:flutter/material.dart';

import '../models/admin_image.dart';
import '../models/admin_image_category.dart';
import 'admin_theme.dart';

/// renderImagePicker() — 썸네일 + 드롭다운으로 업로드된 이미지 중 하나를 고른다.
///
/// [filterCategory]를 주면 그 분류의 이미지만 드롭다운에 나열한다(라이브러리
/// 그리드의 필터 칩과 같은 카테고리 값을 쓴다) — 노드/팩 배경 이미지처럼
/// 항상 특정 분류에서 고르는 자리에서 쓴다. null이면(예: 표지 이미지 —
/// 배경/선택지 어느 쪽에도 딱 맞지 않는다) 전체 목록을 보여준다.
class ImagePickerField extends StatelessWidget {
  final String? currentId;
  final List<AdminImage> images;
  final ValueChanged<String?> onChanged;
  final AdminImageCategory? filterCategory;

  const ImagePickerField({
    super.key,
    required this.currentId,
    required this.images,
    required this.onChanged,
    this.filterCategory,
  });

  @override
  Widget build(BuildContext context) {
    final filterCategory = this.filterCategory;
    final visibleImages = filterCategory == null
        ? images
        : images.where((img) => img.category == filterCategory).toList();
    final selected = visibleImages
        .where((img) => img.id == currentId)
        .firstOrNull;

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
                currentId != null &&
                    visibleImages.any((img) => img.id == currentId)
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
              ...visibleImages.map(
                (img) => DropdownMenuItem<String>(
                  value: img.id,
                  child: Text(img.name),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
        if (visibleImages.isEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              filterCategory == null
                  ? '→ 이미지 라이브러리에서 먼저 업로드하세요'
                  : '→ 이미지 라이브러리에서 "${filterCategory.label}" 이미지를 먼저 업로드하세요',
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
