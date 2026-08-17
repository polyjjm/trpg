import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/google_auth_service.dart';
import '../../core/platform/remove_app_loading.dart';
import '../../core/user/author_application_status.dart';
import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/author_application_repository.dart';
import '../models/author_application.dart';
import '../widgets/admin_theme.dart';
import 'admin_sign_in_page.dart';
import 'author_application_page.dart';
import 'author_application_status_page.dart';
import 'author_tool_page.dart';

/// 앱 진입점. 로그인 여부와 users/{uid}.role / authorApplicationStatus를 확인해
/// 화면을 가른다 — 미로그인(로그인 화면) / 로그인했지만 author·admin이 아님(신청
/// 폼 또는 대기 화면) / author 또는 admin(편집기).
///
/// 게임 쪽 MainPage와 달리 리액티브 인증 스트림을 쓰지 않고, 로그인/로그아웃/
/// 신청 제출 같은 액션이 끝난 뒤 이 페이지를 다시 push해서 상태를 새로
/// 평가하는 방식을 그대로 따른다(기존 코드베이스의 관례).
class AdminGatePage extends StatefulWidget {
  final GoogleAuthService? authService;
  final UserProfileRepository? userProfileRepository;
  final AuthorApplicationRepository? authorApplicationRepository;

  const AdminGatePage({
    super.key,
    this.authService,
    this.userProfileRepository,
    this.authorApplicationRepository,
  });

  @override
  State<AdminGatePage> createState() => _AdminGatePageState();
}

class _AdminGatePageState extends State<AdminGatePage> {
  late final GoogleAuthService _authService = widget.authService ?? GoogleAuthService();
  late final UserProfileRepository _userProfileRepository =
      widget.userProfileRepository ?? UserProfileRepository();
  late final AuthorApplicationRepository _authorApplicationRepository =
      widget.authorApplicationRepository ?? AuthorApplicationRepository();

  Future<(UserProfile, AuthorApplication?)>? _loadFuture;

  @override
  void initState() {
    super.initState();
    removeAppLoadingSplash();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _loadFuture = _load(user);
    }
  }

  Future<(UserProfile, AuthorApplication?)> _load(User user) async {
    final profile = await _userProfileRepository.ensureProfile(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
    );

    if (profile.canAccessAuthorTool) {
      return (profile, null);
    }

    final application = await _authorApplicationRepository.fetchApplication(user.uid);
    return (profile, application);
  }

  void _pushFreshGate(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminGatePage(
          authService: _authService,
          userProfileRepository: _userProfileRepository,
          authorApplicationRepository: _authorApplicationRepository,
        ),
      ),
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    await _authService.signOut();
    if (!context.mounted) return;
    _pushFreshGate(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return AdminSignInPage(authService: _authService);
    }

    return FutureBuilder<(UserProfile, AuthorApplication?)>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AdminGateLoading();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _AdminGateError(authService: _authService);
        }

        final (profile, application) = snapshot.data!;

        if (profile.canAccessAuthorTool) {
          return AuthorToolPage(
            authService: _authService,
            email: user.email ?? '',
            isAdmin: profile.isAdmin,
          );
        }

        final canApply = profile.authorApplicationStatus == AuthorApplicationStatus.none ||
            profile.authorApplicationStatus == AuthorApplicationStatus.rejected;

        if (canApply) {
          return AuthorApplicationPage(
            user: user,
            previousApplication: application,
            repository: _authorApplicationRepository,
            onSubmitted: () => _pushFreshGate(context),
            onSignOut: () => _handleSignOut(context),
          );
        }

        return AuthorApplicationStatusPage(
          application: application,
          onSignOut: () => _handleSignOut(context),
        );
      },
    );
  }
}

class _AdminGateLoading extends StatelessWidget {
  const _AdminGateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AdminColors.bg,
      body: Center(child: CircularProgressIndicator(color: AdminColors.gold)),
    );
  }
}

/// users/{uid} 조회 자체가 실패한 경우(네트워크 등) — 권한/신청 상태와는 다른
/// 문제라 신청 화면들과 구분해서 보여준다.
class _AdminGateError extends StatelessWidget {
  final GoogleAuthService authService;

  const _AdminGateError({required this.authService});

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
                const Icon(Icons.error_outline_rounded, color: AdminColors.danger, size: 40),
                const SizedBox(height: 16),
                const Text(
                  '계정 정보를 불러오지 못했어요',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.ivory),
                ),
                const SizedBox(height: 8),
                const Text(
                  '네트워크 상태를 확인하고 다시 시도해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AdminColors.muted),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => AdminGatePage(authService: authService)),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.ivory,
                    side: const BorderSide(color: AdminColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
