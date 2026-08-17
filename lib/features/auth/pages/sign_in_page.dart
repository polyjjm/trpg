import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/user/user_profile_repository.dart';
import '../../catalog/pages/catalog_shell_page.dart';

/// Google 로그인 화면. 로그인은 필수이며, 로그인 없이 넘어갈 방법은 없다.
/// 로그인에 성공하면 클라우드 세이브를 불러와(없으면 새로 생성) 라이브러리
/// (카탈로그) 화면으로 이동한다.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);

    final authService = AuthScope.of(context);
    final result = await authService.signIn();

    if (!mounted) return;

    if (!result.success) {
      setState(() => _isSigningIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? '로그인에 실패했습니다.')),
      );
      return;
    }

    // GameState에 클라우드 세이브를 미리 반영해 두어, 카탈로그의 상세 화면이
    // 곧바로 정확한 진행 상황을 보여줄 수 있게 한다.
    await AuthScope.cloudSyncOf(context).loadOrInitialize();

    if (!mounted) return;

    // MainPage의 초기 로딩 경로와 동일한 계산 — 이미 로그인된 상태로 앱을
    // 여는 경우(MainPage)와 방금 로그인한 경우(여기) 둘 다 author/admin
    // 계정이면 "작가 모드로 전환" 링크가 나와야 한다. 예전엔 여기서 이 계산을
    // 안 해서, 방금 로그인한 author/admin 계정에는 링크가 안 보였다.
    var showAuthorModeLink = false;
    if (kIsWeb) {
      final uid = authService.userId;
      if (uid != null) {
        final profile = await UserProfileRepository().ensureProfile(
          uid: uid,
          displayName: FirebaseAuth.instance.currentUser?.displayName,
          email: FirebaseAuth.instance.currentUser?.email,
        );
        showAuthorModeLink = profile.canAccessAuthorTool;
      }
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => CatalogShellPage(showAuthorModeLink: showAuthorModeLink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Telo',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                  color: Colors.white.withOpacity(0.94),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '게임을 시작하려면 로그인이 필요합니다.\n진행 상황은 클라우드에 자동으로 저장됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.62),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                  icon: _isSigningIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(_isSigningIn ? '로그인 중...' : 'Google로 로그인'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0E68C),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
