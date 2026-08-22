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

  /// ⚠️ merge:true로 쓴다 — [ReaderPrefs.toFirestore]는 일부러
  /// lastNoticeReadAt을 안 담는다(모델 주석 참고). merge 없이 그냥
  /// set()하면 이 문서를 통째로 덮어써서, 폰트/애니메이션 같은 설정을
  /// 바꿀 때마다 markNoticesRead()가 써 둔 lastNoticeReadAt이 조용히
  /// 지워지는 실제 버그가 생긴다.
  Future<void> save(String uid, ReaderPrefs prefs) async {
    await _docFor(uid).set(prefs.toFirestore(), SetOptions(merge: true));
  }

  /// 공지사항 탭을 열 때 CatalogShellPage가 부른다 — lastNoticeReadAt만
  /// 서버 타임스탬프로 갱신한다(다른 필드는 안 건드린다).
  Future<void> markNoticesRead(String uid) async {
    await _docFor(uid).set(
      {'lastNoticeReadAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
