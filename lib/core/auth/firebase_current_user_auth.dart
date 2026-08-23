import 'package:firebase_auth/firebase_auth.dart';

/// [AuthService]의 읽기 전용 부분(isSignedIn/userId/displayName/photoUrl) —
/// 로그인 이후에는 `FirebaseAuth.currentUser`가 어느 로그인 공급자(Google/
/// Kakao)로 로그인했든 완전히 동일하게 동작하므로, 이 네 getter는 공급자별
/// [AuthService] 구현마다 다시 쓸 이유가 없다. `GoogleAuthService`/
/// `KakaoAuthService`가 이 mixin을 함께 쓰고, 각자 로그인 흐름이 완전히 다른
/// `signIn()`/`signOut()`만 스스로 구현한다.
mixin FirebaseCurrentUserAuth {
  FirebaseAuth get firebaseAuth;

  bool get isSignedIn => firebaseAuth.currentUser != null;

  String? get userId => firebaseAuth.currentUser?.uid;

  String? get displayName => firebaseAuth.currentUser?.displayName;

  String? get photoUrl => firebaseAuth.currentUser?.photoURL;
}
