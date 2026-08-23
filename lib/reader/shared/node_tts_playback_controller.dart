import 'dart:async';

import 'package:just_audio/just_audio.dart' as ja;

import 'data/node_tts_repository.dart';

/// SceneFrame 하단 시트의 TTS 토글이 쓰는 재생 래퍼 — 예전 [TtsController](기기
/// 내장 flutter_tts)를 대체한다. 텍스트를 즉석에서 읽어주는 대신,
/// [NodeTtsRepository]로 이 노드의 Typecast 내레이션 오디오 URL(캐시돼 있으면
/// 즉시, 아니면 첫 생성까지 잠깐 걸린다)을 받아 [just_audio]로 재생한다.
///
/// AudioService(BGM 세션 전역 싱글턴)와 달리 이 컨트롤러는 SceneFrame 하나의
/// 생애를 그대로 따라간다 — 노드가 바뀌면 SceneFrame 자체가 새 key로 다시
/// 만들어지므로(클래스 doc 참고) 내레이션도 자연스럽게 처음부터 다시
/// 시작한다. 세션을 이어갈 필요가 없는 콘텐츠라 별도 세션 컨트롤러를 두지
/// 않았다.
///
/// [playSequence]는 노드 id 하나가 아니라 순서 있는 목록을 받는다 — 대부분은
/// 원소 하나짜리 목록(노드 하나짜리 화면)이지만, 선형 리더의 두 쪽 펼침
/// 모드는 한 화면에 노드 두 개(왼쪽/오른쪽 쪽)를 동시에 보여주므로, 왼쪽
/// 쪽 내레이션이 끝나면 화면 전환 없이 곧바로 오른쪽 쪽 내레이션을 이어
/// 튼다(요청 사양 Part 2: "narration should read through BOTH visible pages
/// in sequence before advancing"). 목록의 마지막 항목까지 다 끝나야만
/// [allCompletedStream]이 울린다 — 그때가 "이 화면 전체의 내레이션이
/// 끝났다"는 뜻이고, 자동 이어재생(다음 노드/스프레드로 넘어갈지)은 그
/// 신호를 받는 리더 페이지(ReaderSessionController)의 몫이다.
class NodeTtsPlaybackController {
  NodeTtsPlaybackController({NodeTtsRepository? repository})
    : _repository = repository ?? NodeTtsRepository() {
    _playerStateSub = _player.playerStateStream.listen(_handlePlayerState);
  }

  final NodeTtsRepository _repository;
  final ja.AudioPlayer _player = ja.AudioPlayer();
  StreamSubscription<ja.PlayerState>? _playerStateSub;

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _loadingController =
      StreamController<bool>.broadcast();
  final StreamController<void> _allCompletedController =
      StreamController<void>.broadcast();

  bool _isPlaying = false;
  bool _isLoading = false;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<bool> get loadingStream => _loadingController.stream;

  /// 지금 이 화면에 걸린 재생 목록(narrationNodeIds)의 마지막 항목까지 자연
  /// 재생 완료됐을 때 한 번 울린다 — 사용자가 일시정지한 경우는 울리지
  /// 않는다(그건 그냥 `_player.pause()`라 processingState가 completed가 될
  /// 일이 없다).
  Stream<void> get allCompletedStream => _allCompletedController.stream;

  String? _packId;
  List<String> _queueNodeIds = const [];
  int _queueIndex = 0;

  /// 지금 로드해 둔 세그먼트의 노드 id — 같은 세그먼트를 일시정지 후 다시
  /// 누르면 재생성/재다운로드 없이 그대로 이어 튼다.
  String? _loadedNodeId;

  void _setPlaying(bool value) {
    if (_isPlaying == value) return;
    _isPlaying = value;
    _playingController.add(value);
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    _loadingController.add(value);
  }

  void _handlePlayerState(ja.PlayerState state) {
    final completed = state.processingState == ja.ProcessingState.completed;
    _setPlaying(state.playing && !completed);
    if (!completed) return;

    if (_queueIndex + 1 < _queueNodeIds.length) {
      _queueIndex += 1;
      // 화면은 그대로 두고(스프레드의 왼쪽→오른쪽 쪽처럼) 다음 세그먼트로
      // 곧바로 넘어간다 — SceneFrame엔 아무 신호도 안 보낸다.
      unawaited(_playQueueIndex());
    } else {
      // 재생목록 전체가 끝났다 — 다음에 다시 누르면 처음부터 다시 재생하도록
      // 초기화해 둔다(그렇지 않으면 "이미 로드된 세그먼트"로 오인해
      // 끝난 자리에서 그냥 멈춰 있는 것처럼 보인다).
      _queueIndex = 0;
      _loadedNodeId = null;
      _allCompletedController.add(null);
    }
  }

  Future<void> _playQueueIndex() async {
    final nodeId = _queueNodeIds[_queueIndex];
    final packId = _packId!;
    _setLoading(true);
    try {
      final url = await _repository.synthesize(packId: packId, nodeId: nodeId);
      await _player.setUrl(url);
      _loadedNodeId = nodeId;
    } finally {
      _setLoading(false);
    }
    // ⚠️ just_audio의 AudioPlayer.play()가 돌려주는 Future는 "재생이 시작될
    // 때"가 아니라 "재생이 끝나거나 일시정지/정지될 때" 완료된다(패키지 문서:
    // "completes when the playback completes or is paused or stopped"). 이걸
    // await하면 재생되는 내내 _isLoading이 true로 묶여서 (a) 설정 패널 라벨이
    // "TTS 준비 중"에 멈춰 있고 (b) 탭 핸들러의 "로딩 중엔 무시" 가드 때문에
    // 재생 중엔 아예 끌 수도 없게 된다 — 실제로 겪은 버그. 재생은
    // fire-and-forget으로 시작만 하고, 이후 상태 갱신은 전부
    // playerStateStream 리스너([_handlePlayerState])가 한다.
    unawaited(_player.play());
  }

  /// [nodeIds] 순서대로 내레이션을 이어 튼다. 이미 같은 목록을 재생하던
  /// 중(일시정지 상태)이면 처음부터 다시 시작하지 않고 그대로 이어 튼다.
  Future<void> playSequence({
    required String packId,
    required List<String> nodeIds,
  }) async {
    if (_isLoading || nodeIds.isEmpty) return;
    final resuming =
        _packId == packId &&
        _loadedNodeId != null &&
        _sameQueue(_queueNodeIds, nodeIds);
    if (resuming) {
      // 위 [_playQueueIndex]와 같은 이유로 await하지 않는다 — 일시정지에서
      // 이어 트는 경우도 재생 시작만 하고 곧바로 반환해야 한다.
      unawaited(_player.play());
      return;
    }

    _packId = packId;
    _queueNodeIds = nodeIds;
    _queueIndex = 0;
    await _playQueueIndex();
  }

  bool _sameQueue(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
    _queueIndex = 0;
    _loadedNodeId = null;
    _setPlaying(false);
  }

  void dispose() {
    _playerStateSub?.cancel();
    _player.dispose();
    _playingController.close();
    _loadingController.close();
    _allCompletedController.close();
  }
}
