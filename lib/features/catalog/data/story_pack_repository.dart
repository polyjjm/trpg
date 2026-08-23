import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/story_pack.dart';

/// 독자 라이브러리(홈 탭)에 보일 스토리팩을 storyPacks Firestore 컬렉션에서
/// 읽어온다. 발행 노드 개수는 노드 collectionGroup을 직접 훑지 않고
/// storyPacks.publishedNodeCount 서버 집계값을 사용한다.
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

    final candidates = snapshot.docs
        .where(
          (doc) =>
              ((doc.data()['publishedNodeCount'] as num?)?.toInt() ?? 0) > 0 &&
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
        publishedNodeCount:
            (data['publishedNodeCount'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// id 목록으로 팩을 직접 조회한다. 번들 카드처럼 가벼운 표시용이라
  /// publishedNodeCount는 사용하지 않는다.
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
