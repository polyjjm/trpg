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
  /// defaultBgmId/defaultTtsVoiceId는 반대다 — title/genres 등과 완전히
  /// 같은 대우로 liveMetadata 게이트를 그대로 거친다(admin_story_pack.dart의
  /// AdminStoryPack.defaultBgmId/defaultTtsVoiceId doc 참고) — 여기서
  /// top-level 필드로 즉시 저장하는 건 다른 draft 필드와 똑같이
  /// "임시저장"일 뿐이고, 독자에게 실제로 반영되려면 아래
  /// [requestMetadataEdit]/[approveMetadataEdit]을 거쳐야 한다.
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

  /// 강제 내리기 — [AdminStoryPack.suspended] 문서 참고: serializationStatus/
  /// liveMetadata와 완전히 독립된 게이트라 이 필드들은 건드리지 않는다.
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

  /// 복원 — suspended만 false로 되돌리고 suspendedReason/At/By는 그대로
  /// 남긴다. 지워버리면 "이 팩이 예전에 왜/언제/누가 내렸었는지"를 나중에
  /// 되짚을 방법이 없어진다 — 마지막 내림 기록으로 남겨 두는 편이 admin이
  /// 팩 이력을 살필 때 더 쓸모 있다는 판단.
  Future<void> unsuspendPack(AdminStoryPack pack) async {
    await _packs.doc(pack.id).update({'suspended': false});
  }

  /// 작가 자격 회수/계정 정지에서 "작품도 함께 비공개 처리" 체크를 했을 때
  /// 쓴다 — 그 작가의 모든 팩을 한 배치로 강제 내린다. 이미 suspended인
  /// 팩도 그냥 다시 덮어쓴다(사유/시각만 최신으로 갱신될 뿐이라 해가 없다).
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
      // PR #1의 수정을 draft/live 분리 이후에도 그대로 유지한다 — 한 번도
      // 승인된 적 없는 신규 노드만 draft로 되돌리고, 이미 liveSnapshot이 있는
      // 수정 요청은 published를 유지한다.
      //
      // 분리 전에는 이 값이 리더가 보는 문서에 그대로 쓰여서, draft로
      // 되돌리면 `status == 'published'` 쿼리에서 빠져 **이미 공개된 화가
      // 독자에게서 사라지는** 실제 장애였다. 지금은 live 문서를 아예 안
      // 건드리므로 독자에게는 영향이 없지만, 이 값은 여전히 편집기의 상태
      // 표시(watchNodeSummaries는 draftNodes를 본다)와 다음 승인 요청의
      // 기준이 되므로 똑같이 유지해야 한다 — 이미 연재 중인 노드를 "미발행"
      // 으로 보여주면 작가가 상태를 오해한다.
      'status': node.liveSnapshot == null ? 'draft' : 'published',
      'pendingAction': null,
      'rejectionReason': reason,
    });
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