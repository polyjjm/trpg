import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/kakao_auth_service.dart';
import '../../../core/user/user_profile_repository.dart';
import '../../../widgets/loading.dart';
import '../../catalog/pages/catalog_shell_page.dart';

/// 로그인 화면 — Google/카카오 둘 중 하나로 로그인한다. 로그인은 필수이며,
/// 로그인 없이 넘어갈 방법은 없다. 로그인에 성공하면 클라우드 세이브를
/// 불러와(없으면 새로 생성) 라이브러리(카탈로그) 화면으로 이동한다.
///
/// 두 버튼의 로그인 "수행" 자체는 다른 경로를 탄다 — Google은
/// [AuthScope]가 앱 전체에 하나 들고 있는 [AuthService] 인스턴스를 그대로
/// 쓰지만, 카카오는 [AuthScope]를 거치지 않고 그 자리에서 바로
/// `KakaoAuthService().signIn()`을 부른다. 하지만 로그인 *이후*
/// 처리(_completeSignIn)는 완전히 같다.
///
/// 화면은 웹(데스크톱) 기준으로 짜여 있다 — 폭 1024 이상이면 좌측 브랜드
/// 패널 + 우측 로그인 패널(520 고정)로 나뉘고, 그 아래에서는 좁은 화면용
/// 세로 레이아웃 하나로 접힌다.
///
/// 로딩 표시는 버튼별 스피너가 아니라 화면 전체 오버레이 하나다 — 예전엔
/// Google/카카오 두 버튼이 동시에 스피너를 돌려서, 어느 쪽으로 로그인 중인지
/// 알 수 없고 두 개가 같이 도는 것처럼 보였다. 지금은 두 버튼 다 그냥
/// 비활성(onPressed: null)으로만 두고, [Loading] 카드를 화면 전체에 덮는다 —
/// web/index.html의 초기 스플래시, [AppLoadingScreen]과 같은 카드라서
/// 로그인 → 클라우드 세이브 로딩까지 같은 화면이 이어져 보인다.
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
  /// 카탈로그 화면 이동.
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

    // MainPage의 초기 로딩 경로와 동일한 계산 — author/admin 계정이 웹에서
    // 열었을 때만 "작가 모드로 전환" 링크가 나와야 한다.
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
      backgroundColor: TeloPalette.panel,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1024;
                if (!isWide) return _buildNarrow();
                return Row(
                  children: [
                    const Expanded(child: _BrandPanel()),
                    Container(
                      width: 520,
                      decoration: const BoxDecoration(
                        color: TeloPalette.panel,
                        border: Border(
                          left: BorderSide(color: TeloPalette.hairline),
                        ),
                      ),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 76,
                            vertical: 48,
                          ),
                          child: _buildLoginColumn(compact: false),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // 로그인 중에는 화면 전체를 덮는다 — 버튼별 스피너는 없다.
          if (_isSigningIn)
            const Positioned.fill(child: _SignInLoadingOverlay()),
        ],
      ),
    );
  }

  /// 좁은 화면(모바일 웹/앱) — 배경 그라디언트 위에 로고 · 문구 · 버튼을
  /// 한 줄로 쌓는다.
  Widget _buildNarrow() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF241C10), Color(0xFF16110A), Colors.black],
          stops: [0.0, 0.46, 1.0],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: _buildLoginColumn(compact: true),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginColumn({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _LogoCard(),
        SizedBox(height: compact ? 26 : 22),
        if (compact) ...[
          Text(
            'TELO',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w500,
              letterSpacing: 7.7,
              color: TeloPalette.text,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '읽고 고르는 이야기',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 3.1,
              color: TeloPalette.amber,
            ),
          ),
          const SizedBox(height: 44),
        ],
        const Text(
          '이야기를 시작하려면\n로그인이 필요합니다',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            height: 1.6,
            fontWeight: FontWeight.w500,
            color: TeloPalette.text,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '읽던 자리는 클라우드에 자동으로 저장됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.85,
            color: TeloPalette.text.withOpacity(0.55),
          ),
        ),
        const SizedBox(height: 40),
        _SignInButton(
          label: 'Google로 로그인',
          background: const Color(0xFFF0E68C),
          foreground: Colors.black,
          icon: Icons.login_rounded,
          onPressed: _isSigningIn ? null : _handleGoogleSignIn,
        ),
        const SizedBox(height: 12),
        // 카카오 공식 버튼 브랜딩 — 배경 #FEE500, 텍스트 #191919(순검정이
        // 아니다, 카카오 가이드가 지정하는 값). 카카오 로고 에셋은 이
        // 프로젝트에 없어서 말풍선 모양의 범용 Material 아이콘으로 대신한다.
        _SignInButton(
          label: '카카오로 시작하기',
          background: const Color(0xFFFEE500),
          foreground: const Color(0xFF191919),
          icon: Icons.chat_bubble_rounded,
          onPressed: _isSigningIn ? null : _handleKakaoSignIn,
        ),
        const SizedBox(height: 26),
        Text(
          '로그인하면 이용약관에 동의하게 됩니다',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            height: 1.8,
            color: TeloPalette.text.withOpacity(0.32),
          ),
        ),
      ],
    );
  }
}

