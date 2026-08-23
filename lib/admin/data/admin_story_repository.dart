import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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

  /// 승인 요청 직후 요청 시각을 서버 시계로 찍는다 — saveNode()/
  /// saveNodesBatch() 다음에 제출한 노드마다 부른다.
  ///
  /// 클라이언트 시계를 믿지 않으려고 모델 값이 아니라 serverTimestamp로 쓴다.
  /// 그 다음 스냅샷에서 AdminStoryNode.approvalRequestedAt이 이 값을 읽어
  /// 보존하므로(그 필드의 doc 참고), 이후 임시저장이 값을 지우지 않는다.
  Future<void> stampApprovalRequestedAt(String packId, String nodeId) async {
    await _nodes(
      packId,
    ).doc(nodeId).update({'approvalRequestedAt': FieldValue.serverTimestamp()});
  }

  /// 한 번도 발행된 적 없는 순수 초안을 즉시 삭제한다(승인 절차 불필요).
  Future<void> deleteNodeDoc(String packId, String nodeId) async {
    await _nodes(packId).doc(nodeId).delete();
  }

  /// 모든 스토리팩을 통틀어 승인 대기 중인 노드를 감시한다.
  ///
  /// 관리자 개요의 대기함 미리보기가 "얼마나 오래 기다렸나"로 정렬하므로,
  /// 문서의 approvalRequestedAt을 [PendingNodeRef]에 같이 담아 넘긴다 —
  /// 정렬/표시는 화면 쪽에서 한다(대기 건수가 수백 건대가 되기 전까지는
  /// 서버 정렬 + 복합 색인을 붙일 이유가 없다).
  Stream<List<PendingNodeRef>> watchPendingNodes() {
    return _firestore
        .collectionGroup('nodes')
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

  /// 승인: 삭제 요청이면 실제로 문서를 지우고, 등록/수정 요청이면 지금 draft
  /// 내용을 liveSnapshot으로 복사하고 published로 바꾼다. rejectionReason도
  /// 같이 지운다 — 방어적 처리다(정상 흐름에서는 재제출 시점에 이미
  /// requestApprovalForNode가 지우지만, 혹시 그 경로를 안 거치고 옛 반려
  /// 사유가 남은 채로 승인되는 경우에도 승인된 버전에는 안 남아야 한다).
  ///
  /// approvalRequestedAt은 일부러 지우지 않는다 — "마지막으로 언제 요청됐던
  /// 노드인가"를 나중에 되짚을 수 있어야 하고, pendingAction이 비면 대기함
  /// 목록에서 어차피 빠진다.
  Future<void> approveNode(String packId, AdminStoryNode node) async {
    if (node.pendingAction == PendingAction.delete) {
      await deleteNodeDoc(packId, node.id);
      return;
    }

    await _nodes(packId).doc(node.id).update({
      'liveSnapshot': node.contentSnapshot(),
      'status': 'published',
      'pendingAction': null,
      'rejectionReason': null,
    });
  }

  /// 반려: 삭제 요청이면 요청만 취소하고, 등록/수정 요청이면 draft 상태로
  /// 되돌려 작가가 다시 손볼 수 있게 한다 — liveSnapshot(이미 연재 중인 버전)은
  /// 건드리지 않는다. [reason]을 rejectionReason에 저장해서 작가가 노드
  /// 목록/편집 화면에서 왜 반려됐는지 볼 수 있게 한다(approvals_tab.dart가
  /// 반려 사유 입력을 필수로 강제한다).
  Future<void> rejectNode(
    String packId,
    AdminStoryNode node, {
    required String reason,
  }) async {
    if (node.pendingAction == PendingAction.delete) {
      await _nodes(
        packId,
      ).doc(node.id).update({'pendingAction': null, 'rejectionReason': reason});
      return;
    }

    await _nodes(packId).doc(node.id).update({
      'status': 'draft',
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
