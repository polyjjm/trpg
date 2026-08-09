import 'auth_service.dart';

/// 실제 로그인 백엔드가 준비되기 전까지 쓰는 기본 구현.
/// 항상 "로그인하지 않은 로컬 전용 사용자" 상태를 유지하며, signIn()을 호출해도 실패로
/// 처리한다. 실제 로그인 연동이 준비되면 [AuthService]를 구현하는 새 클래스(예:
/// ServerAuthService)로 교체하면 된다.
class LocalAuthService implements AuthService {
  const LocalAuthService();

  @override
  bool get isSignedIn => false;

  @override
  String? get userId => null;

  @override
  Future<AuthResult> signIn() async {
    // TODO: 실제 로그인 공급자 연동 지점.
    return const AuthResult(
      success: false,
      errorMessage: '로그인 기능은 아직 준비되지 않았습니다.',
    );
  }

  @override
  Future<void> signOut() async {}
}
