import 'package:cloud_firestore/cloud_firestore.dart';

/// users/{uid}/wallet/current — 코인 잔액. 클라이언트는 읽기만 한다(firestore.rules
/// 참고) — 잔액은 오직 confirmCoinCharge Cloud Function(Admin SDK, 규칙을
/// 우회해서 쓴다)만 바꾼다. 화면은 항상 이 스트림을 구독해서 보여줘야 한다 —
/// 결제 성공했다고 클라이언트가 잔액을 직접 더하면 서버 값과 어긋날 수 있다.
class WalletRepository {
  WalletRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _walletDoc(String uid) =>
      _firestore.collection('users').doc(uid).collection('wallet').doc('current');

  /// 아직 한 번도 충전한 적 없는 유저는 문서 자체가 없다 — 그 경우 0으로
  /// 취급한다.
  Stream<int> watchBalance(String uid) {
    return _walletDoc(uid).snapshots().map(
      (snapshot) => (snapshot.data()?['balance'] as num?)?.toInt() ?? 0,
    );
  }
}
