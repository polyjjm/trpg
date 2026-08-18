import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// SceneFrame 하단 시트의 TTS 토글이 쓰는 얇은 재생 래퍼. flutter_tts 인스턴스
/// 하나를 감싸 play/pause/stop과 "지금 재생 중인지" 스트림만 노출한다 —
/// 어떤 텍스트를 읽을지(블록별 ttsOverride 우선순위 등)는 호출부(SceneFrame)의
/// 몫이고, 여기는 순수 재생 담당이다(AudioService가 BGM/SFX에 대해 갖는 것과
/// 같은 역할 분리).
class TtsController {
  TtsController() {
    _tts.setLanguage('ko-KR');
    _tts.setCompletionHandler(() => _setPlaying(false));
    _tts.setCancelHandler(() => _setPlaying(false));
    _tts.setErrorHandler((message) => _setPlaying(false));
  }

  final FlutterTts _tts = FlutterTts();
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  Stream<bool> get playingStream => _playingController.stream;

  void _setPlaying(bool playing) {
    if (_isPlaying == playing) return;
    _isPlaying = playing;
    _playingController.add(playing);
  }

  Future<void> play(String text) async {
    if (text.trim().isEmpty) return;
    _setPlaying(true);
    await _tts.speak(text);
  }

  /// 일부 플랫폼(웹 등)은 일시정지를 지원하지 않는다 — 그런 경우 정지로 대신한다.
  Future<void> pause() async {
    try {
      final result = await _tts.pause();
      if (result != 1) {
        await _tts.stop();
      }
    } catch (_) {
      await _tts.stop();
    }
    _setPlaying(false);
  }

  Future<void> stop() async {
    await _tts.stop();
    _setPlaying(false);
  }

  void dispose() {
    _tts.stop();
    _playingController.close();
  }
}
