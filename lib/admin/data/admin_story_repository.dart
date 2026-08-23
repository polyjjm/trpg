import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/pack_serialization_status.dart';
import '../models/pending_action.dart';
import '../models/pending_node_ref.dart';
import '../models/story_pack_type.dart';

/// storyPacks의 팩 메타데이터와 노드 draft/live 저장소를 다룬다.
///
/// 노드 콘텐츠는 두 컬렉션으로 분리한다.
/// - draftNodes: 작가가 편집 중인 전체 문서 + 승인 상태/반려 사유
/// - nodes: 마지막 승인된 liveSnapshot과 서버 캐시(TTS 등), reader-facing 호환 문서
///
/// 작가의 임시저장은 draftNodes만 갱신하고, admin 승인 시에만 nodes가 바뀐다.
/// 따라서 이미 발행된 노드를 수정하는 동안 미승인 초안이 reader-facing
/// nodes 문서에 덮어써지는 구조적 누출을 끊는다.
class AdminStoryRepository {
  AdminStoryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _packs =>
      _firestore.collection('storyPacks');

  /// reader/TTS가 보는 승인본 호환 컬렉션.
  CollectionReference<Map<String, dynamic>> _nodes(String packId) =>
      _packs.doc(packId).collection('nodes');

  /// author/admin editor가 보는 편집본 컬렉션.
  CollectionReference<Map<String, dynamic>> _draftNodes(String packId) =>
      _packs.doc(packId).collection('draftNodes');

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

