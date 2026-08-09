import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 앱 전역 BGM/SFX 재생을 담당하는 얇은 싱글턴 래퍼.
///
/// GameState 등 다른 상태 계층과는 무관한 순수 오디오 재생 담당이다 — 스토리
/// 진행/전투 로직이 "언제 소리를 낼지"는 알아도, 이 서비스는 "그 소리를 어떻게
/// 재생할지"만 안다. 어디서 부르든(스토리 노드, 전투, UI 버튼 등) 자리를 가리지
/// 않도록 설계했다.
///
/// [playBgm]/[playSfx]는 둘 다 번들 애셋 경로("assets/audio/...")와 http(s) URL을
/// 그대로 받는다 — 지금은 assets/audio/sfx/의 하드코딩된 시스템 효과음만 쓰지만,
/// 나중에 Firestore로 옮겨간 스토리 노드가 자기만의 bgmId/sfxId(Firebase Storage
/// 업로드 URL)를 들고 오게 되면 같은 메서드를 그대로 재사용할 수 있다.
///
/// 실제 오디오 파일이 없거나(assets/audio/sfx/README.md 참고) 재생에 실패해도
/// 예외를 밖으로 흘리지 않는다 — 로그만 남기고 조용히 넘어간다.
class AudioService {
  AudioService._internal();

  static final AudioService instance = AudioService._internal();

  final AudioPlayer _bgmPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  String? _currentBgmPath;

  /// 배경음악을 반복 재생한다. 이미 같은 트랙이 재생 중이면 아무 것도 하지 않고,
  /// 다른 트랙이 요청되면 지금 트랙을 멈추고 바로 교체한다.
  Future<void> playBgm(String assetOrUrl) async {
    if (_currentBgmPath == assetOrUrl) return;

    final previous = _currentBgmPath;
    _currentBgmPath = assetOrUrl;

    try {
      await _bgmPlayer.stop();
      await _bgmPlayer.play(_sourceFor(assetOrUrl));
    } catch (e) {
      debugPrint('BGM 재생 실패: $assetOrUrl ($e)');
      // 재생에 실패했으니 "지금 재생 중"으로 취급하지 않는다 — 그래야 같은
      // 트랙을 다시 요청했을 때 (파일이 뒤늦게 채워진 뒤 등) 재시도할 수 있다.
      _currentBgmPath = previous;
    }
  }

  Future<void> stopBgm() async {
    _currentBgmPath = null;
    try {
      await _bgmPlayer.stop();
    } catch (e) {
      debugPrint('BGM 정지 실패: $e');
    }
  }

  /// 짧은 효과음을 한 번 재생한다. BGM은 건드리지 않고, 매번 새 플레이어로
  /// 재생해 효과음이 겹쳐 울려도(예: 연속 공격) 서로 끊기지 않게 한다.
  Future<void> playSfx(String assetOrUrl) async {
    final player = AudioPlayer();
    try {
      await player.play(_sourceFor(assetOrUrl));
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (e) {
      debugPrint('SFX 재생 실패: $assetOrUrl ($e)');
      await player.dispose();
    }
  }

  Source _sourceFor(String assetOrUrl) {
    if (assetOrUrl.startsWith('http://') || assetOrUrl.startsWith('https://')) {
      return UrlSource(assetOrUrl);
    }
    // 번들 애셋 경로("assets/audio/...")를 audioplayers의 AssetSource가 기대하는,
    // "assets/" 접두사를 뗀 상대 경로로 바꾼다.
    final normalized = assetOrUrl.startsWith('assets/')
        ? assetOrUrl.substring('assets/'.length)
        : assetOrUrl;
    return AssetSource(normalized);
  }
}
