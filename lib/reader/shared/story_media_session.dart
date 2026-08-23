import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/story_reader_repository.dart';
import 'models/story_node.dart';

/// 리딩 세션 하나가 살아 있는 동안의 미디어(배경/SFX/BGM) URL 상태.
///
/// `resolveStoryMedia` Cloud Function이 돌려주는 건 **5분짜리 V4 signed URL**
/// 이다(functions/src/secure_story_media.ts의 `signedUrlTtlMs`). 예전에는
/// 리더가 팩을 열 때 딱 한 번 URL을 받아 [ResolvedStoryNode]에 그대로 박아
/// 두고 세션 내내 재사용했는데, 실제 독서 시간은 5분을 훌쩍 넘기므로 그
/// 이후 이동하는 노드마다 만료된 URL을 쓰게 됐다 — 배경은 조용히
/// fallback 배너로 바뀌고(errorBuilder), BGM/SFX는 AudioService가 예외를
/// 삼켜서 그냥 소리가 안 났다. 아무 에러도 안 보이는 게 더 나빴다.
///
/// 그래서 이 클래스가 두 겹으로 막는다:
///
/// **(A) 만료 전 선제 재해결** — [ensureFresh]. 노드를 이동할 때마다 부르고,
/// 마지막 해결로부터 [refreshAfter]([signedUrlTtl]보다 [_safetyMargin]만큼
/// 짧다)가 지났으면 렌더 전에 새 URL을 받아 온다. 화면에 그려지기 **전에**
/// 갱신되므로 사용자는 만료를 아예 겪지 않는다. idle 상태에서는 아무 것도
/// 하지 않는다(타이머로 주기 호출하지 않는다 — 아무도 안 보는 URL에
/// 서명하느라 함수를 깨울 이유가 없다).
///
/// **(B) 실패 시 사후 재해결** — [refreshAfterFailure]. (A)가 놓치는 경우가
/// 남는다: 같은 노드에 오래 머문 뒤 위젯이 다시 그려지면서 이미지를 새로
/// 요청하는 경우 등. 이때 `Image.network`의 errorBuilder가 이걸 부르면
/// 즉시 새 URL을 받아 다시 그린다. 새 URL은 서명이 달라 Flutter의 실패
/// 캐시에 걸리지 않으므로 실제로 재요청이 일어난다.
///
/// 두 경로 모두 [_inFlight]로 중복 호출을 합치고, (B)는 [_failureCooldown]
/// 으로 무한 루프를 막는다 — 파일이 실제로 없어서 실패하는 경우 새 URL을
/// 받아도 똑같이 실패하는데, 그때 errorBuilder → 재해결 → errorBuilder가
/// 끝없이 도는 걸 방지한다.
class StoryMediaSession extends ChangeNotifier {
  StoryMediaSession({
    required StoryReaderRepository repository,
    required String packId,
    required List<StoryNode> rawNodes,
    required StoryMedia media,
    this.packDefaultBackgroundImageId,
    this.packDefaultBgmId,
  })  : _repository = repository,
        _packId = packId,
        _rawNodes = rawNodes,
        _media = media {
    _rebuildResolved();
  }

  /// 서버(`secure_story_media.ts`)가 발급하는 signed URL의 수명. 서버 값이
  /// 바뀌면 여기도 같이 바꿔야 한다 — 이쪽이 더 길면 만료된 URL을 그대로
  /// 쓰게 된다.
  static const Duration signedUrlTtl = Duration(minutes: 5);

  /// 네트워크 왕복과 사용자가 노드를 읽는 시간을 감안한 여유. 만료 직전이
  /// 아니라 이만큼 남았을 때 미리 갱신한다.
  static const Duration _safetyMargin = Duration(minutes: 1);

  /// 이 시간이 지나면 [ensureFresh]가 재해결한다(= TTL - 여유 = 4분).
  static Duration get refreshAfter => signedUrlTtl - _safetyMargin;

  /// (B) 경로가 연달아 도는 걸 막는 최소 간격.
  static const Duration _failureCooldown = Duration(seconds: 10);

