import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'auth_service.dart';
import 'firebase_current_user_auth.dart';
import 'kakao_login_popup.dart';
import 'kakao_popup_result.dart';

/// 카카오 로그인 — Firebase Authentication에는 카카오 공급자가 없어서
/// (Google과 달리), 이 클래스는 카카오 자체 OAuth 흐름 + 백엔드 Cloud
/// Function(`kakaoSignIn`, functions/src/index.ts)을 거쳐 Firebase 커스텀
/// 토큰을 받아 로그인한다:
///
/// 1. [openKakaoLoginPopup]이 카카오 OAuth 인가 팝업을 띄우고 인가 코드를
///    받아온다(lib/core/auth/kakao_login_popup.dart — Toss 결제 팝업과 같은
///    패턴).
/// 2. 그 코드를 `kakaoSignIn` Cloud Function에 넘긴다 — 서버가 카카오 REST
///    API 키/클라이언트 시크릿으로 액세스 토큰과 교환하고, 그 토큰으로
///    카카오 API(`kapi.kakao.com/v2/user/me`)를 직접 불러 사용자를
///    검증한다(클라이언트가 보낸 값을 그대로 믿지 않는다).
/// 3. 서버가 `kakao_{카카오 유저 id}` 형태의 안정적인 Firebase uid로 매핑해
///    Firebase 커스텀 토큰을 돌려주면, [FirebaseAuth.signInWithCustomToken]으로
///    로그인을 마친다 — 그 순간부터 `FirebaseAuth.currentUser`는 Google로
///    로그인했을 때와 완전히 똑같이 동작한다(그래서 이 클래스도
///    [FirebaseCurrentUserAuth]를 그대로 함께 쓴다).
///
/// 지금은 웹 전용이다 — 카카오 로그인 팝업이 dart:html 기반이라 네이티브
/// 모바일 앱이 생기면 카카오 네이티브 SDK로 별도 구현이 필요하다
/// (google_mobile_ads처럼 이 프로젝트가 아직 웹 전용이라 미뤄 둔 것과 같은
/// 이유 — CLAUDE.md의 모바일 준비 체크리스트 참고).
class KakaoAuthService with FirebaseCurrentUserAuth implements AuthService {
  KakaoAuthService({FirebaseAuth? firebaseAuth, FirebaseFunctions? functions})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFunctions _functions;

  @override
  FirebaseAuth get firebaseAuth => _firebaseAuth;

  /// 카카오 JavaScript 키 — 카카오 자신의 설계상 공개 키다(REST API 키/
  /// 클라이언트 시크릿과 달리 웹 자산에 그대로 박아 둬도 안전하다, 카카오
  /// 개발자 문서가 명시하는 구분이다). REST API 키/클라이언트 시크릿은
  /// 절대 클라이언트 코드에 두지 않는다 — 그 둘은 오직 `kakaoSignIn` Cloud
  /// Function이 서버 쪽 시크릿(`defineSecret`)으로만 갖고 있다.
  static const _jsKey = '7c6f4efc5c324009b53fff62862ddd49';

  @override
  Future<AuthResult> signIn() async {
    if (!kIsWeb) {
      return const AuthResult(
        success: false,
        errorMessage: '카카오 로그인은 아직 웹에서만 지원돼요.',
      );
    }

    // 카카오 개발자 콘솔의 "카카오 로그인 > Redirect URI"에 이 정확한 값이
    // (배포 도메인 + 로컬 개발 주소 각각) 등록돼 있어야 한다 — 카카오
    // 토큰 교환 API는 여기서 보낸 값과 authorize 요청 때 쓴 값이 정확히
    // 일치하지 않으면 거부한다.
    final redirectUri = Uri.base.resolve('kakao_login_return.html').toString();

    final popupResult = await openKakaoLoginPopup(
      jsKey: _jsKey,
      redirectUri: redirectUri,
    );

    switch (popupResult) {
      case KakaoPopupBlocked():
        return const AuthResult(
          success: false,
          errorMessage: '팝업이 차단됐어요. 브라우저의 팝업 차단을 해제한 뒤 다시 시도해 주세요.',
        );
      case KakaoPopupCancelled():
        return const AuthResult(success: false, errorMessage: '로그인이 취소되었습니다.');
      case KakaoPopupFailure(:final message):
        return AuthResult(success: false, errorMessage: message);
      case KakaoPopupSuccess(:final code):
        try {
          final callable = _functions.httpsCallable('kakaoSignIn');
          final response = await callable.call<Map<String, dynamic>>({
            'code': code,
            'redirectUri': redirectUri,
          });
          final customToken = response.data['customToken'] as String?;
          if (customToken == null || customToken.isEmpty) {
            return const AuthResult(
              success: false,
              errorMessage: '로그인에 실패했습니다.',
            );
          }
          final credential = await _firebaseAuth.signInWithCustomToken(
            customToken,
          );
          return AuthResult(success: true, userId: credential.user?.uid);
        } catch (e) {
          return AuthResult(success: false, errorMessage: '로그인에 실패했습니다: $e');
        }
    }
  }

  @override
  Future<void> signOut() async {
    // 카카오 액세스 토큰은 kakaoSignIn Cloud Function이 서버에서 잠깐
    // 검증만 하고 클라이언트에는 절대 돌려주지 않는다 — 로그인 이후로는
    // 완전히 Firebase 세션(커스텀 토큰)으로만 동작해서, 여기서 별도로 끊어야
    // 할 "카카오 쪽 세션"이 없다.
    await _firebaseAuth.signOut();
  }
}
