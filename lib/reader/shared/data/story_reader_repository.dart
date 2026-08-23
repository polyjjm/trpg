import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/story/background_image_inheritance.dart';
import '../models/story_node.dart';

/// [StoryNode] + 배경 인계 규칙까지 적용해 이미 URL로 resolve된 배경 이미지.
class ResolvedStoryNode {
  final StoryNode node;
  final String? backgroundImageUrl;
  final String? sfxUrl;
  final String? bgmUrl;

  const ResolvedStoryNode({
    required this.node,
    required this.backgroundImageUrl,
    this.sfxUrl,
    this.bgmUrl,
  });
}

/// storyPacks/{packId}/nodes에서 리더가 실제로 보여줄 콘텐츠를 읽어온다.
/// 노드 본문은 liveSnapshot만 읽고, 이미지/SFX/BGM 실제 파일 URL은 Firestore
/// 라이브러리 문서를 직접 읽지 않는다. resolveStoryMedia Cloud Function이
/// 구매/무료/미리보기 권한과 실제 liveSnapshot 참조 여부를 서버에서 다시
/// 검증한 뒤 pack 전용 private Storage 복사본의 짧은 signed URL만 반환한다.
class StoryReaderRepository {
  StoryReaderRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> _nodes(String packId) =>
      _firestore.collection('storyPacks').doc(packId).collection('nodes');

  Future<({List<ResolvedStoryNode> nodes, String? defaultBgmUrl})>
  fetchPublishedNodes(
    String packId, {
    String? packDefaultBackgroundImageId,
    String? packDefaultBgmId,
  }) async {
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
      if (liveSnapshot == null) continue;
      nodes.add(StoryNode.fromFirestore(doc.id, liveSnapshot));
    }
    nodes.sort((a, b) => a.order.compareTo(b.order));

    final imageIds = <String>{
      ...nodes.map((n) => n.backgroundImage).whereType<String>(),
      ?packDefaultBackgroundImageId,
    };
    final sfxIds = nodes
        .where((n) => n.effects.sfx.enabled)
        .map((n) => n.effects.sfx.sfxId)
        .whereType<String>()
        .toSet();
    final bgmIds = <String>{
      ...nodes.map((n) => n.effects.bgm?.bgmId).whereType<String>(),
      ?packDefaultBgmId,
    };

    debugPrint(
      'fetchPublishedNodes($packId): secure media resolve 시작 '
      '(images=${imageIds.length}, sfx=${sfxIds.length}, bgm=${bgmIds.length})',
    );
    final media = await _resolveStoryMedia(
      packId: packId,
      imageIds: imageIds,
      sfxIds: sfxIds,
      bgmIds: bgmIds,
    );
    debugPrint('fetchPublishedNodes($packId): secure media resolve 성공');

    final resolvedNodes = [
      for (final node in nodes)
        ResolvedStoryNode(
          node: node,
          backgroundImageUrl:
              media.images[node.backgroundImage ??
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
              ? media.sfx[node.effects.sfx.sfxId]
              : null,
          bgmUrl: media.bgm[node.effects.bgm?.bgmId],
        ),
    ];

    return (
      nodes: resolvedNodes,
      defaultBgmUrl: packDefaultBgmId != null
          ? media.bgm[packDefaultBgmId]
          : null,
    );
  }

  Future<({Map<String, String> images, Map<String, String> sfx, Map<String, String> bgm})>
  _resolveStoryMedia({
    required String packId,
    required Set<String> imageIds,
    required Set<String> sfxIds,
    required Set<String> bgmIds,
  }) async {
    if (imageIds.isEmpty && sfxIds.isEmpty && bgmIds.isEmpty) {
      return (images: <String, String>{}, sfx: <String, String>{}, bgm: <String, String>{});
    }

    final result = await _functions.httpsCallable('resolveStoryMedia').call({
      'packId': packId,
      'imageIds': imageIds.toList(),
      'sfxIds': sfxIds.toList(),
      'bgmIds': bgmIds.toList(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);

    Map<String, String> parseMap(String key) {
      final raw = data[key];
      if (raw is! Map) return <String, String>{};
      return {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    }

    return (
      images: parseMap('images'),
      sfx: parseMap('sfx'),
      bgm: parseMap('bgm'),
    );
  }

  /// 리딩 세션이 시작될 때 정확히 한 번 호출한다.
  Future<void> incrementViewCount(String packId) async {
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
}
