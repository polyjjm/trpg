import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/kakao_auth_service.dart';
import '../../../core/user/user_profile_repository.dart';
import '../../catalog/pages/catalog_shell_page.dart';

/// 로그인 화면 — Google/카카오 둘 중 하나로 로그인한다. 로그인은 필수이며,
/// 로그인 없이 넘어갈 방법은 없다. 로그인에 성공하면 클라우드 세이브를
/// 불러와(없으면 새로 생성) 라이브러리(카탈로그) 화면으로 이동한다.
///
/// 두 버튼의 로그인 "수행" 자체는 다른 경로를 탄다 — Google은
/// [AuthScope]가 앱 전체에 하나 들고 있는 [AuthService] 인스턴스를 그대로
/// 쓰지만, 카카오는 [AuthScope]를 거치지 않고 그 자리에서 바로
/// `KakaoAuthService().signIn()`을 부른다([AuthScope]는 공급자 하나만
/// 들고 있어서, 두 번째 공급자를 위해 굳이 늘릴 이유가 없다 —
/// auth_service.dart의 [AuthService] 문서 참고). 하지만 로그인 *이후*
/// 처리(_completeSignIn)는 완전히 같다 — 어느 쪽으로 로그인했든 그 순간부터
/// `FirebaseAuth.currentUser`가 채워진 상태는 동일해서, [AuthScope]의
/// 공유 인스턴스로 그 상태를 읽으면 그만이다.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    final result = await AuthScope.of(context).signIn();
    await _completeSignIn(result);
  }

  Future<void> _handleKakaoSignIn() async {
    setState(() => _isSigningIn = true);
    final result = await KakaoAuthService().signIn();
    await _completeSignIn(result);
  }

  /// Google/카카오 로그인 버튼 핸들러가 공유하는 로그인 이후 처리 — 실패
  /// 스낵바, 클라우드 세이브 불러오기, users/{uid} 문서 생성(최초 로그인),
  /// 카탈로그 화면 이동. 어느 [AuthService]로 로그인했는지는 여기서부터
  /// 중요하지 않다(위 클래스 문서 참고) — 항상 [AuthScope]의 공유 인스턴스로
  /// 읽는다.
  Future<void> _completeSignIn(AuthResult result) async {
    if (!mounted) return;

    if (!result.success) {
      setState(() => _isSigningIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? '로그인에 실패했습니다.')),
      );
      return;
    }

    final authService = AuthScope.of(context);

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
      MaterialPageRoute(
        builder: (_) =>
            CatalogShellPage(showAuthorModeLink: showAuthorModeLink),
      ),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                // 카카오 공식 버튼 브랜딩 — 배경 #FEE500, 텍스트 #191919
                // (순검정이 아니다, 카카오 가이드가 지정하는 값). 카카오
                // 로고 에셋은 이 프로젝트에 없어서(assets/에 없음, 새로
                // 만들지 않는다) 말풍선 모양의 범용 Material 아이콘으로
                // 대신한다 — 카카오의 실제 로고를 흉내 낸 게 아니라 순수
                // 대체 아이콘이다.
                child: ElevatedButton.icon(
                  onPressed: _isSigningIn ? null : _handleKakaoSignIn,
                  icon: _isSigningIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
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
