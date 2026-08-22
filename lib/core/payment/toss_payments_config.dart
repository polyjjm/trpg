/// Toss Payments 설정값. 클라이언트 키는 결제창을 여는 데만 쓰이고 결제
/// 승인 권한이 없어 앱 코드에 그대로 둬도 안전하다(Toss 공식 문서 기준) —
/// 시크릿 키와 반대다. 시크릿 키는 여기 없다: functions/src/index.ts의
/// confirmCoinCharge가 Firebase Functions 시크릿(TOSS_SECRET_KEY)에서만
/// 읽는다 — 이 저장소 어디에도 하드코딩되지 않는다.
class TossPaymentsConfig {
  TossPaymentsConfig._();

  /// 테스트 모드 클라이언트 키. 실 서비스로 전환할 때 실제 클라이언트 키로
  /// 교체하면 되고(이 값 자체는 비밀이 아니다), 그때 functions 쪽
  /// TOSS_SECRET_KEY도 같이 실 서비스용 시크릿 키로 교체해야 한다.
  static const String clientKey = 'test_ck_E92LAa5PVbJ0xyKmAnPzV7YmpXyJ';
}
