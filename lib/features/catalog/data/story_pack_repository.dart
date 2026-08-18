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
  StoryPackRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<StoryPack>> watchVisiblePacks() {
    return _firestore
        .collection('storyPacks')
        .where('serializationStatus', isEqualTo: 'approved')
        .snapshots()
        .asyncMap(_toVisiblePacks);
  }

  Future<List<StoryPack>> _toVisiblePacks(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    if (snapshot.docs.isEmpty) return const [];

    final publishedPackIds = await _fetchPackIdsWithPublishedNode();
    final candidates = snapshot.docs.where((doc) => publishedPackIds.contains(doc.id)).toList();
    if (candidates.isEmpty) return const [];

    final coverImageIds = candidates
        .map((doc) => (doc.data()['liveMetadata'] as Map<String, dynamic>?)?['coverImageId'] as String?)
        .whereType<String>()
        .toSet();
    final coverUrls = await _fetchImageUrls(coverImageIds);

    return candidates.map((doc) {
      final data = doc.data();
      final live = data['liveMetadata'] as Map<String, dynamic>?;
      final coverImageId = live?['coverImageId'] as String?;
      return StoryPack(
        id: doc.id,
        title: live?['title'] as String? ?? data['title'] as String? ?? '(제목 없음)',
        description: live?['description'] as String? ?? '',
        authorName: data['authorName'] as String? ?? '알 수 없음',
        coverImageUrl: coverImageId != null ? coverUrls[coverImageId] : null,
        price: 0,
        format: (data['type'] as String?) == 'linear' ? StoryPackFormat.linear : StoryPackFormat.interactive,
        genres: (live?['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
        ttsEnabled: data['ttsEnabled'] as bool? ?? false,
        ambientBgm: data['ambientBgm'] as String?,
        defaultBackgroundImage: data['defaultBackgroundImage'] as String?,
      );
    }).toList();
  }

  /// 팩이 "발행된 노드가 최소 1개 있는지"는 collectionGroup 조회로 한 번에
  /// 구한다 — 팩마다 nodes 서브컬렉션을 따로 조회하지 않는다.
  Future<Set<String>> _fetchPackIdsWithPublishedNode() async {
    final snapshot = await _firestore.collectionGroup('nodes').where('status', isEqualTo: 'published').get();
    return snapshot.docs.map((doc) => doc.reference.parent.parent!.id).toSet();
  }

  Future<Map<String, String>> _fetchImageUrls(Set<String> imageIds) async {
    if (imageIds.isEmpty) return {};
    final snapshot =
        await _firestore.collection('images').where(FieldPath.documentId, whereIn: imageIds.toList()).get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()['url'] as String? ?? ''};
  }
}
