import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/story/background_image_inheritance.dart';
import '../models/story_node.dart';

/// [StoryNode] + 배경 인계 규칙까지 적용해 이미 URL로 resolve된 배경 이미지 —
/// SceneFrame은 imageId를 모르므로(images 컬렉션 join은 이 리포지토리 선에서
/// 끝낸다) 리더가 바로 SceneFrame에 꽂아 넣을 수 있는 형태.
class ResolvedStoryNode {
  final StoryNode node;
  final String? backgroundImageUrl;

  /// sfxLibrary/{sfxId}에서 조인한 다운로드 URL — node.sfxId가 있을 때만
  /// 값을 갖는다. SceneFrame은 아직 이 값을 재생하지 않는다(node_effects.dart
  /// 참고) — 지금은 리더가 바로 꽂아 쓸 수 있는 형태로 미리 resolve만 해 둔다.
  final String? sfxUrl;

  /// bgmLibrary/{bgmId}에서 조인한 다운로드 URL — node.effects.bgm?.bgmId가
  /// 있을 때만 값을 갖는다(silence 지시일 땐 bgmId 자체가 없어서 항상 null).
  /// SceneFrame이 아니라 리더 페이지(InteractiveReader/LinearReader)의
  /// BgmSessionController가 이 값을 쓴다 — bgm_session_controller.dart 참고.
  final String? bgmUrl;

  const ResolvedStoryNode({
    required this.node,
    required this.backgroundImageUrl,
    this.sfxUrl,
    this.bgmUrl,
  });
}

/// storyPacks/{packId}/nodes에서 리더가 실제로 보여줄 콘텐츠를 읽어온다.
///
/// 노드 문서는 "지금 편집 중인" top-level 필드와 "마지막으로 승인된" liveSnapshot
/// 을 동시에 들고 있다(admin_story_node.dart 참고) — 팩의 liveMetadata와 같은
/// 이유로, 리더는 반드시 liveSnapshot만 읽는다. top-level 필드를 읽으면 아직
/// 승인 안 된 수정 중인 내용이 새어 나갈 수 있다.
class StoryReaderRepository {
  StoryReaderRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _nodes(String packId) =>
      _firestore.collection('storyPacks').doc(packId).collection('nodes');

