import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// 앱 전역 BGM/SFX 재생을 담당하는 얇은 싱글턴 래퍼.
///
/// GameState 등 다른 상태 계층과는 무관한 순수 오디오 재생 담당이다 — 스토리
/// 진행/전투 로직이 "언제 소리를 낼지"는 알아도, 이 서비스는 "그 소리를 어떻게
/// 재생할지"만 안다. "지금 재생 중인 bgmId가 뭔지", "이 노드가 BGM을 바꿔야
/// 하는지" 같은 판단은 이 서비스가 아니라 호출부(BgmSessionController,
/// lib/reader/shared/bgm_session_controller.dart)의 몫이다.
///
/// SFX와 BGM이 서로 다른 패키지를 쓴다:
/// - **SFX**([playSfx]): `audioplayers` — 매번 새 플레이어를 만들어 겹쳐 울려도
///   서로 안 끊기는 단순 1회 재생이면 충분하다(기존 그대로, 안 건드렸다).
/// - **BGM**([crossfadeToBgm]/[fadeOutBgm]): `just_audio` — 두 플레이어를
///   번갈아 쓰며 볼륨을 서서히 올리고/내리는 크로스페이드가 필요해서
///   audioplayers보다 세밀한 볼륨 제어 API를 제공하는 just_audio로 새로 짰다.
///   just_audio는 Flutter Web을 공식 지원한다(federated plugin
///   `just_audio_web`이 `flutter pub add just_audio` 시점에 자동으로 같이
///   설치된다) — HTML5 `<audio>` 엘리먼트 기반이라 이 서비스가 쓰는 볼륨
///   제어/루프/동시 재생 전부 웹에서도 그대로 동작한다. 다만 브라우저의
///   자동재생 정책상 사용자 상호작용 이전에는 재생이 막힐 수 있는데, 이
///   서비스가 호출되는 시점은 항상 리더 화면에 이미 진입한 뒤(= 이미
///   상호작용이 있었던 뒤)라 실질적인 제약이 되지 않는다.
class AudioService {
  AudioService._internal();

  static final AudioService instance = AudioService._internal();

  // ── BGM: just_audio, 두 플레이어를 번갈아 쓰는 크로스페이드 ──────────────

  final List<ja.AudioPlayer> _bgmPlayers = [ja.AudioPlayer(), ja.AudioPlayer()];
  int _activeBgmPlayer = 0;
  String? _currentBgmUrl;

  /// 지금 트랙에 작성자가 정한 볼륨(effects.bgm.volume, 기본 1.0) — "완전히
  /// 페이드인된 상태"에서 이 값과 [_userMasterVolume]을 곱한 게 실제 목표
  /// 볼륨이다([_effectiveVolume]).
  double _currentBgmVolume = 1.0;

  /// 리더 본인이 설정 패널의 BGM 볼륨 슬라이더로 고른 값(0.0~1.0, 기본 1.0,
  /// `ReaderPrefs.bgmMasterVolume`에서 온다) — 작성자가 정한 [_currentBgmVolume]과
  /// 곱해진다. 슬라이더를 드래그하는 동안 [setBgmMasterVolume]이 실시간으로
  /// 갱신한다.
  double _userMasterVolume = 1.0;

  static const Duration _bgmFadeDuration = Duration(milliseconds: 1000);

  /// 트랙 전환 없이 볼륨만 바뀔 때 쓰는 더 짧은 전환 — 크로스페이드만큼
  /// 느릴 필요가 없다(같은 트랙이 계속 들리는 채로 볼륨만 스윽 바뀌면
  /// 충분하다).
  static const Duration _bgmVolumeAdjustDuration = Duration(milliseconds: 400);

  static const int _bgmFadeSteps = 20;

  /// 지금 재생 중이어야 할 실제 목표 볼륨 — 작성자가 정한 값과 리더 본인의
  /// 취향을 곱한다. 둘 중 하나가 0이면(작성자가 무음으로 정했거나, 리더가
  /// 슬라이더를 완전히 내렸거나) 결과도 0이다.
  double get _effectiveVolume =>
      (_currentBgmVolume * _userMasterVolume).clamp(0.0, 1.0);

