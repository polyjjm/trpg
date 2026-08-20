import 'package:flutter/material.dart';

import '../../core/audio/audio_service.dart';
import '../models/admin_sfx.dart';
import '../models/admin_sfx_category.dart';
import 'admin_theme.dart';

/// ImagePickerField와 같은 "썸네일 자리 + 드롭다운" 골격이지만, 효과음에는
/// 보여줄 그림이 없다 — 그 자리에 고른 효과음을 바로 들어볼 수 있는 재생
/// 버튼을 놓는다.
///
/// ImagePickerField는 쓰이는 자리(배경 이미지 필드)가 항상 정해진 한 카테고리
/// (배경)로 고정돼 있어서 `filterCategory` 하나를 부모가 넘겨주면 끝이지만,
/// 노드 연출 효과의 "효과음"은 어떤 카테고리든(문/발소리/비명/심장박동/기타)
/// 고를 수 있는 자리다 — 그래서 이 위젯은 카테고리를 미리 정해서 받는 대신,
/// 필터 칩을 직접 들고 있는 StatefulWidget으로 만들어 작가가 그 자리에서
/// 후보를 좁혀가며 고르게 한다.
class SfxPickerField extends StatefulWidget {
  final String? currentId;
  final List<AdminSfx> sfxLibrary;
  final ValueChanged<String?> onChanged;

  const SfxPickerField({
    super.key,
    required this.currentId,
    required this.sfxLibrary,
    required this.onChanged,
  });

  @override
  State<SfxPickerField> createState() => _SfxPickerFieldState();
}

class _SfxPickerFieldState extends State<SfxPickerField> {
  /// null이면 "전체".
  AdminSfxCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final visibleSfx = filter == null
        ? widget.sfxLibrary
        : widget.sfxLibrary.where((s) => s.category == filter).toList();
    final selected = widget.sfxLibrary
        .where((s) => s.id == widget.currentId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _CategoryChip(
              label: '전체',
              selected: filter == null,
              onTap: () => setState(() => _filter = null),
            ),
            for (final category in AdminSfxCategory.values)
              _CategoryChip(
                label: category.label,
                selected: filter == category,
                onTap: () => setState(() => _filter = category),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AdminColors.border),
                color: AdminColors.panel2,
              ),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 20,
                onPressed: selected == null
                    ? null
                    : () => AudioService.instance.playSfx(selected.storageUrl),
                icon: Icon(
                  Icons.play_circle_fill_rounded,
                  color: selected == null
                      ? AdminColors.muted
                      : AdminColors.gold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue:
                    widget.currentId != null &&
                        visibleSfx.any((s) => s.id == widget.currentId)
                    ? widget.currentId
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
                  ...visibleSfx.map(
                    (s) => DropdownMenuItem<String>(
                      value: s.id,
                      child: Text(s.name),
                    ),
                  ),
                ],
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
        if (visibleSfx.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            filter == null
                ? '→ 효과음 라이브러리에서 먼저 업로드하세요'
                : '→ 효과음 라이브러리에서 "${filter.label}" 효과음을 먼저 업로드하세요',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : AdminColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
