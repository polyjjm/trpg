/// 로그인/계정 동기화 기능을 위한 추상화.
///
/// 지금은 실제 로그인 백엔드가 없어 [LocalAuthService](로그인하지 않은 로컬 전용 상태)만
/// 존재한다. 나중에 실제 로그인 공급자(예: 자체 서버, Firebase Auth 등)를 붙일 때는 이
/// 인터페이스를 구현하는 새 클래스를 만들어 교체하면 되고, GameState나 UI 코드는 손댈
/// 필요가 없다 — 지금 당장은 아무 곳에서도 이 인터페이스를 사용하지 않는, 순수한 자리(seam)다.
abstract class AuthService {
  /// 현재 로그인된 사용자가 있는지.
  bool get isSignedIn;

  /// 로그인된 사용자의 고유 id. 로그인하지 않았다면 null.
  String? get userId;

  /// 리뷰/댓글 작성자 표시에 쓰는 로그인 공급자 프로필 값 — 로그인 안 했거나
  /// 공급자가 값을 안 주면 null(호출부가 "익명" 등으로 대체한다).
  String? get displayName;
  String? get photoUrl;

  Future<AuthResult> signIn();

  Future<void> signOut();
}

/// [AuthService.signIn] 결과.
class AuthResult {
  final bool success;
  final String? userId;
  final String? errorMessage;

  const AuthResult({required this.success, this.userId, this.errorMessage});
}
