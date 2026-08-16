import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/pending_action.dart';
import '../models/pending_node_ref.dart';
import '../models/story_pack_type.dart';

/// storyPacks / storyPacks/{packId}/nodes 컬렉션을 다루는 저장소.
///
/// 승인 전(draft, pendingAction 대기 중) 콘텐츠까지 그대로 문서에 들어있고,
/// 게임 클라이언트는 이 문서를 직접 읽지 않는다(아직은 데이터 마이그레이션 전
/// 단계라 게임은 여전히 하드코딩된 story_nodes.dart를 쓴다) — 이 저장소는
/// 편집기 전용이다.
class AdminStoryRepository {
  AdminStoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _packs =>
      _firestore.collection('storyPacks');

  CollectionReference<Map<String, dynamic>> _nodes(String packId) =>
      _packs.doc(packId).collection('nodes');

  /// 모든 스토리팩(작가 구분 없이) — admin 시점 목록.
  Stream<List<AdminStoryPack>> watchPacks() {
    return _packs.orderBy('title').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminStoryPack.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 특정 작가 소유의 스토리팩만 — author 시점 목록. authorId 동등 필터 +
  /// title 정렬 조합이라 복합 색인 없이도 동작한다.
  Stream<List<AdminStoryPack>> watchPacksForAuthor(String authorId) {
    return _packs.where('authorId', isEqualTo: authorId).orderBy('title').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminStoryPack.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<AdminStoryPack> createPack({
    required String title,
    required String authorId,
    required StoryPackType type,
    required List<String> genres,
  }) async {
    final pack = AdminStoryPack(id: '', title: title, authorId: authorId, type: type, genres: genres);
    final doc = await _packs.add(pack.toJson());
    return AdminStoryPack(id: doc.id, title: title, authorId: authorId, type: type, genres: genres);
  }

  Stream<List<AdminStoryNodeSummary>> watchNodeSummaries(String packId) {
    return _nodes(packId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminStoryNodeSummary.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<AdminStoryNode?> fetchNode(String packId, String nodeId) async {
    final doc = await _nodes(packId).doc(nodeId).get();
    final data = doc.data();
    if (data == null) return null;
    return AdminStoryNode.fromFirestore(doc.id, data);
  }

  /// 노드를 통째로 덮어쓴다 — 신규 생성과 임시저장/승인요청 모두 이 메서드
  /// 하나로 처리한다(문서 전체가 항상 로컬 편집 상태를 그대로 반영하기 때문에
  /// 부분 업데이트보다 전체 set이 더 안전하다).
  Future<void> saveNode(String packId, AdminStoryNode node) async {
    await _nodes(packId).doc(node.id).set(node.toFirestoreJson());
  }

  /// 한 번도 발행된 적 없는 순수 초안을 즉시 삭제한다(승인 절차 불필요).
  Future<void> deleteNodeDoc(String packId, String nodeId) async {
    await _nodes(packId).doc(nodeId).delete();
  }

  /// 모든 스토리팩을 통틀어 승인 대기 중인 노드를 감시한다.
  Stream<List<PendingNodeRef>> watchPendingNodes() {
    return _firestore
        .collectionGroup('nodes')
        .where('pendingAction', whereIn: ['create', 'edit', 'delete'])
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final packId = doc.reference.parent.parent!.id;
              return PendingNodeRef(
                packId: packId,
                node: AdminStoryNode.fromFirestore(doc.id, doc.data()),
              );
            }).toList());
  }

  /// 승인: 삭제 요청이면 실제로 문서를 지우고, 등록/수정 요청이면 지금 draft
  /// 내용을 liveSnapshot으로 복사하고 published로 바꾼다.
  Future<void> approveNode(String packId, AdminStoryNode node) async {
    if (node.pendingAction == PendingAction.delete) {
      await deleteNodeDoc(packId, node.id);
      return;
    }

    await _nodes(packId).doc(node.id).update({
      'liveSnapshot': node.contentSnapshot(),
      'status': 'published',
      'pendingAction': null,
    });
  }

  /// 반려: 삭제 요청이면 요청만 취소하고, 등록/수정 요청이면 draft 상태로
  /// 되돌려 작가가 다시 손볼 수 있게 한다 — liveSnapshot(이미 연재 중인 버전)은
  /// 건드리지 않는다.
  Future<void> rejectNode(String packId, AdminStoryNode node) async {
    if (node.pendingAction == PendingAction.delete) {
      await _nodes(packId).doc(node.id).update({'pendingAction': null});
      return;
    }

    await _nodes(packId).doc(node.id).update({
      'status': 'draft',
      'pendingAction': null,
    });
  }
}
