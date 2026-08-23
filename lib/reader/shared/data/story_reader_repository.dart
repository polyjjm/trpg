import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/story/background_image_inheritance.dart';
import '../models/story_node.dart';

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

/// 독자용 스토리 본문은 Firestore의 nodes 컬렉션을 직접 읽지 않고
/// fetchReaderStoryNodes Cloud Function을 통해 받는다. 서버가 무료/구매/
/// 미리보기 권한을 판정하고 liveSnapshot만 반환하므로 유료 팩 본문과
/// 미승인 top-level draft가 클라이언트의 직접 쿼리 경로에 의존하지 않는다.
class StoryReaderRepository {
  StoryReaderRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<({List<ResolvedStoryNode> nodes, String? defaultBgmUrl})>
  fetchPublishedNodes(
    String packId, {
    String? packDefaultBackgroundImageId,
    String? packDefaultBgmId,
  }) async {
    debugPrint('fetchPublishedNodes($packId): 서버 인가 조회 시작');
    final response = await _functions.httpsCallable('fetchReaderStoryNodes').call({
      'packId': packId,
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    final rawNodes = (data['nodes'] as List<dynamic>? ?? const []);

    final nodes = <StoryNode>[];
    for (final raw in rawNodes) {
      final map = Map<String, dynamic>.from(raw as Map);
      final id = map.remove('id') as String?;
      if (id == null || id.isEmpty) continue;
      nodes.add(StoryNode.fromFirestore(id, map));
    }
    nodes.sort((a, b) => a.order.compareTo(b.order));
    debugPrint(
      'fetchPublishedNodes($packId): 서버 인가 조회 성공 (${nodes.length}건, ${data['access']})',
    );

    final imageIds = <String>{
      ...nodes.map((n) => n.backgroundImage).whereType<String>(),
      ?packDefaultBackgroundImageId,
    };
    final imageUrls = await _fetchImageUrls(imageIds);

    final sfxIds = nodes
        .where((n) => n.effects.sfx.enabled)
        .map((n) => n.effects.sfx.sfxId)
        .whereType<String>()
        .toSet();
    final sfxUrls = await _fetchSfxUrls(sfxIds);

    final bgmIds = <String>{
      ...nodes.map((n) => n.effects.bgm?.bgmId).whereType<String>(),
      ?packDefaultBgmId,
    };
    final bgmUrls = await _fetchBgmUrls(bgmIds);

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
                        backgroundAppliesForward:
                            n.backgroundAppliesForward,
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

  /// PR #4의 private story-media 전달 구조가 머지되기 전까지는 기존 공유
  /// 라이브러리 조인을 유지한다. #4가 머지되면 이 세 메서드는
  /// resolveStoryMedia 호출로 교체할 수 있다.
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
