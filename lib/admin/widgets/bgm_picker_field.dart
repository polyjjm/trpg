import 'package:flutter/material.dart';

import '../../core/audio/audio_service.dart';
import '../models/admin_bgm.dart';
import 'admin_theme.dart';

/// SfxPickerField와 같은 "미리듣기 버튼 + 드롭다운" 골격이지만, BGM
/// 라이브러리는 카테고리가 없어서(admin_bgm.dart 참고) 필터 칩이 없다 —
/// 그만큼 더 단순하다. 노드 연출 효과의 "배경음악" 트랙 선택과 팩 설정의
/// "기본 배경음악" 둘 다 이 위젯을 쓴다.
class BgmPickerField extends StatelessWidget {
  final String? currentId;
  final List<AdminBgm> bgmLibrary;
  final ValueChanged<String?> onChanged;

  const BgmPickerField({
    super.key,
    required this.currentId,
    required this.bgmLibrary,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = bgmLibrary.where((b) => b.id == currentId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    currentId != null &&
                        bgmLibrary.any((b) => b.id == currentId)
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
                  ...bgmLibrary.map(
                    (b) => DropdownMenuItem<String>(
                      value: b.id,
                      child: Text(b.name),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        if (bgmLibrary.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '→ 배경음악 라이브러리에서 먼저 업로드하세요',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
