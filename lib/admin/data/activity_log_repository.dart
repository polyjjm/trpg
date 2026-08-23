import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/activity_event.dart';

/// activityLog 컬렉션 — 관리자 개요 "최근 활동" 카드의 유일한 소스.
///
/// Cloud Functions 트리거가 아니라 **관리자 클라이언트가 직접 쓴다**. 기록
/// 대상인 승인/반려/상품 수정/배너 게시가 전부 이미 admin 클라이언트에서
/// 일어나는 쓰기라, 같은 동작을 서버에서 다시 감지할 이유가 없다(트리거를
/// 늘리면 배포 대상만 늘고 지연도 붙는다).
///
/// 그래서 [log]는 **절대 예외를 위로 던지지 않는다** — 로그 쓰기가 실패해도
/// 원래 하려던 승인/반려는 이미 끝났거나 끝나야 하는 일이다. 타임라인 한
/// 줄이 빠지는 것과 승인이 실패한 것처럼 보이는 것 중에서는 전자가 낫다.
class ActivityLogRepository {
  ActivityLogRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('activityLog');

  Future<void> log({
    required ActivityKind kind,
    required String message,
    String? actorUid,
  }) async {
    try {
      await _collection.add({
        'kind': kind.wireValue,
        'message': message,
        'actorUid': actorUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('activityLog 기록 실패(무시): $e');
    }
  }

  /// 최근 활동 [limit]건. createdAt 단일 필드 정렬이라 복합 색인이 필요 없다
  /// (색인 파일에는 그래도 명시해 둔다 — patches/firestore.indexes.patch.json 참고).
  Stream<List<ActivityEvent>> watchRecent({int limit = 6}) {
    return _collection
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ActivityEvent.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }
}
