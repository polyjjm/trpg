import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/story/background_image_inheritance.dart';
import '../models/story_node.dart';

/// [StoryNode] + 배경 인계 규칙까지 적용해 이미 URL로 resolve된 배경 이미지 —
/// SceneFrame은 imageId를 모르므로(images 컬렉션 join은 이 리포지토리 선에서
/// 끝낸다) 리더가 바로 SceneFrame에 꽂아 넣을 수 있는 형태.
class ResolvedStoryNode {
  final StoryNode node;
  final String? backgroundImageUrl;

  const ResolvedStoryNode({required this.node, required this.backgroundImageUrl});
}

/// storyPacks/{packId}/nodes에서 리더가 실제로 보여줄 콘텐츠를 읽어온다.
///
/// 노드 문서는 "지금 편집 중인" top-level 필드와 "마지막으로 승인된" liveSnapshot
/// 을 동시에 들고 있다(admin_story_node.dart 참고) — 팩의 liveMetadata와 같은
/// 이유로, 리더는 반드시 liveSnapshot만 읽는다. top-level 필드를 읽으면 아직
/// 승인 안 된 수정 중인 내용이 새어 나갈 수 있다.
class StoryReaderRepository {
  StoryReaderRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _nodes(String packId) =>
      _firestore.collection('storyPacks').doc(packId).collection('nodes');

  /// 발행된(published) 노드만, order 오름차순으로 정렬해 반환한다.
  /// [packDefaultBackgroundImageId]는 이 팩의 storyPacks.defaultBackgroundImage —
  /// 어떤 노드도 배경을 명시적으로 고르지 않았을 때의 최종 폴백이다.
  Future<List<ResolvedStoryNode>> fetchPublishedNodes(
    String packId, {
    String? packDefaultBackgroundImageId,
  }) async {
    final snapshot = await _nodes(packId).where('status', isEqualTo: 'published').get();

    final nodes = <StoryNode>[];
    for (final doc in snapshot.docs) {
      final liveSnapshot = doc.data()['liveSnapshot'] as Map<String, dynamic>?;
      // status == 'published'인데 승인 스냅샷이 없는 건 있을 수 없는 상태다 —
      // watchVisiblePacks()의 이중 체크와 같은 이유의 방어적 스킵.
      if (liveSnapshot == null) continue;
      nodes.add(StoryNode.fromFirestore(doc.id, liveSnapshot));
    }
    nodes.sort((a, b) => a.order.compareTo(b.order));

    final imageIds = <String>{
      ...nodes.map((n) => n.backgroundImage).whereType<String>(),
      ?packDefaultBackgroundImageId,
    };
    final imageUrls = await _fetchImageUrls(imageIds);

    return [
      for (final node in nodes)
        ResolvedStoryNode(
          node: node,
          backgroundImageUrl: imageUrls[node.backgroundImage ??
              resolveInheritedBackgroundImage(
                nodes: nodes.map((n) => (
                      order: n.order,
                      backgroundImage: n.backgroundImage,
                      backgroundAppliesForward: n.backgroundAppliesForward,
                    )),
                targetOrder: node.order,
                packDefaultBackgroundImage: packDefaultBackgroundImageId,
              )],
        ),
    ];
  }

  Future<Map<String, String>> _fetchImageUrls(Set<String> imageIds) async {
    if (imageIds.isEmpty) return {};
    final snapshot =
        await _firestore.collection('images').where(FieldPath.documentId, whereIn: imageIds.toList()).get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()['url'] as String? ?? ''};
  }
}
