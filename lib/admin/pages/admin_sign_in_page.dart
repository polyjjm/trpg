import 'package:flutter/material.dart';

import '../../core/auth/google_auth_service.dart';
import '../widgets/admin_theme.dart';
import 'admin_gate_page.dart';

/// 작가 편집기 로그인 화면. 게임 쪽 SignInPage와 마찬가지로 기존
/// GoogleAuthService를 그대로 재사용한다 — 별도 인증 시스템을 새로 만들지 않는다.
class AdminSignInPage extends StatefulWidget {
  final GoogleAuthService authService;

  const AdminSignInPage({super.key, required this.authService});

  @override
  State<AdminSignInPage> createState() => _AdminSignInPageState();
}

class _AdminSignInPageState extends State<AdminSignInPage> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _handleSignIn() async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    final result = await widget.authService.signIn();

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isSigningIn = false;
        _errorMessage = result.errorMessage ?? '로그인에 실패했습니다.';
      });
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AdminGatePage(authService: widget.authService)),
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
                const Text(
                  '작가 편집기',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AdminColors.ivory),
                ),
                const SizedBox(height: 8),
                const Text(
                  '허용된 작가/관리자 계정으로 로그인하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AdminColors.muted),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isSigningIn ? null : _handleSignIn,
                    icon: _isSigningIn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(_isSigningIn ? '로그인 중...' : 'Google로 로그인'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(_errorMessage!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
