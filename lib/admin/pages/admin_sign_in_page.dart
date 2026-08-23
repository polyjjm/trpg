import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/auth/google_auth_service.dart';
import '../../core/auth/kakao_auth_service.dart';
import '../widgets/admin_theme.dart';
import 'admin_gate_page.dart';

/// 작가 편집기 로그인 화면 — Google/카카오 둘 중 하나로 로그인한다. 게임 쪽
/// SignInPage와 같은 원칙: 별도 인증 시스템을 새로 만들지 않고 기존
/// AuthService 구현들을 그대로 재사용한다.
///
/// 두 버튼의 로그인 "수행" 자체는 다른 경로를 탄다 — Google은 이 화면이
/// 생성자로 받은 [authService] 인스턴스를 그대로 쓰지만, 카카오는 그 자리에서
/// 바로 `KakaoAuthService().signIn()`을 부른다(sign_in_page.dart의 Kakao
/// 버튼과 정확히 같은 패턴 — 거기서도 AuthScope가 들고 있는 인스턴스는
/// 안 거친다). 하지만 로그인 *이후*(_completeSignIn)에는 항상
/// [widget.authService]로 [AdminGatePage]를 연다 — 로그인에 성공한 순간부터
/// `FirebaseAuth.currentUser`는 어느 공급자로 로그인했든 완전히 동일하게
/// 동작해서(google_auth_service.dart/kakao_auth_service.dart가 공유하는
/// [FirebaseCurrentUserAuth] 참고), 웹에서는 `GoogleAuthService.signOut()`도
/// 결국 `FirebaseAuth.instance.signOut()`만 부르는 것과 같다 — 실제로 로그인에
/// 쓰지 않은 GoogleAuthService 인스턴스를 계속 재사용해도 아무 문제가 없다.
class AdminSignInPage extends StatefulWidget {
  final GoogleAuthService authService;

  const AdminSignInPage({super.key, required this.authService});

  @override
  State<AdminSignInPage> createState() => _AdminSignInPageState();
}

class _AdminSignInPageState extends State<AdminSignInPage> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    final result = await widget.authService.signIn();
    _completeSignIn(result);
  }

  Future<void> _handleKakaoSignIn() async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    final result = await KakaoAuthService().signIn();
    _completeSignIn(result);
  }

  /// Google/카카오 버튼이 공유하는 로그인 이후 처리 — 위 클래스 문서 참고.
  void _completeSignIn(AuthResult result) {
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
      MaterialPageRoute(
        builder: (_) => AdminGatePage(authService: widget.authService),
      ),
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
                Text(
                  '작가 편집기',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AdminColors.ivory,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Google 또는 카카오 계정으로 로그인하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AdminColors.muted),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                    icon: _isSigningIn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(_isSigningIn ? '로그인 중...' : 'Google로 로그인'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  // 카카오 공식 버튼 브랜딩(#FEE500 배경 + #191919 텍스트) +
                  // 말풍선 아이콘 — sign_in_page.dart의 카카오 버튼과 정확히
                  // 같은 값이다(관리자 테마의 라이트/다크에 흔들리지 않는
                  // 고정 브랜드 색이라 AdminColors가 아니라 그대로 하드코딩).
                  child: ElevatedButton.icon(
                    onPressed: _isSigningIn ? null : _handleKakaoSignIn,
                    icon: _isSigningIn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF191919),
                            ),
                          )
                        : const Icon(
                            Icons.chat_bubble_rounded,
                            color: Color(0xFF191919),
                          ),
                    label: Text(_isSigningIn ? '로그인 중...' : '카카오로 시작하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: const Color(0xFF191919),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AdminColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
