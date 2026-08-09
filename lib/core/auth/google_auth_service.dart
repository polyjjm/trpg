import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

/// Firebase Authentication의 Google 로그인 공급자를 사용하는 실제 구현.
/// 웹에서는 GoogleAuthProvider + signInWithPopup 방식을, 모바일에서는 google_sign_in
/// 패키지로 얻은 자격 증명을 Firebase에 넘기는 방식을 사용한다.
class GoogleAuthService implements AuthService {
  GoogleAuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _providedGoogleSignIn = googleSignIn;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn? _providedGoogleSignIn;

  // 웹에서는 google_sign_in 패키지를 쓰지 않으므로, 실제로 필요한 모바일 분기에서만
  // 생성한다 — 그렇지 않으면 웹 환경에서 client_id 없이 자동 초기화가 시도된다.
  late final GoogleSignIn _googleSignIn = _providedGoogleSignIn ?? GoogleSignIn();

  @override
  bool get isSignedIn => _firebaseAuth.currentUser != null;

  @override
  String? get userId => _firebaseAuth.currentUser?.uid;

  @override
  Future<AuthResult> signIn() async {
    try {
      final UserCredential credential;

      if (kIsWeb) {
        credential = await _firebaseAuth.signInWithPopup(GoogleAuthProvider());
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
      return AuthResult(
        success: false,
        errorMessage: '로그인에 실패했습니다: $e',
      );
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
