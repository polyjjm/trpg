import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/story_pack.dart';

/// 독자 라이브러리(홈 탭)에 보일 스토리팩을 storyPacks Firestore 컬렉션에서
/// 읽어온다. 작가 편집기(lib/admin/)가 쓰는 컬렉션과 같은 문서를 읽지만,
/// 리더는 오직 "연재 시작 승인을 받았고, 발행된 노드가 최소 1개 있는" 팩만
/// 봐야 한다 — 승인만 받고 아직 첫 노드를 안 쓴 팩까지 보이면 빈 서가처럼
/// 어색하다(FIRESTORE_SCHEMA.md의 storyPacks "독자 라이브러리 노출 조건" 참고).
///
/// 표시 필드는 항상 liveMetadata(마지막으로 승인된 스냅샷)에서 읽는다 —
/// 팩 문서의 top-level title/genres/description/coverImageId는 작가가 "지금
/// 편집 중인" 값이라 아직 승인 안 된 변경이 섞여 있을 수 있다.
class StoryPackRepository {
  StoryPackRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<StoryPack>> watchVisiblePacks() {
    return _firestore
        .collection('storyPacks')
        .where('serializationStatus', isEqualTo: 'approved')
        .snapshots()
        .asyncMap(_toVisiblePacks);
  }

  Future<List<StoryPack>> _toVisiblePacks(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (snapshot.docs.isEmpty) return const [];

    final publishedNodeCounts = await _fetchPublishedNodeCounts();
    final candidates = snapshot.docs
        .where(
          (doc) =>
              publishedNodeCounts.containsKey(doc.id) &&
              // admin이 강제로 내린 팩(lib/admin/models/admin_story_pack.dart의
              // suspended 문서 참고) — serializationStatus == approved라도
              // 여기서 걸러낸다. 이미 불러온 스냅샷에 대한 클라이언트 필터라
              // 새 색인이 필요 없다(publishedNodeCounts 필터와 같은 방식).
              doc.data()['suspended'] != true,
        )
        .toList();
    if (candidates.isEmpty) return const [];

    final coverImageIds = candidates
        .map(
          (doc) =>
              (doc.data()['liveMetadata']
                      as Map<String, dynamic>?)?['coverImageId']
                  as String?,
        )
        .whereType<String>()
        .toSet();
    final coverUrls = await _fetchImageUrls(coverImageIds);

    return candidates.map((doc) {
      final data = doc.data();
      final live = data['liveMetadata'] as Map<String, dynamic>?;
      final coverImageId = live?['coverImageId'] as String?;
      return StoryPack(
        id: doc.id,
        title:
            live?['title'] as String? ?? data['title'] as String? ?? '(제목 없음)',
        description: live?['description'] as String? ?? '',
        authorName: data['authorName'] as String? ?? '알 수 없음',
        coverImageUrl: coverImageId != null ? coverUrls[coverImageId] : null,
        price: (live?['price'] as num?)?.toInt() ?? 0,
        salePrice: (live?['salePrice'] as num?)?.toInt(),
        discountStartAt: (live?['discountStartAt'] as Timestamp?)?.toDate(),
        discountEndAt: (live?['discountEndAt'] as Timestamp?)?.toDate(),
        format: (data['type'] as String?) == 'linear'
            ? StoryPackFormat.linear
            : StoryPackFormat.interactive,
        genres: (live?['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
        defaultBackgroundImage: data['defaultBackgroundImage'] as String?,
        defaultBgmId: live?['defaultBgmId'] as String?,
        avgRating: (data['avgRating'] as num?)?.toDouble(),
        reviewCount: (data['reviewCount'] as num?)?.toInt() ?? 0,
        publishedNodeCount: publishedNodeCounts[doc.id] ?? 0,
      );
    }).toList();
  }

  /// 팩이 "발행된 노드가 최소 1개 있는지"(키가 있는지)와 "몇 개나 있는지"
  /// (값)를 collectionGroup 조회 한 번으로 같이 구한다 — 팩마다 nodes
  /// 서브컬렉션을 따로 조회하지 않는다. 개수는 StoryPack.publishedNodeCount로
  /// 그대로 흘려보내 내 서재 탭의 진행률 바 계산에 쓴다.
  /// id 목록으로 팩을 직접 조회한다 — [watchVisiblePacks]처럼 라이브러리
  /// 노출 조건(연재 승인 + 발행 노드 존재)을 따지지 않고, 표지/제목만 필요한
  /// 가벼운 표시용 자리(번들 카드가 포함된 팩을 나열할 때)에 쓴다. 그래서
  /// avgRating/publishedNodeCount 등 이 자리에서 안 쓰는 필드는 기본값으로
  /// 채운다. 최대 30개(Firestore whereIn 제한) — 번들 하나에 담기는 팩
  /// 개수가 이보다 많을 일은 없다고 본다.
  Future<List<StoryPack>> fetchPacksByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final snapshot = await _firestore
        .collection('storyPacks')
        .where(FieldPath.documentId, whereIn: ids)
        .get();
    if (snapshot.docs.isEmpty) return const [];

    final coverImageIds = snapshot.docs
        .map(
          (doc) =>
              (doc.data()['liveMetadata']
                      as Map<String, dynamic>?)?['coverImageId']
                  as String?,
        )
        .whereType<String>()
        .toSet();
    final coverUrls = await _fetchImageUrls(coverImageIds);

    return snapshot.docs.map((doc) {
      final data = doc.data();
      final live = data['liveMetadata'] as Map<String, dynamic>?;
      final coverImageId = live?['coverImageId'] as String?;
      return StoryPack(
        id: doc.id,
        title:
            live?['title'] as String? ?? data['title'] as String? ?? '(제목 없음)',
        description: live?['description'] as String? ?? '',
        authorName: data['authorName'] as String? ?? '알 수 없음',
        coverImageUrl: coverImageId != null ? coverUrls[coverImageId] : null,
        price: (live?['price'] as num?)?.toInt() ?? 0,
        salePrice: (live?['salePrice'] as num?)?.toInt(),
        discountStartAt: (live?['discountStartAt'] as Timestamp?)?.toDate(),
        discountEndAt: (live?['discountEndAt'] as Timestamp?)?.toDate(),
        format: (data['type'] as String?) == 'linear'
            ? StoryPackFormat.linear
            : StoryPackFormat.interactive,
        genres: (live?['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
      );
    }).toList();
  }

  Future<Map<String, int>> _fetchPublishedNodeCounts() async {
    final snapshot = await _firestore
        .collectionGroup('nodes')
        .where('status', isEqualTo: 'published')
        .get();
    final counts = <String, int>{};
    for (final doc in snapshot.docs) {
      final packId = doc.reference.parent.parent!.id;
      counts[packId] = (counts[packId] ?? 0) + 1;
    }
    return counts;
  }

  Future<Map<String, String>> _fetchImageUrls(Set<String> imageIds) async {
    if (imageIds.isEmpty) return {};
    final snapshot = await _firestore
        .collection('images')
        .where(FieldPath.documentId, whereIn: imageIds.toList())
        .get();
    return {
      for (final doc in snapshot.docs)
        doc.id: doc.data()['url'] as String? ?? '',
    };
  }
}
