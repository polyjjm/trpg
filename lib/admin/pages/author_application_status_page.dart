import 'package:flutter/material.dart';

import '../models/author_application.dart';
import '../widgets/admin_theme.dart';

/// 신청서가 검토 대기 중일 때 보여주는 화면. 할 일이 없다는 게 이 화면의
/// 요점이라 로그아웃 말고는 아무 것도 누를 게 없다 — 가짜 진행률 표시도,
/// 반려처럼 보이는 경고색도 쓰지 않는다.
class AuthorApplicationStatusPage extends StatelessWidget {
  final AuthorApplication? application;
  final VoidCallback onSignOut;

  const AuthorApplicationStatusPage({super.key, required this.application, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final submittedAt = application?.submittedAt;

    return Scaffold(
      backgroundColor: AdminColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top_rounded, color: AdminColors.muted, size: 36),
                const SizedBox(height: 18),
                const Text(
                  '신청서를 검토 중이에요',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AdminColors.ivory),
                ),
                const SizedBox(height: 8),
                Text(
                  submittedAt == null
                      ? '검토가 끝나면 알려드릴게요.'
                      : '${_formatDate(submittedAt)}에 제출했어요.\n검토가 끝나면 알려드릴게요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AdminColors.muted, height: 1.5),
                ),
                const SizedBox(height: 28),
                InkWell(
                  onTap: onSignOut,
                  child: const Text('로그아웃', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) =>
    '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