  /// 리더 화면 설정 패널의 BGM 볼륨 슬라이더가 쓴다 — 드래그하는 동안 매
  /// 프레임 불려도 되도록 [_fadeVolume]의 단계적 전환 없이 활성 플레이어의
  /// 볼륨을 즉시 새 목표치로 바꾼다(느린 크로스페이드/조정과 달리, 슬라이더는
  /// "실시간으로 들려야" 의미가 있다 — 매번 0.4초짜리 페이드를 새로 걸면
  /// 계속 겹쳐 덧씌워지며 오히려 부자연스럽다). 재생 중인 트랙이 없어도
  /// [_userMasterVolume] 자체는 갱신해 둔다 — 다음에 트랙이 시작될 때
  /// (crossfadeToBgm) 바로 반영되게.
  Future<void> setBgmMasterVolume(double volume) async {
    _userMasterVolume = volume.clamp(0.0, 1.0);
    if (_currentBgmUrl == null) return;
    try {
      await _bgmPlayers[_activeBgmPlayer].setVolume(_effectiveVolume);
    } catch (e) {
      debugPrint('BGM 마스터 볼륨 조정 실패: $e');
    }
  }

  /// 지금 재생 중인 트랙에서 [url]로 크로스페이드한다 — 두 플레이어 중 안 쓰는
  /// 쪽에 새 트랙을 0볼륨으로 미리 걸어 재생을 시작해 두고, 새 플레이어는
  /// 볼륨을 올리는 동시에 기존 플레이어는 볼륨을 내려 [fade] 동안 서서히
  /// 자리를 바꾼다(둘 다 동시에 진행 — 한쪽이 끝나길 기다렸다 다른 쪽을
  /// 시작하지 않는다). [volume](기본 1.0, effects.bgm.volume에서 온다)이
  /// 작성자가 정한 목표 볼륨이다 — 실제로 페이드해 도달하는 값은 여기에
  /// [_userMasterVolume]까지 곱한 [_effectiveVolume]이다(항상 100%로
  /// 올라가는 게 아니라 이 노드가 정한 값 × 리더 취향까지만 올라간다).
  /// 이미 같은 URL이 재생 중이면 아무 것도 하지 않는다 — BgmSessionController가
  /// "같은 트랙이면 호출 자체를 안 한다"는 판단을 이미 하지만, 방어적으로
  /// 여기서도 한 번 더 막는다(볼륨만 바뀐 경우는 이 메서드가 아니라
  /// [adjustBgmVolume]로 온다).
  Future<void> crossfadeToBgm(
    String url, {
    double volume = 1.0,
    Duration fade = _bgmFadeDuration,
  }) async {
    if (_currentBgmUrl == url) return;

    final fromPlayer = _bgmPlayers[_activeBgmPlayer];
    final wasPlaying = fromPlayer.playing;
    final toIndex = 1 - _activeBgmPlayer;
    final toPlayer = _bgmPlayers[toIndex];

    _currentBgmUrl = url;
    _currentBgmVolume = volume;
    _activeBgmPlayer = toIndex;

    try {
      await toPlayer.setLoopMode(ja.LoopMode.one);
      await toPlayer.setUrl(url);
      await toPlayer.setVolume(0);
      // play()가 반환하는 Future는 재생이 "끝날 때"(LoopMode.one이면 사실상
      // 영원히) 완료되는 Future라 await하면 여기서 멈춘다 — fire-and-forget한다.
      unawaited(toPlayer.play());

      await Future.wait([
        _fadeVolume(toPlayer, to: _effectiveVolume, duration: fade),
        if (wasPlaying) _fadeVolume(fromPlayer, to: 0, duration: fade),
      ]);
      if (wasPlaying) await fromPlayer.stop();
    } catch (e) {
      debugPrint('BGM 크로스페이드 실패: $url ($e)');
      // 재생에 실패했으니 "지금 재생 중"으로 취급하지 않는다 — 그래야 같은
      // 트랙을 다시 요청했을 때(파일이 뒤늦게 채워진 뒤 등) 재시도할 수 있다.
      _currentBgmUrl = null;
    }
  }

