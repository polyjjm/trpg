import 'package:flutter/material.dart';

import 'admin_theme.dart';

/// 확인/취소 다이얼로그 — story_tab_view.dart(노드 전환/새 노드/일괄 작업)와
/// author_tool_page.dart(팩 전환/탭 전환 시 저장 안 한 변경사항 확인)가
/// 공유한다. 취소하거나 다이얼로그 밖을 눌러 닫으면 false.
Future<bool> showConfirmDialog(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AdminColors.panel,
      content: Text(message, style: TextStyle(color: AdminColors.ivory)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('확인', style: TextStyle(color: AdminColors.gold)),
        ),
      ],
    ),
  );
  return result ?? false;
}
