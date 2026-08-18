import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reader_prefs.dart';

/// users/{uid}/readerPrefs/settings 문서 — 게임 세이브(users/{uid}/save/current,
/// CloudSaveService)와 같은 "단일 고정 문서 id" 패턴을 그대로 따른다. 계정에
/// 묶인 리더 환경설정이라 기기별로 나뉘지 않는다.
class ReaderPrefsRepository {
  ReaderPrefsRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _docFor(String uid) =>
      _firestore.collection('users').doc(uid).collection('readerPrefs').doc('settings');

  /// 문서가 아직 없으면(최초 진입) [ReaderPrefs.defaults]를 흘려보낸다.
  Stream<ReaderPrefs> watch(String uid) {
    return _docFor(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? ReaderPrefs.defaults : ReaderPrefs.fromFirestore(data);
    });
  }

  Future<void> save(String uid, ReaderPrefs prefs) async {
    await _docFor(uid).set(prefs.toFirestore());
  }
}