  /// 발행된(published) 노드만, order 오름차순으로 정렬해 반환한다.
  /// [packDefaultBackgroundImageId]는 이 팩의 storyPacks.defaultBackgroundImage —
  /// 어떤 노드도 배경을 명시적으로 고르지 않았을 때의 최종 폴백이다.
  /// [packDefaultBgmId]는 storyPacks.defaultBgmId(liveMetadata에서 이미 resolve된
  /// 값 — 호출부인 InteractiveReader/LinearReader가 widget.pack.defaultBgmId를
  /// 그대로 넘긴다) — 반환값의 defaultBgmUrl로 조인된다. 리딩 세션 시작
  /// 시점에 "첫 노드가 BGM을 아예 안 정했을 때"만 쓰인다(bgm_session_controller.dart).
  Future<({List<ResolvedStoryNode> nodes, String? defaultBgmUrl})>
  fetchPublishedNodes(
    String packId, {
    String? packDefaultBackgroundImageId,
    String? packDefaultBgmId,
  }) async {
    // fetchPublishedNodes 안에서 순서대로 nodes/images/sfxLibrary, 세 번
    // 별도로 읽는다 — 어느 쪽에서 permission-denied가 나는지 구분하려고
    // 각 단계 앞뒤에 로그를 남긴다.
    debugPrint('fetchPublishedNodes($packId): nodes 쿼리 시작');
    final snapshot = await _nodes(
      packId,
    ).where('status', isEqualTo: 'published').get();
    debugPrint(
      'fetchPublishedNodes($packId): nodes 쿼리 성공 (${snapshot.docs.length}건)',
    );

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
    debugPrint('fetchPublishedNodes($packId): images 쿼리 시작 ($imageIds)');
    final imageUrls = await _fetchImageUrls(imageIds);
    debugPrint('fetchPublishedNodes($packId): images 쿼리 성공');

    final sfxIds = nodes
        .where((n) => n.effects.sfx.enabled)
        .map((n) => n.effects.sfx.sfxId)
        .whereType<String>()
        .toSet();
    debugPrint('fetchPublishedNodes($packId): sfx 쿼리 시작 ($sfxIds)');
    final sfxUrls = await _fetchSfxUrls(sfxIds);
    debugPrint('fetchPublishedNodes($packId): sfx 쿼리 성공');

    final bgmIds = <String>{
      ...nodes.map((n) => n.effects.bgm?.bgmId).whereType<String>(),
      ?packDefaultBgmId,
    };
    debugPrint('fetchPublishedNodes($packId): bgm 쿼리 시작 ($bgmIds)');
    final bgmUrls = await _fetchBgmUrls(bgmIds);
    debugPrint('fetchPublishedNodes($packId): bgm 쿼리 성공');

    final resolvedNodes = [
      for (final node in nodes)
        ResolvedStoryNode(
          node: node,
          backgroundImageUrl:
              imageUrls[node.backgroundImage ??
                  resolveInheritedBackgroundImage(
                    nodes: nodes.map(
                      (n) => (
                        order: n.order,
                        backgroundImage: n.backgroundImage,
                        backgroundAppliesForward: n.backgroundAppliesForward,
                      ),
                    ),
                    targetOrder: node.order,
                    packDefaultBackgroundImage: packDefaultBackgroundImageId,
                  )],
          sfxUrl: node.effects.sfx.enabled
              ? sfxUrls[node.effects.sfx.sfxId]
              : null,
          bgmUrl: bgmUrls[node.effects.bgm?.bgmId],
        ),
    ];

    return (
      nodes: resolvedNodes,
      defaultBgmUrl: packDefaultBgmId != null
          ? bgmUrls[packDefaultBgmId]
          : null,
    );
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

  /// 리딩 세션이 시작될 때(InteractiveReader/LinearReader가 팩을 처음 열
  /// 때) 정확히 한 번만 호출한다 — 노드를 넘길 때마다가 아니다. 랭킹 스냅샷
  /// (rankingSnapshots, functions/src/index.ts의 computeDailyRankingSnapshot)
  /// 의 원천 데이터. firestore.rules가 이 필드 하나만, +1로만 바뀌는 update를
  /// 허용한다 — 다른 필드를 같이 바꾸거나 다른 값을 넣으려 하면 거부된다.
  Future<void> incrementViewCount(String packId) async {
    // viewCount 하나만, FieldValue.increment로만 건드린다 — firestore.rules의
    // affectedKeys().hasOnly(['viewCount']) + "정확히 이전 값+1"이라는 조건과
    // 정확히 맞아떨어져야 한다. 호출부(InteractiveReader/LinearReader)에서
    // unawaited로 fire-and-forget하기 때문에, 실패해도 원래는 콘솔에 아무
    // 흔적도 안 남는다 — 그 payload와 실패 여부를 여기서 직접 남긴다.
    final payload = {'viewCount': FieldValue.increment(1)};
    debugPrint('incrementViewCount($packId) payload: $payload');
    try {
      await _firestore.collection('storyPacks').doc(packId).update(payload);
      debugPrint('incrementViewCount($packId) 성공');
    } catch (e, stackTrace) {
      debugPrint('incrementViewCount($packId) 실패: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<Map<String, String>> _fetchSfxUrls(Set<String> sfxIds) async {
    if (sfxIds.isEmpty) return {};
    final snapshot = await _firestore
        .collection('sfxLibrary')
        .where(FieldPath.documentId, whereIn: sfxIds.toList())
        .get();
    return {
      for (final doc in snapshot.docs)
        doc.id: doc.data()['storageUrl'] as String? ?? '',
    };
  }

  Future<Map<String, String>> _fetchBgmUrls(Set<String> bgmIds) async {
    if (bgmIds.isEmpty) return {};
    final snapshot = await _firestore
        .collection('bgmLibrary')
        .where(FieldPath.documentId, whereIn: bgmIds.toList())
        .get();
    return {
      for (final doc in snapshot.docs)
        doc.id: doc.data()['storageUrl'] as String? ?? '',
    };
  }
}
