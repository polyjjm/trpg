import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/pack_serialization_status.dart';
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
    return _packs
        .orderBy('title')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminStoryPack.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 특정 작가 소유의 스토리팩만 — author 시점 목록. authorId 동등 필터 +
  /// title 정렬 조합이라 복합 색인 없이도 동작한다.
  Stream<List<AdminStoryPack>> watchPacksForAuthor(String authorId) {
    return _packs
        .where('authorId', isEqualTo: authorId)
        .orderBy('title')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminStoryPack.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 장르/설명/표지는 생성 시점엔 받지 않는다 — 생성 직후 PackSettingsPage로
  /// 이동해서 채우고, 거기서 연재 시작 승인을 요청한다.
  Future<AdminStoryPack> createPack({
    required String title,
    required String authorId,
    required String authorName,
    required StoryPackType type,
  }) async {
    final pack = AdminStoryPack(
      id: '',
      title: title,
      authorId: authorId,
      authorName: authorName,
      type: type,
      genres: const [],
      description: '',
      coverImageId: null,
      serializationStatus: PackSerializationStatus.draft,
    );
    final doc = await _packs.add(pack.toJson());
    return AdminStoryPack(
      id: doc.id,
      title: title,
      authorId: authorId,
      authorName: authorName,
      type: type,
      genres: const [],
      description: '',
      coverImageId: null,
      serializationStatus: PackSerializationStatus.draft,
    );
  }

  Future<AdminStoryPack?> fetchPack(String packId) async {
    final doc = await _packs.doc(packId).get();
    final data = doc.data();
    if (data == null) return null;
    return AdminStoryPack.fromFirestore(doc.id, data);
  }

  /// PackSettingsPage처럼 승인/반려 상태(serializationStatus/pendingMetadataAction
  /// 등)를 실시간으로 반영해야 하는 화면용. AdminStoryPack의 title/genres/
  /// description/coverImageId/defaultBackgroundImage는 편집 폼이 별도의 로컬
  /// 컨트롤러/상태로 들고 있고 이 스트림 값을 직접 표시에 쓰지 않는 화면에서만
  /// 안전하다 — NodeEditor처럼 폼 필드가 모델 값을 initialValue로 직접 쓰는
  /// 화면에서는 쓰면 안 된다(타이핑 중인 내용이 스냅샷에 덮어써진다).
  Stream<AdminStoryPack?> watchPack(String packId) {
    return _packs.doc(packId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return AdminStoryPack.fromFirestore(doc.id, data);
    });
  }

  /// 팩 설정을 직접 저장한다("임시저장") — 상태 전이 없이 언제나 가능하다.
  ///
  /// defaultBackgroundImage는 title/genres/description/coverImageId와 달리
  /// liveMetadata 승인 게이트를 거치지 않는다 — 순수 렌더링 기본값이라
  /// 저장하는 즉시 바로 반영된다(검토가 필요한 "콘텐츠"가 아니라는 판단).
  Future<void> saveDraftPackSettings(
    String packId, {
    required String title,
    required List<String> genres,
    required String description,
    required String? coverImageId,
    required String? defaultBackgroundImage,
  }) async {
    await _packs.doc(packId).update({
      'title': title,
      'genres': genres,
      'description': description,
      'coverImageId': coverImageId,
      'defaultBackgroundImage': defaultBackgroundImage,
    });
  }

  /// 연재 시작 승인 요청 — draft/rejected일 때만 의미 있다([AdminStoryPack.canRequestSerialization]).
  ///
  /// 발행된(published) 노드가 최소 1개 있어야 한다 — 관리자가 제목/장르/설명뿐인
  /// 빈 팩이 아니라 실제로 쓰인 콘텐츠를 보고 연재 시작을 판단할 수 있어야
  /// 하기 때문이다. 이 체크는 앱 계층의 보호막일 뿐이다 — Firestore 규칙은
  /// "서브컬렉션에 조건을 만족하는 문서가 하나라도 있는지"를 표현하지 못해서
  /// (특정 경로의 get()/exists()만 가능하다) 규칙으로는 강제할 수 없다. 우회해도
  /// admin이 빈 요청을 보게 될 뿐 보안 구멍은 아니다.
  Future<void> requestSerialization(String packId) async {
    final nodes = await _nodes(packId).get();
    final hasPublishedNode = nodes.docs.any(
      (doc) => doc.data()['status'] == 'published',
    );
    if (!hasPublishedNode) {
      throw const PackRequestSerializationError(
        '연재 시작을 요청하려면 발행된 노드가 최소 1개 있어야 해요.',
      );
    }

    await _packs.doc(packId).update({
      'serializationStatus': PackSerializationStatus.pending.wireValue,
      'serializationSubmittedAt': FieldValue.serverTimestamp(),
      'serializationRejectionReason': null,
    });
  }

  /// 연재 시작 승인 — 처음으로 liveMetadata를 채운다(노드의 첫 승인이
  /// liveSnapshot을 채우는 것과 같은 구조).
  Future<void> approveSerialization(
    AdminStoryPack pack, {
    required String reviewerUid,
  }) async {
    await _packs.doc(pack.id).update({
      'serializationStatus': PackSerializationStatus.approved.wireValue,
      'serializationReviewedBy': reviewerUid,
      'serializationReviewedAt': FieldValue.serverTimestamp(),
      'serializationRejectionReason': null,
      'liveMetadata': _metadataSnapshot(pack),
    });
  }

  /// 반려 — draft/rejected 재신청 때 다시 손볼 수 있도록 작가가 쓴 내용
  /// 자체(title/genres/description/coverImageId)는 건드리지 않는다.
  Future<void> rejectSerialization(
    AdminStoryPack pack, {
    required String reviewerUid,
    String? reason,
  }) async {
    await _packs.doc(pack.id).update({
      'serializationStatus': PackSerializationStatus.rejected.wireValue,
      'serializationReviewedBy': reviewerUid,
      'serializationReviewedAt': FieldValue.serverTimestamp(),
      'serializationRejectionReason': reason,
    });
  }

  /// 대기 중인 연재 시작 요청 전부 — 관리자 검토 탭용.
  Stream<List<AdminStoryPack>> watchPendingSerializationRequests() {
    return _packs
        .where(
          'serializationStatus',
          isEqualTo: PackSerializationStatus.pending.wireValue,
        )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminStoryPack.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 메타데이터 변경 승인 요청 — 이미 연재 중인 팩에서만 의미 있다
  /// ([AdminStoryPack.canRequestMetadataEdit]).
  Future<void> requestMetadataEdit(
    String packId, {
    required String title,
    required List<String> genres,
    required String description,
    required String? coverImageId,
  }) async {
    await _packs.doc(packId).update({
      'title': title,
      'genres': genres,
      'description': description,
      'coverImageId': coverImageId,
      'pendingMetadataAction': 'edit',
      'metadataSubmittedAt': FieldValue.serverTimestamp(),
      'metadataRejectionReason': null,
    });
  }

  Future<void> approveMetadataEdit(
    AdminStoryPack pack, {
    required String reviewerUid,
  }) async {
    await _packs.doc(pack.id).update({
      'pendingMetadataAction': null,
      'metadataReviewedBy': reviewerUid,
      'metadataReviewedAt': FieldValue.serverTimestamp(),
      'metadataRejectionReason': null,
      'liveMetadata': _metadataSnapshot(pack),
    });
  }

  /// 반려 — liveMetadata(마지막 승인 버전)는 그대로 두고, 작가가 요청한
  /// draft 필드도 그대로 남겨서 다시 손볼 수 있게 한다.
  Future<void> rejectMetadataEdit(
    AdminStoryPack pack, {
    required String reviewerUid,
    String? reason,
  }) async {
    await _packs.doc(pack.id).update({
      'pendingMetadataAction': null,
      'metadataReviewedBy': reviewerUid,
      'metadataReviewedAt': FieldValue.serverTimestamp(),
      'metadataRejectionReason': reason,
    });
  }

  /// 대기 중인 메타데이터 변경 요청 전부 — 관리자 검토 탭용.
  Stream<List<AdminStoryPack>> watchPendingMetadataEdits() {
    return _packs
        .where('pendingMetadataAction', isEqualTo: 'edit')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminStoryPack.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Map<String, dynamic> _metadataSnapshot(AdminStoryPack pack) => {
    'title': pack.title,
    'genres': pack.genres,
    'description': pack.description,
    'coverImageId': pack.coverImageId,
  };

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

  /// 일괄 쓰기("한 번에 쓰기", 선형 스토리 페이지 분할)가 여러 노드를 한 번에
  /// 만들 때 쓴다 — saveNode()를 N번 부르는 것과 달리 하나의 배치로 묶여서
  /// 중간에 실패해도 부분 반영되지 않는다.
  Future<void> saveNodesBatch(String packId, List<AdminStoryNode> nodes) async {
    final batch = _firestore.batch();
    for (final node in nodes) {
      batch.set(_nodes(packId).doc(node.id), node.toFirestoreJson());
    }
    await batch.commit();
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
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final packId = doc.reference.parent.parent!.id;
            return PendingNodeRef(
              packId: packId,
              node: AdminStoryNode.fromFirestore(doc.id, doc.data()),
            );
          }).toList(),
        );
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

    await _nodes(
      packId,
    ).doc(node.id).update({'status': 'draft', 'pendingAction': null});
  }
}

/// requestSerialization()이 "발행된 노드가 없다"는 이유로 거부할 때 던지는
/// 예외 — 메시지 자체가 사용자에게 보여줄 수 있는 문장이다.
class PackRequestSerializationError implements Exception {
  final String message;

  const PackRequestSerializationError(this.message);

  @override
  String toString() => message;
}
