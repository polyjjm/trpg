/// 로그인/계정 동기화 기능을 위한 추상화.
///
/// 실제 구현은 둘이다 — `GoogleAuthService`(Firebase Authentication의 Google
/// 공급자)와 `KakaoAuthService`(카카오 로그인 → 백엔드 Cloud Function이 발급한
/// Firebase 커스텀 토큰). 둘 다 로그인에 성공하고 나면 결과적으로
/// `FirebaseAuth.currentUser`가 채워진다는 점은 같아서, 이 인터페이스의
/// 읽기 전용 부분(isSignedIn/userId/displayName/photoUrl)은 어느 쪽으로
/// 로그인했는지 구분하지 않는다 — [AuthScope]가 앱 전체에 딱 하나의
/// [AuthService] 인스턴스만 들고 있어도, 다른 공급자로 로그인한 뒤에도 그
/// 인스턴스를 그대로 계속 쓸 수 있는 이유다(lib/features/auth/pages/
/// sign_in_page.dart가 Kakao 로그인은 AuthScope를 거치지 않고 직접
/// `KakaoAuthService().signIn()`을 부르면서도, 로그인 *이후* 상태 조회는
/// 여전히 AuthScope 쪽 인스턴스로 하는 이유가 바로 이거다).
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
