import 'package:flutter/material.dart';

import '../../core/auth/google_auth_service.dart';
import '../widgets/admin_theme.dart';
import 'admin_gate_page.dart';

/// Firebase 로그인은 성공했지만 이메일이 화이트리스트에 없는 경우.
class AdminAccessDeniedPage extends StatelessWidget {
  final GoogleAuthService authService;
  final String? email;

  const AdminAccessDeniedPage({super.key, required this.authService, required this.email});

  Future<void> _handleSignOut(BuildContext context) async {
    await authService.signOut();
    if (!context.mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AdminGatePage(authService: authService)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                const Icon(Icons.block_rounded, color: AdminColors.danger, size: 40),
                const SizedBox(height: 16),
                const Text(
                  '권한이 없는 계정이에요',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdminColors.ivory),
                ),
                const SizedBox(height: 8),
                Text(
                  '${email ?? '(알 수 없음)'} 계정은 작가 편집기 접근 목록에 없어요.\n관리자에게 추가를 요청하세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AdminColors.muted, height: 1.5),
                ),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: () => _handleSignOut(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.ivory,
                    side: const BorderSide(color: AdminColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('다른 계정으로 로그인'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
