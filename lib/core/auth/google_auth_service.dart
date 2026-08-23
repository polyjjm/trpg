import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';
import 'firebase_current_user_auth.dart';

/// Firebase Authentication의 Google 로그인 공급자를 사용하는 실제 구현.
/// 웹에서는 GoogleAuthProvider + signInWithPopup 방식을, 모바일에서는 google_sign_in
/// 패키지로 얻은 자격 증명을 Firebase에 넘기는 방식을 사용한다.
///
/// [AuthService]의 다른 구현으로 [KakaoAuthService](lib/core/auth/
/// kakao_auth_service.dart)가 있다 — 로그인 흐름(signIn/signOut)만 공급자마다
/// 다르고, 로그인 이후 읽기 전용 상태(isSignedIn/userId/displayName/
/// photoUrl)는 둘 다 [FirebaseCurrentUserAuth] mixin을 공유한다.
class GoogleAuthService with FirebaseCurrentUserAuth implements AuthService {
  GoogleAuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _providedGoogleSignIn = googleSignIn;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn? _providedGoogleSignIn;

  @override
  FirebaseAuth get firebaseAuth => _firebaseAuth;

  // 웹에서는 google_sign_in 패키지를 쓰지 않으므로, 실제로 필요한 모바일 분기에서만
  // 생성한다 — 그렇지 않으면 웹 환경에서 client_id 없이 자동 초기화가 시도된다.
  late final GoogleSignIn _googleSignIn =
      _providedGoogleSignIn ?? GoogleSignIn();

  @override
  Future<AuthResult> signIn() async {
    try {
      final UserCredential credential;

      if (kIsWeb) {
        // prompt: 'select_account'를 명시하지 않으면 FirebaseAuth.signOut()
        // 이후에도(그건 Firebase 세션만 지운다) 브라우저에 남아 있는 구글
        // 계정 세션으로 팝업 없이 곧장 재로그인돼서, 계정을 못 바꾸는
        // 것처럼 보인다 — Firebase Auth + Google 웹 팝업의 잘 알려진
        // 동작이라 이 커스텀 파라미터가 표준 해결책이다.
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        credential = await _firebaseAuth.signInWithPopup(provider);
      } else {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return const AuthResult(
            success: false,
            errorMessage: '로그인이 취소되었습니다.',
          );
        }

        final googleAuth = await googleUser.authentication;
        final oauthCredential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        credential = await _firebaseAuth.signInWithCredential(oauthCredential);
      }

      return AuthResult(success: true, userId: credential.user?.uid);
    } catch (e) {
      return AuthResult(success: false, errorMessage: '로그인에 실패했습니다: $e');
    }
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
  }
}
