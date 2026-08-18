import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'widgets/loading.dart';
import 'core/auth/auth_scope.dart';
import 'core/constants/asset_paths.dart';
import 'core/monetization/admob_monetization_service.dart';
import 'core/platform/remove_app_loading.dart';
import 'core/state/game_state_provider.dart';
import 'core/user/user_profile_repository.dart';
import 'features/auth/pages/sign_in_page.dart';
import 'features/catalog/pages/catalog_shell_page.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // 웹 빌드에서는 google_mobile_ads(모바일 전용 플러그인)를 초기화하지 않는다.
  if (!kIsWeb) {
    await AdMobMonetizationService.initialize();
  }
  runApp(const MyApp());
}

// 앱 시작점
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GameStateProvider(
      child: MaterialApp(
        title: 'Telo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          fontFamily: 'NotoSansKR',
        ),
        home: const MainPage(),
      ),
    );
  }
}

/// 앱 진입 시 한 번 거치는 게이트 화면.
/// 로그인 여부를 확인해 미로그인 상태면 로그인 화면으로 보내 접근을 차단하고,
/// 로그인 상태면 클라우드 세이브를 GameState에 반영한 뒤 라이브러리(카탈로그)
/// 화면으로 이동한다 — '새 게임/이어하기' 메뉴 역할은 이제 라이브러리의 상세
/// 화면(StoryPackDetailPage)이 맡는다.
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    removeAppLoadingSplash();

    await Future.delayed(const Duration(milliseconds: 1400));

    if (!mounted) return;

    final authService = AuthScope.of(context);

    if (!authService.isSignedIn) {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SignInPage()),
      );
      return;
    }

    await AuthScope.cloudSyncOf(context).loadOrInitialize();

    if (!mounted) return;

    // author/admin 계정이 웹에서 열었을 때만 "작가 모드로 전환" 링크를 보여준다 —
    // 대부분의 계정(role: reader)은 이 조회 결과와 무관하게 아무 것도 안 보인다.
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

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => CatalogShellPage(showAuthorModeLink: showAuthorModeLink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1610), Colors.black],
                ),
              ),
            ),
          ),
          Center(
            child: SvgPicture.asset(UiPaths.logo, width: 88, height: 88),
          ),
          const Loading(message: '이야기를 불러오는 중...'),
        ],
      ),
    );
  }
}
