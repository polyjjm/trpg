import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/story/background_image_inheritance.dart';
import '../models/story_node.dart';
import '../story_media_session.dart';

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

/// `resolveStoryMedia` 호출 한 번의 결과 — 미디어 id → 짧은 수명의 signed URL.
///
/// [resolvedAt]을 같이 들고 다니는 게 핵심이다. 이 URL들은 서버에서 5분 뒤
/// 만료되므로 "언제 받은 URL인가"를 모르면 갱신 시점을 알 수 없다
/// ([StoryMediaSession] 참고).
class StoryMedia {
  final Map<String, String> images;
  final Map<String, String> sfx;
  final Map<String, String> bgm;
  final DateTime resolvedAt;

  const StoryMedia({
    required this.images,
    required this.sfx,
    required this.bgm,
    required this.resolvedAt,
  });

  StoryMedia.empty()
      : images = const {},
        sfx = const {},
        bgm = const {},
        resolvedAt = DateTime.fromMillisecondsSinceEpoch(0);
}

/// 노드 목록에서 서버에 물어봐야 할 미디어 id를 모은다. 최초 로드와 재해결이
/// **정확히 같은 집합**을 보내야 갱신 후에도 빠지는 미디어가 없어서, 이
/// 계산을 한 곳에 모아 뒀다.
({Set<String> imageIds, Set<String> sfxIds, Set<String> bgmIds}) collectMediaIds({
  required List<StoryNode> nodes,
  String? packDefaultBackgroundImageId,
  String? packDefaultBgmId,
}) {
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
  return (imageIds: imageIds, sfxIds: sfxIds, bgmIds: bgmIds);
}

/// 노드 + 방금 받은 URL 맵을 합쳐 [ResolvedStoryNode] 목록을 만든다.
/// 최초 로드와 재해결이 같은 함수를 쓴다 — 배경 인계 체인을 두 번 구현해
/// 두면 갱신 후에만 배경이 어긋나는 버그가 생긴다.
List<ResolvedStoryNode> resolveNodesWithMedia({
  required List<StoryNode> nodes,
  required StoryMedia media,
  String? packDefaultBackgroundImageId,
}) {
  return [
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
        sfxUrl: node.effects.sfx.enabled ? media.sfx[node.effects.sfx.sfxId] : null,
        bgmUrl: media.bgm[node.effects.bgm?.bgmId],
      ),
  ];
}

/// 리더가 실제로 보여줄 콘텐츠를 가져온다. **Firestore를 직접 읽는 경로가
/// 하나도 없다** — 본문과 미디어가 각각 별도의 서버 게이트를 지난다.
///
/// - **본문**: `fetchReaderStoryNodes` Cloud Function(PR #6). 서버가 무료/구매/
///   미리보기 권한을 다시 판정하고 승인본(`liveSnapshot`)만 반환한다. 그래서
///   유료 팩 본문도, 작가가 수정 중인 미승인 top-level draft도 클라이언트의
///   직접 쿼리로는 도달할 수 없다.
/// - **미디어 URL**: `resolveStoryMedia` Cloud Function(PR #4). 팩 전용 private
///   Storage 복사본의 5분짜리 signed URL만 돌려준다. 만료 관리(선제 갱신 +
///   실패 시 갱신)는 [StoryMediaSession]이 맡는다.
///
/// 두 게이트는 서로 독립이다 — 본문 권한과 미디어 권한을 각자 다시 판정하므로
/// 한쪽을 우회해도 다른 쪽이 열리지 않는다.
class StoryReaderRepository {
  StoryReaderRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// 팩을 열 때 한 번 호출한다 — 본문을 서버에서 받고 미디어 URL을 한 번 받아
  /// [StoryMediaSession]을 만들어 돌려준다. 이후 URL 만료 관리는 그 세션이
  /// 맡는다.
  Future<StoryMediaSession> openReadingSession(
    String packId, {
    String? packDefaultBackgroundImageId,
    String? packDefaultBgmId,
  }) async {
    debugPrint('openReadingSession($packId): 본문 서버 인가 조회 시작');
    final response = await _functions
        .httpsCallable('fetchReaderStoryNodes')
        .call({'packId': packId});
    final data = Map<String, dynamic>.from(response.data as Map);
    final rawNodes = data['nodes'] as List<dynamic>? ?? const [];

    final nodes = <StoryNode>[];
    for (final raw in rawNodes) {
      final map = Map<String, dynamic>.from(raw as Map);
      // 서버가 liveSnapshot을 펼치면서 id를 같이 넣어 준다 — 본문 필드와
      // 섞이지 않게 여기서 다시 뽑아낸다.
      final id = map.remove('id') as String?;
      if (id == null || id.isEmpty) continue;
      nodes.add(StoryNode.fromFirestore(id, map));
    }
    nodes.sort((a, b) => a.order.compareTo(b.order));
    debugPrint(
      'openReadingSession($packId): 본문 조회 성공 '
      '(${nodes.length}건, access=${data['access']})',
    );

    final ids = collectMediaIds(
      nodes: nodes,
      packDefaultBackgroundImageId: packDefaultBackgroundImageId,
      packDefaultBgmId: packDefaultBgmId,
    );

    debugPrint(
      'openReadingSession($packId): secure media resolve 시작 '
      '(images=${ids.imageIds.length}, sfx=${ids.sfxIds.length}, '
      'bgm=${ids.bgmIds.length})',
    );
    final media = await resolveMedia(
      packId: packId,
      imageIds: ids.imageIds,
      sfxIds: ids.sfxIds,
      bgmIds: ids.bgmIds,
    );
    debugPrint('openReadingSession($packId): secure media resolve 성공');

    return StoryMediaSession(
      repository: this,
      packId: packId,
      rawNodes: nodes,
      media: media,
      packDefaultBackgroundImageId: packDefaultBackgroundImageId,
      packDefaultBgmId: packDefaultBgmId,
    );
  }

  /// resolveStoryMedia를 호출해 id → signed URL 맵을 받는다. 최초 로드와
  /// [StoryMediaSession]의 갱신이 같은 경로를 쓴다.
  Future<StoryMedia> resolveMedia({
    required String packId,
    required Set<String> imageIds,
    required Set<String> sfxIds,
    required Set<String> bgmIds,
  }) async {
    if (imageIds.isEmpty && sfxIds.isEmpty && bgmIds.isEmpty) {
      return StoryMedia(
        images: const {},
        sfx: const {},
        bgm: const {},
        resolvedAt: DateTime.now(),
      );
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

    return StoryMedia(
      images: parseMap('images'),
      sfx: parseMap('sfx'),
      bgm: parseMap('bgm'),
      // 서버 TTL의 기준은 서버가 서명한 시각이지만, 클라이언트가 알 수 있는
      // 건 응답을 받은 시각뿐이다. 왕복 시간만큼 보수적으로(= 실제보다 조금
      // 늦게 받은 것으로) 잡히므로 안전한 방향의 오차다.
      resolvedAt: DateTime.now(),
    );
  }

  /// 리딩 세션이 시작될 때 정확히 한 번 호출한다. 노드 본문과 달리 이건
  /// 여전히 Firestore 직접 쓰기다 — firestore.rules가 viewCount 한 필드만,
  /// 정확히 +1로만 바뀌는 update를 허용한다.
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
