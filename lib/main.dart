import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'widgets/app_loading_screen.dart';
import 'core/auth/auth_scope.dart';
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
        title: 'TELO',
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
///
/// 목적지(SignInPage/CatalogShellPage)로 Navigator.pushReplacement를 쓰지
/// 않는다 — 예전엔 그렇게 라우트를 통째로 갈아 끼웠는데, 그 라우트 전환
/// 애니메이션 자체가 "로딩 화면이 사라지고 아직 데이터가 안 찬 홈 탭이
/// 드러나는" 눈에 띄는 컷이었다(게다가 CatalogShellPage는 스토리팩 스트림의
/// 첫 스냅샷이 오기 전까지 홈 탭에 보여줄 게 없어서 그 사이 "아직 연재 중인
/// 스토리가 없어요" 같은 문구가 잠깐 스쳐 지나갔다). 대신 목적지를 이 위젯의
/// 자식으로 Stack에 얹어 두고, [AppLoadingScreen]을 같은 인스턴스로 계속
/// 마운트한 채 opacity만 내려서 걷어낸다 — CatalogShellPage는 홈 탭의 첫
/// 스토리팩 데이터가 실제로 도착했을 때만 [onContentReady]를 불러 준다.
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  Widget? _destination;
  bool _showLoading = true;

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
      // 로그인 화면은 기다릴 스트림이 없으니 목적지가 정해지자마자 곧장
      // 로딩 오버레이를 걷어낸다.
      setState(() {
        _destination = const SignInPage();
        _showLoading = false;
      });
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

    setState(() {
      _destination = CatalogShellPage(
        showAuthorModeLink: showAuthorModeLink,
        // 홈 탭의 스토리팩 스트림이 첫 스냅샷(데이터든 에러든)을 내놓기
        // 전까지는 _showLoading이 true로 남아, 로딩 오버레이가 실제 콘텐츠
        // 위에 계속 덮여 있는다.
        onContentReady: () {
          if (!mounted) return;
          setState(() => _showLoading = false);
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cloudSync = AuthScope.cloudSyncOf(context);

    return Scaffold(
      body: Stack(
        children: [
          ?_destination,
          // 자동 저장 실패는 debugPrint로만 삼키지 않고 사용자에게도 보인다.
          // 실패가 이어지는 동안 배너 하나만 유지되고, 최신 저장이 성공하면
          // CloudSyncController가 null로 되돌려 자동으로 사라진다.
          ValueListenableBuilder<String?>(
            valueListenable: cloudSync.saveErrorMessage,
            builder: (context, message, child) {
              if (message == null) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 20),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                message,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // web/index.html의 #app-loading(Flutter 엔진이 뜨기 전 HTML/CSS
          // 스플래시)과 같은 카드 디자인을 그대로 이어받는 AppLoadingScreen을
          // 프로세스 시작부터 실제 콘텐츠가 준비될 때까지 단 하나의 인스턴스로
          // 계속 마운트해 둔다 — 부트스트랩 단계와 데이터 로딩 단계가 서로
          // 다른 인스턴스로 새로 그려지면 진행 바 애니메이션이 처음부터 다시
          // 시작되면서 그 자체가 눈에 띄는 깜빡임처럼 보인다.
          IgnorePointer(
            ignoring: !_showLoading,
            child: AnimatedOpacity(
              opacity: _showLoading ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: const AppLoadingScreen(),
            ),
          ),
        ],
      ),
    );
  }
}
