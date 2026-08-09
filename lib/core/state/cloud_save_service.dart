import 'package:cloud_firestore/cloud_firestore.dart';

import 'game_state.dart';

/// [GameState]를 Firestore의 users/{uid}/save/current 문서에 저장·불러온다.
class CloudSaveService {
  CloudSaveService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _saveDocFor(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('save')
      .doc('current');

  Future<void> save(String uid, GameState gameState) async {
    await _saveDocFor(uid).set(gameState.toJson());
  }

  /// 저장된 데이터가 없으면 null을 반환한다.
  Future<Map<String, dynamic>?> load(String uid) async {
    final snapshot = await _saveDocFor(uid).get();
    return snapshot.data();
  }
}