  final StoryReaderRepository _repository;
  final String _packId;
  final List<StoryNode> _rawNodes;

  final String? packDefaultBackgroundImageId;
  final String? packDefaultBgmId;

  StoryMedia _media;
  late List<ResolvedStoryNode> _nodes;
  late Map<String, ResolvedStoryNode> _nodesById;

  Future<void>? _inFlight;
  bool _disposed = false;

  /// order 오름차순으로 정렬된, URL까지 채워진 노드들.
  List<ResolvedStoryNode> get nodes => _nodes;

  Map<String, ResolvedStoryNode> get nodesById => _nodesById;

  /// 첫 노드가 BGM을 안 정했을 때 쓸 팩 기본 BGM의 현재 URL.
  String? get defaultBgmUrl =>
      packDefaultBgmId == null ? null : _media.bgm[packDefaultBgmId];

  /// 마지막으로 URL을 받아 온 시각. 테스트/디버깅용.
  @visibleForTesting
  DateTime get resolvedAt => _media.resolvedAt;

  bool get _isStale =>
      DateTime.now().difference(_media.resolvedAt) >= refreshAfter;

  /// (A) 노드를 이동하기 직전에 부른다. 아직 만료가 멀었으면 즉시 반환하므로
  /// 이동 경로에 그냥 `await`로 끼워 넣어도 비용이 없다.
  Future<void> ensureFresh() {
    if (_disposed) return Future<void>.value();
    final pending = _inFlight;
    if (pending != null) return pending;
    if (!_isStale) return Future<void>.value();
    return _refresh(reason: 'ttl');
  }

  /// (B) 미디어 로드가 실제로 실패했을 때 부른다(`Image.network`의
  /// errorBuilder 등). 방금 갱신했는데 또 실패했다면 만료가 원인이 아니므로
  /// [_failureCooldown] 동안은 다시 시도하지 않는다.
  Future<void> refreshAfterFailure() {
    if (_disposed) return Future<void>.value();
    final pending = _inFlight;
    if (pending != null) return pending;
    if (DateTime.now().difference(_media.resolvedAt) < _failureCooldown) {
      debugPrint(
        'StoryMediaSession($_packId): 방금 갱신한 URL도 실패했다 — 만료가 아닌 다른 '
        '원인으로 보고 재해결을 건너뛴다.',
      );
      return Future<void>.value();
    }
    return _refresh(reason: 'load-failure');
  }

  Future<void> _refresh({required String reason}) {
    final future = _doRefresh(reason).whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<void> _doRefresh(String reason) async {
    final ids = collectMediaIds(
      nodes: _rawNodes,
      packDefaultBackgroundImageId: packDefaultBackgroundImageId,
      packDefaultBgmId: packDefaultBgmId,
    );
    if (ids.imageIds.isEmpty && ids.sfxIds.isEmpty && ids.bgmIds.isEmpty) {
      return;
    }

    debugPrint('StoryMediaSession($_packId): 미디어 URL 재해결 시작 (사유: $reason)');
    try {
      final media = await _repository.resolveMedia(
        packId: _packId,
        imageIds: ids.imageIds,
        sfxIds: ids.sfxIds,
        bgmIds: ids.bgmIds,
      );
      if (_disposed) return;
      _media = media;
      _rebuildResolved();
      debugPrint('StoryMediaSession($_packId): 미디어 URL 재해결 성공');
      notifyListeners();
    } catch (e, stackTrace) {
      // 실패해도 기존 URL을 지우지 않는다 — 아직 안 만료됐을 수도 있고,
      // 만료됐더라도 "깨진 이미지"가 "아무것도 없음"보다는 낫다. 다음
      // ensureFresh/refreshAfterFailure에서 다시 시도한다.
      debugPrint('StoryMediaSession($_packId): 미디어 URL 재해결 실패: $e\n$stackTrace');
    }
  }

  void _rebuildResolved() {
    _nodes = resolveNodesWithMedia(
      nodes: _rawNodes,
      media: _media,
      packDefaultBackgroundImageId: packDefaultBackgroundImageId,
    );
    _nodesById = {for (final n in _nodes) n.node.id: n};
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
