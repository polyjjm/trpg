import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'admin/pages/admin_gate_page.dart';
import 'admin/widgets/admin_theme.dart';
import 'firebase_options.dart';

/// 작가/관리자용 웹 편집기 진입점 — 게임 앱(lib/main.dart)과는 별도로 빌드된다.
///
///   flutter run -d chrome -t lib/main_admin.dart
///   flutter build web -t lib/main_admin.dart
///
/// 게임과 같은 코드베이스·같은 Firebase 프로젝트를 공유하지만(core/auth,
/// firebase_options.dart 재사용), lib/admin/ 아래 화면·상태는 이 파일에서만
/// 참조된다 — lib/main.dart나 lib/features/**는 lib/admin/을 import하지 않으므로
/// `flutter build apk -t lib/main.dart`(모바일 게임 빌드)에는 이 폴더가 전혀
/// 포함되지 않는다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AdminTheme.load();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    // AdminTheme.mode가 바뀔 때마다(라이트/다크 토글) MaterialApp을 통째로
    // 다시 그린다 — themeMode가 바뀌면 기본 Material 위젯(체크박스/스위치
    // 기본 색상 등 AdminColors로 직접 칠하지 않은 것들)은 즉시 반응한다.
    // AdminColors 자체는 여전히 static const라(admin_theme.dart 상단 doc
    // 참고) 화면 대부분의 색은 이 토글에 반응하지 않는다 — 인프라(저장/토글
    // 버튼)만 이번 패스 범위다.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AdminTheme.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Telo 작가 편집기',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFFBF8F3),
            fontFamily: 'NotoSansKR',
            colorScheme: ColorScheme.fromSeed(
              seedColor: AdminColors.gold,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AdminColors.bg,
            fontFamily: 'NotoSansKR',
            colorScheme: ColorScheme.fromSeed(
              seedColor: AdminColors.gold,
              brightness: Brightness.dark,
            ),
          ),
          home: const AdminGatePage(),
        );
      },
    );
  }
}
