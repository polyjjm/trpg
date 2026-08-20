import 'package:flutter/material.dart';

import 'admin_theme.dart';

/// 이미지/효과음 라이브러리 탭이 공유하는 이름 검색창 — 카테고리 필터 칩
/// 위(또는 아래)에 놓고, 타이핑할 때마다 [onChanged]로 검색어를 올려보낸다.
/// 실제 필터링(카테고리 AND 이름 부분 일치)은 각 탭이 들고 있는 리스트에
/// 그대로 client-side로 적용한다 — 이 위젯은 입력 UI만 맡는다.
///
/// X(지우기) 버튼은 [controller]를 직접 구독해서(ValueListenableBuilder) 텍스트가
/// 있을 때만 보인다 — 부모가 "검색어가 비어 있는지"를 따로 넘겨줄 필요가 없다.
class LibrarySearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const LibrarySearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          style: TextStyle(color: AdminColors.inputText, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AdminColors.inputFill,
            hintText: hintText,
            hintStyle: TextStyle(color: AdminColors.muted, fontSize: 13),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: AdminColors.muted,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AdminColors.muted,
                    ),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 9,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AdminColors.inputBorder),
            ),
          ),
          onChanged: onChanged,
        );
      },
    );
  }
}