  Stream<AdminStoryPack?> watchPack(String packId) {
    return _packs.doc(packId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return AdminStoryPack.fromFirestore(doc.id, data);
    });
  }

  Future<void> saveDraftPackSettings(
    String packId, {
    required String title,
    required List<String> genres,
    required String description,
    required String? coverImageId,
    required int price,
    required int? salePrice,
    required DateTime? discountStartAt,
    required DateTime? discountEndAt,
    required String? defaultBackgroundImage,
    required String? defaultBgmId,
    required String? defaultTtsVoiceId,
  }) async {
    await _packs.doc(packId).update({
      'title': title,
      'genres': genres,
      'description': description,
      'coverImageId': coverImageId,
      'price': price,
      'salePrice': salePrice,
      'discountStartAt': discountStartAt != null
          ? Timestamp.fromDate(discountStartAt)
          : null,
      'discountEndAt': discountEndAt != null
          ? Timestamp.fromDate(discountEndAt)
          : null,
      'defaultBackgroundImage': defaultBackgroundImage,
      'defaultBgmId': defaultBgmId,
      'defaultTtsVoiceId': defaultTtsVoiceId,
    });
  }

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

  Future<void> approveSerialization(
    AdminStoryPack pack, {
    required String reviewerUid,
  }) async {
    final payload = {
      'serializationStatus': PackSerializationStatus.approved.wireValue,
      'serializationReviewedBy': reviewerUid,
      'serializationReviewedAt': FieldValue.serverTimestamp(),
      'serializationRejectionReason': null,
      'liveMetadata': _metadataSnapshot(pack),
    };
    debugPrint('approveSerialization(${pack.id}) payload: $payload');
    try {
      await _packs.doc(pack.id).update(payload);
      debugPrint('approveSerialization(${pack.id}) 성공');
    } catch (e, stackTrace) {
      debugPrint('approveSerialization(${pack.id}) 실패: $e\n$stackTrace');
      rethrow;
    }
  }

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

  Future<void> requestMetadataEdit(
    String packId, {
    required String title,
    required List<String> genres,
    required String description,
    required String? coverImageId,
    required int price,
    required int? salePrice,
    required DateTime? discountStartAt,
    required DateTime? discountEndAt,
    required String? defaultBgmId,
    required String? defaultTtsVoiceId,
  }) async {
    await _packs.doc(packId).update({
      'title': title,
      'genres': genres,
      'description': description,
      'coverImageId': coverImageId,
      'price': price,
      'salePrice': salePrice,
      'discountStartAt': discountStartAt != null
          ? Timestamp.fromDate(discountStartAt)
          : null,
      'discountEndAt': discountEndAt != null
          ? Timestamp.fromDate(discountEndAt)
          : null,
      'defaultBgmId': defaultBgmId,
      'defaultTtsVoiceId': defaultTtsVoiceId,
      'pendingMetadataAction': 'edit',
      'metadataSubmittedAt': FieldValue.serverTimestamp(),
      'metadataRejectionReason': null,
    });
  }

  Future<void> approveMetadataEdit(
    AdminStoryPack pack, {
    required String reviewerUid,
  }) async {
    final payload = {
      'pendingMetadataAction': null,
      'metadataReviewedBy': reviewerUid,
      'metadataReviewedAt': FieldValue.serverTimestamp(),
      'metadataRejectionReason': null,
      'liveMetadata': _metadataSnapshot(pack),
    };
    debugPrint('approveMetadataEdit(${pack.id}) payload: $payload');
    debugPrint(
      'approveMetadataEdit(${pack.id}) pack 스냅샷: '
      'price=${pack.price} salePrice=${pack.salePrice} '
      'discountStartAt=${pack.discountStartAt} discountEndAt=${pack.discountEndAt} '
      'title=${pack.title} genres=${pack.genres} coverImageId=${pack.coverImageId}',
    );
    try {
      await _packs.doc(pack.id).update(payload);
      debugPrint('approveMetadataEdit(${pack.id}) 성공');
    } catch (e, stackTrace) {
      debugPrint('approveMetadataEdit(${pack.id}) 실패: $e\n$stackTrace');
      rethrow;
    }
  }

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

  Future<void> suspendPack(
    AdminStoryPack pack, {
    required String reviewerUid,
    required String reason,
  }) async {
    await _packs.doc(pack.id).update({
      'suspended': true,
      'suspendedReason': reason,
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspendedBy': reviewerUid,
    });
  }

  Future<void> unsuspendPack(AdminStoryPack pack) async {
    await _packs.doc(pack.id).update({'suspended': false});
  }

  Future<void> suspendPacksForAuthor(
    String authorId, {
    required String reviewerUid,
    required String reason,
  }) async {
    final snapshot = await _packs.where('authorId', isEqualTo: authorId).get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'suspended': true,
        'suspendedReason': reason,
        'suspendedAt': FieldValue.serverTimestamp(),
        'suspendedBy': reviewerUid,
      });
    }
    await batch.commit();
  }

  Map<String, dynamic> _metadataSnapshot(AdminStoryPack pack) => {
    'title': pack.title,
    'genres': pack.genres,
    'description': pack.description,
    'coverImageId': pack.coverImageId,
    'price': pack.price,
    'salePrice': pack.salePrice,
    'discountStartAt': pack.discountStartAt != null
        ? Timestamp.fromDate(pack.discountStartAt!)
        : null,
    'discountEndAt': pack.discountEndAt != null
        ? Timestamp.fromDate(pack.discountEndAt!)
        : null,
    'defaultBgmId': pack.defaultBgmId,
    'defaultTtsVoiceId': pack.defaultTtsVoiceId,
  };

  /// 편집기/관리자 대기함은 reader-facing nodes가 아니라 draftNodes를 본다.
  Stream<List<AdminStoryNodeSummary>> watchNodeSummaries(String packId) {
    return _draftNodes(packId).snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => AdminStoryNodeSummary.fromFirestore(doc.id, doc.data()))
          .toList(),
    );
  }

  /// 마이그레이션 직후 혹은 백필 전 개발 환경을 위해 draftNodes가 없으면
  /// 기존 nodes를 fallback으로 읽는다. 저장하는 순간부터 draftNodes가 생긴다.
  Future<AdminStoryNode?> fetchNode(String packId, String nodeId) async {
    final draft = await _draftNodes(packId).doc(nodeId).get();
    final draftData = draft.data();
    if (draftData != null) {
      return AdminStoryNode.fromFirestore(draft.id, draftData);
    }

    final legacy = await _nodes(packId).doc(nodeId).get();
    final legacyData = legacy.data();
    if (legacyData == null) return null;
    return AdminStoryNode.fromFirestore(legacy.id, legacyData);
  }

  /// 임시저장/승인요청은 draftNodes만 갱신한다. 이미 공개 중인 nodes는
  /// approveNode가 실행되기 전까지 전혀 변경되지 않는다.
  Future<void> saveNode(String packId, AdminStoryNode node) async {
    await _draftNodes(packId).doc(node.id).set(node.toFirestoreJson());
  }

  Future<void> saveNodesBatch(String packId, List<AdminStoryNode> nodes) async {
    final batch = _firestore.batch();
    for (final node in nodes) {
      batch.set(_draftNodes(packId).doc(node.id), node.toFirestoreJson());
    }
    await batch.commit();
  }

  Future<void> stampApprovalRequestedAt(String packId, String nodeId) async {
    await _draftNodes(
      packId,
    ).doc(nodeId).update({'approvalRequestedAt': FieldValue.serverTimestamp()});
  }

  /// 한 번도 발행되지 않은 순수 초안은 draft 문서만 지운다.
  Future<void> deleteNodeDoc(String packId, String nodeId) async {
    await _draftNodes(packId).doc(nodeId).delete();
  }

  Stream<List<PendingNodeRef>> watchPendingNodes() {
    return _firestore
        .collectionGroup('draftNodes')
        .where('pendingAction', whereIn: ['create', 'edit', 'delete'])
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final packId = doc.reference.parent.parent!.id;
            final data = doc.data();
            return PendingNodeRef(
              packId: packId,
              node: AdminStoryNode.fromFirestore(doc.id, data),
              requestedAt: PendingNodeRef.requestedAtFrom(data),
            );
          }).toList(),
        );
  }

  /// 승인만 live 문서를 갱신한다. draft와 live를 같은 batch로 바꿔 중간 상태가
  /// 남지 않게 한다. live 쪽은 merge로 써서 TTS 서버 캐시 필드를 보존한다.
  Future<void> approveNode(String packId, AdminStoryNode node) async {
    final draftRef = _draftNodes(packId).doc(node.id);
    final liveRef = _nodes(packId).doc(node.id);
    final batch = _firestore.batch();

    if (node.pendingAction == PendingAction.delete) {
      batch.delete(draftRef);
      batch.delete(liveRef);
      await batch.commit();
      return;
    }

    final liveSnapshot = node.contentSnapshot();
    batch.set(
      liveRef,
      {
        'status': 'published',
        'liveSnapshot': liveSnapshot,
        'pendingAction': null,
        'rejectionReason': null,
      },
      SetOptions(merge: true),
    );
    batch.update(draftRef, {
      'liveSnapshot': liveSnapshot,
      'status': 'published',
      'pendingAction': null,
      'rejectionReason': null,
    });
    await batch.commit();
  }

  /// 반려는 draft 상태만 바꾼다. 기존 live 문서는 절대 건드리지 않는다.
  /// 이미 발행된 노드의 수정 반려라면 editor 상태는 published를 유지하고,
  /// 신규 등록 반려만 draft로 돌아간다.
  Future<void> rejectNode(
    String packId,
    AdminStoryNode node, {
    required String reason,
  }) async {
    final draftRef = _draftNodes(packId).doc(node.id);
    if (node.pendingAction == PendingAction.delete) {
      await draftRef.update({
        'pendingAction': null,
        'rejectionReason': reason,
      });
      return;
    }

    await draftRef.update({
      'status': node.liveSnapshot == null ? 'draft' : 'published',
      'pendingAction': null,
      'rejectionReason': reason,
    });
  }
}

class PackRequestSerializationError implements Exception {
  final String message;

  const PackRequestSerializationError(this.message);

  @override
  String toString() => message;
}
