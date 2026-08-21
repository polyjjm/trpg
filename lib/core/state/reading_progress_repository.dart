import 'package:cloud_firestore/cloud_firestore.dart';

import 'reading_progress.dart';

/// [ReadingProgress]를 Firestore의 users/{uid}/readingProgress/{packId}
/// 문서에 저장·불러온다 — CloudSaveService가 users/{uid}/save/current를
/// 다루는 것과 같은 경계(모델 자체는 Firestore를 모르고, 이 클래스가
/// 직렬화를 전담한다). save/current 문서 하나에 모든 팩의 진행 상황을
/// 욱여넣지 않고 팩마다 별도 문서를 쓰는 이유는 CLAUDE.md에 적힌 그대로다 —
/// 한 팩을 읽다 다른 팩을 열었다 돌아와도 서로의 위치가 안 섞여야 한다.
class ReadingProgressRepository {
  ReadingProgressRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _docFor(String uid, String packId) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('readingProgress')
          .doc(packId);

  Future<void> save(String uid, String packId, ReadingProgress progress) async {
    await _docFor(uid, packId).set({
      'currentNodeId': progress.currentNodeId,
      'visitedNodeCount': progress.visitedNodeCount,
      'completed': progress.completed,
      'lastReadAt': FieldValue.serverTimestamp(),
    });
  }

  /// 저장된 진행 상황이 없으면 null을 반환한다(이 팩을 아직 한 번도 안 읽은
  /// 경우 — 신규 유저이거나, 로그인 전에는 게스트로만 읽었던 경우).
  Future<ReadingProgress?> load(String uid, String packId) async {
    final snapshot = await _docFor(uid, packId).get();
    final data = snapshot.data();
    if (data == null) return null;

    final currentNodeId = data['currentNodeId'] as String?;
    if (currentNodeId == null) return null;

    final lastReadAtRaw = data['lastReadAt'];
    return ReadingProgress(
      currentNodeId: currentNodeId,
      visitedNodeCount: (data['visitedNodeCount'] as num?)?.toInt() ?? 0,
      lastReadAt: lastReadAtRaw is Timestamp ? lastReadAtRaw.toDate() : null,
      completed: data['completed'] as bool? ?? false,
    );
  }
}