/// 로그인 화면이 쓰는 색 — 로고(assets/images/telo_logo.svg)와 같은 계열의
/// 따뜻한 다크 톤. web/index.html의 스플래시와 값이 맞다.
class TeloPalette {
  const TeloPalette._();

  static const panel = Color(0xFF0B0906);
  static const hairline = Color(0xFF201A11);
  static const text = Color(0xFFF5EEE2);
  static const orange = Color(0xFFE2703A);
  static const amber = Color(0xFFF2B33D);
  static const paper = Color(0xFFF7F1E6);
}

/// 로고 마크를 얹은 종이 카드 — 뒤에 두 장을 살짝 기울여 겹쳐 "쌓인
/// 이야기"를 만든다.
class _LogoCard extends StatelessWidget {
  const _LogoCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 186,
      width: 200,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 24,
            child: Transform.rotate(
              angle: -0.122, // -7°
              child: Container(
                width: 126,
                height: 142,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A150E),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            child: Transform.rotate(
              angle: 0.07, // +4°
              child: Container(
                width: 126,
                height: 144,
                decoration: BoxDecoration(
                  color: const Color(0xFF251E14),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Container(
              width: 132,
              height: 150,
              decoration: BoxDecoration(
                color: TeloPalette.paper,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 24),
              // 카드 자체가 이미 종이색이라, 마크의 종이 배경은 빼고
              // 책갈피만 얹는다.
              child: SvgPicture.asset(
                'assets/images/telo_logo.svg',
                width: 96,
                height: 96,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 데스크톱 좌측 브랜드 패널 — 로그인과 무관한 소개 영역.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2116), Color(0xFF1A140C), Color(0xFF0B0906)],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  'assets/images/telo_logo.svg',
                  width: 40,
                  height: 40,
                ),
                const SizedBox(width: 14),
                Text(
                  'TELO',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 4.0,
                    color: TeloPalette.text,
                  ),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '읽는 이야기,\n고르는 이야기,\n같이 쓰는 이야기',
                    style: TextStyle(
                      fontSize: 44,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                      color: TeloPalette.text,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    '소설부터 선택지가 있는 인터랙티브 이야기까지, 한곳에서 이어 읽습니다.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.9,
                      color: TeloPalette.text.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            // 책등 — 실제 표지가 준비되면 이 자리를 스토리팩 커버로 바꾼다.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                _Spine(height: 104, color: TeloPalette.paper, opacity: 0.9),
                _Spine(height: 126, color: TeloPalette.orange, opacity: 0.85),
                _Spine(height: 88, color: Color(0xFF2F2618)),
                _Spine(height: 116, color: TeloPalette.amber, opacity: 0.8),
                _Spine(height: 96, color: Color(0xFF2F2618)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Spine extends StatelessWidget {
  final double height;
  final Color color;
  final double opacity;

  const _Spine({
    required this.height,
    required this.color,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 74,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}

/// 로그인 버튼 — 높이 52, radius 14(기존 값 그대로). 로그인 중에는
/// onPressed가 null이라 Material이 알아서 비활성 색으로 눌러 준다.
class _SignInButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
  final VoidCallback? onPressed;

  const _SignInButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: foreground, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withOpacity(0.45),
          disabledForegroundColor: foreground.withOpacity(0.55),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// 로그인 진행 중 화면 전체를 덮는 오버레이 — 딤 + [Loading] 카드.
/// 카드는 앱의 다른 로딩(web/index.html 스플래시, AppLoadingScreen)과 완전히
/// 같은 디자인이다.
class _SignInLoadingOverlay extends StatelessWidget {
  const _SignInLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xB8080604), // rgba(8,6,4,0.72)
      child: Stack(children: [Loading(message: '이야기를 불러오는 중...')]),
    );
  }
}
