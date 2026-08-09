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
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZOMBIE ROAD 작가 편집기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
  }
}
