import 'package:cloud_functions/cloud_functions.dart';

/// setAuthorAccountDisabled 결과 — 실제로 몇 개의 팩이 같이 내려갔는지는
/// 서버가 계산해 돌려준다(클라이언트는 uid/disabled/suspendPacks/reason만
/// 보냈다).
class SetAuthorAccountDisabledResult {
  final bool success;
  final int suspendedPackCount;

  const SetAuthorAccountDisabledResult({
    required this.success,
    required this.suspendedPackCount,
  });
}

/// admin 전용 — 작가 계정의 Firebase Auth 로그인 자체를 막거나(정지) 다시
/// 허용한다(정지 해제). refundCoinCharge와 같은 원칙: 클라이언트 SDK는
/// 다른 유저의 Auth 계정을 건드릴 수 없으므로(Admin SDK 전용 API), admin
/// 권한 확인부터 실제 처리까지 전부 setAuthorAccountDisabled Cloud
/// Function이 서버에서 한다.
class AuthorAccountService {
  AuthorAccountService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<SetAuthorAccountDisabledResult> setAccountDisabled({
    required String uid,
    required bool disabled,
    required bool suspendPacks,
    String? reason,
  }) async {
    final callable = _functions.httpsCallable('setAuthorAccountDisabled');
    final result = await callable.call<Map<String, dynamic>>({
      'uid': uid,
      'disabled': disabled,
      'suspendPacks': suspendPacks,
      if (reason != null) 'reason': reason,
    });

    final data = result.data;
    return SetAuthorAccountDisabledResult(
      success: data['success'] as bool? ?? false,
      suspendedPackCount: (data['suspendedPackCount'] as num?)?.toInt() ?? 0,
    );
  }
}