  /// 트랙은 그대로 이어지는 채로 작성자 목표 볼륨([volume])만 바꾼다 — 같은
  /// `bgmId`가 다음 노드에서도 계속되는데 `effects.bgm.volume`만 달라졌을
  /// 때 쓴다(BgmSessionController가 "트랙은 같은데 볼륨만 다르다"를
  /// 감지해서 이 메서드를 부른다 — [crossfadeToBgm]을 다시 부르면
  /// `_currentBgmUrl == url`이라 조용히 무시되므로, 볼륨 변경은 반드시
  /// 이 메서드를 따로 타야 한다). 재생 중인 BGM이 없으면 아무 것도 하지
  /// 않는다.
  Future<void> adjustBgmVolume(
    double volume, {
    Duration fade = _bgmVolumeAdjustDuration,
  }) async {
    if (_currentBgmUrl == null) return;
    _currentBgmVolume = volume;
    try {
      await _fadeVolume(
        _bgmPlayers[_activeBgmPlayer],
        to: _effectiveVolume,
        duration: fade,
      );
    } catch (e) {
      debugPrint('BGM 볼륨 조정 실패: $e');
    }
  }

  /// 지금 재생 중인 BGM을 [fade] 동안 무음으로 페이드아웃한 뒤 멈춘다.
  /// 재생 중인 BGM이 없으면 아무 것도 하지 않는다.
  Future<void> fadeOutBgm({Duration fade = _bgmFadeDuration}) async {
    if (_currentBgmUrl == null) return;
    final active = _bgmPlayers[_activeBgmPlayer];
    _currentBgmUrl = null;
    try {
      await _fadeVolume(active, to: 0, duration: fade);
      await active.stop();
    } catch (e) {
      debugPrint('BGM 무음 전환 실패: $e');
    }
  }

  Future<void> _fadeVolume(
    ja.AudioPlayer player, {
    required double to,
    required Duration duration,
  }) async {
    final from = player.volume;
    if (duration <= Duration.zero || from == to) {
      await player.setVolume(to);
      return;
    }
    final stepMs = (duration.inMilliseconds / _bgmFadeSteps).round().clamp(
      1,
      duration.inMilliseconds,
    );
    for (var i = 1; i <= _bgmFadeSteps; i++) {
      final t = i / _bgmFadeSteps;
      await player.setVolume((from + (to - from) * t).clamp(0.0, 1.0));
      if (i < _bgmFadeSteps) {
        await Future.delayed(Duration(milliseconds: stepMs));
      }
    }
  }

  // ── SFX: audioplayers, 그대로 ────────────────────────────────────────

  /// 짧은 효과음을 한 번 재생한다. BGM은 건드리지 않고, 매번 새 플레이어로
  /// 재생해 효과음이 겹쳐 울려도(예: 연속 공격) 서로 끊기지 않게 한다.
  ///
  /// 실제 오디오 파일이 없거나(assets/audio/sfx/README.md 참고) 재생에
  /// 실패해도 예외를 밖으로 흘리지 않는다 — 로그만 남기고 조용히 넘어간다.
  Future<void> playSfx(String assetOrUrl) async {
    final player = ap.AudioPlayer();
    try {
      await player.play(_sourceFor(assetOrUrl));
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (e) {
      debugPrint('SFX 재생 실패: $assetOrUrl ($e)');
      await player.dispose();
    }
  }

  ap.Source _sourceFor(String assetOrUrl) {
    if (assetOrUrl.startsWith('http://') || assetOrUrl.startsWith('https://')) {
      return ap.UrlSource(assetOrUrl);
    }
    // 번들 애셋 경로("assets/audio/...")를 audioplayers의 AssetSource가 기대하는,
    // "assets/" 접두사를 뗀 상대 경로로 바꾼다.
    final normalized = assetOrUrl.startsWith('assets/')
        ? assetOrUrl.substring('assets/'.length)
        : assetOrUrl;
    return ap.AssetSource(normalized);
  }
}
