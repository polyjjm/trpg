import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/google_auth_service.dart';
import '../../core/platform/remove_app_loading.dart';
import '../data/admin_allowlist.dart';
import 'admin_access_denied_page.dart';
import 'admin_shell_page.dart';
import 'admin_sign_in_page.dart';

/// 앱 진입점. 로그인 여부와 이메일 화이트리스트를 확인해 세 화면 중 하나로
/// 분기한다 — 미로그인(로그인 화면) / 로그인했지만 미허용(접근 거부) / 허용됨(편집기).
///
/// 게임 쪽 MainPage와 달리 리액티브 인증 스트림을 쓰지 않고, 로그인/로그아웃
/// 액션이 끝난 뒤 이 페이지를 다시 push해서 상태를 새로 평가하는 방식을
/// 그대로 따른다(기존 코드베이스의 관례).
class AdminGatePage extends StatefulWidget {
  final GoogleAuthService? authService;

  const AdminGatePage({super.key, this.authService});

  @override
  State<AdminGatePage> createState() => _AdminGatePageState();
}

class _AdminGatePageState extends State<AdminGatePage> {
  late final GoogleAuthService _authService = widget.authService ?? GoogleAuthService();

  @override
  void initState() {
    super.initState();
    removeAppLoadingSplash();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return AdminSignInPage(authService: _authService);
    }

    if (!isAllowedAdminEmail(user.email)) {
      return AdminAccessDeniedPage(authService: _authService, email: user.email);
    }

    return AdminShellPage(authService: _authService, email: user.email ?? '');
  }
}
