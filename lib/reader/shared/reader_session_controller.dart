import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/audio/audio_service.dart';
import 'models/node_effects.dart';

/// 리딩 세션(팩을 열어 리더 화면에 들어온 순간부터 나갈 때까지) 동안 세 가지
/// "이 세션이 지금 어떤 상태인지"를 들고 있는다 — (1) BGM: 지금 재생 중인
/// bgmId(예전 BgmSessionController의 역할, 그대로), (2) 내레이션이 사용자
/// 의도로 켜져 있는지([ttsUserEnabled] — 노드가 바뀌어도 유지된다), (3) 지금
/// 노드의 내레이션이 끝나면 자동으로 다음 노드로 "넘어갈지"([_autoContinueTarget]/
/// [_autoContinueEnabled] — (2)와는 별개다: (2)는 "TTS 소리 자체가 계속
/// 나올지", (3)은 "내레이션이 끝났을 때 화면을 자동으로 넘길지"를 묻는다).
/// 원래 BGM 전용이던 클래스를 여기로 확장했다(요청 사양 Part 2: "implement
/// it in the same reader session controller that already manages BGM
/// continuity, not as a one-off special case") — 두 기능 다 "노드가 바뀔
/// 때마다 갱신되는 세션 상태"라는 같은 성격이라, 서로 다른 두 컨트롤러가
/// 각자 따로 도는 것보다 한 곳에서 조율하는 편이 일관적이다.
///
/// InteractiveReader/LinearReader가 각자 자기 State 안에 하나씩 만들어서
/// 리더 페이지의 생명주기 동안 들고 있는다 — SceneFrame이 아니다. SceneFrame은
/// 노드가 바뀔 때마다(key가 바뀌며) 완전히 새로 만들어지는 위젯이라 "지금
/// 재생 중인 BGM이 뭔지"/"자동 이어재생이 켜져 있는지" 같은 세션 상태를
/// 이어서 들고 있을 수 없다. 같은 이유로, 다른 다섯 연출 효과(blackout/
/// shake/sfx/flash/haptic)는 "본문 타이핑이 끝나는 시점"에 SceneFrame이
/// 트리거하지만, BGM은 그 타이밍을 따르지 않는다 — BGM은 "다 읽고 나서"
/// 바뀌는 게 아니라 장면에 들어서자마자 깔리는 배경 음향에 가깝고, 무엇보다
/// 그 트리거를 SceneFrame에 맡기면 세션 상태를 SceneFrame 쪽으로 옮겨야
/// 해서 리더 페이지가 노드를 넘길 때(_currentNodeId가 바뀌는 시점)를 그대로
/// 트리거 지점으로 쓴다. 내레이션 자동 이어재생은 반대로 SceneFrame이
/// "내레이션이 끝까지 재생됐다"는 신호를 줘야만 판단할 수 있는 일이라(그
/// 신호 자체는 SceneFrame 안의 NodeTtsPlaybackController.allCompletedStream이
/// 낸다), [handleNarrationCompleted]는 SceneFrame의 콜백을 받아 부른다 —
/// 노드를 바꾸는 실제 동작(화면 전환/재생 시작)은 이 컨트롤러가 위젯 트리를
/// 모르므로 호출부(리더 페이지)에 콜백으로 넘긴다.
class ReaderSessionController {
  // ── BGM (예전 BgmSessionController 그대로) ────────────────────────────
  String? _currentBgmId;

  /// 지금 재생 중인 트랙에 마지막으로 적용한 목표 볼륨 — 다음 노드가 같은
  /// `bgmId`를 계속 쓰면서 `volume`만 바꿨는지 판단하는 기준이다. 재생 중인
  /// 트랙이 없으면(상속 폴백 전이거나 무음 전환 직후) null.
  double? _currentVolume;

  bool _sessionStarted = false;

  // ── 내레이션 자동 이어재생 ───────────────────────────────────────────
  /// 기본 켜짐(요청 사양: "auto-continue should be the default behavior but
  /// not forced") — 리더 페이지가 ReaderPrefs 스트림을 받을 때마다
  /// [setAutoContinueEnabled]로 최신 값을 밀어 넣는다(AudioService.
  /// setBgmMasterVolume과 같은 패턴).
  bool _autoContinueEnabled = true;

  /// 지금 화면의 내레이션이 끝까지 재생되면 자동으로 넘어갈 다음 노드 —
  /// null이면 자동으로 넘어갈 곳이 없다(선택지 분기점, 마지막 노드 등).
  /// [visitNode]와 같은 시점에 [setAutoContinueTarget]으로 갱신된다.
  String? _autoContinueTarget;

  /// 사용자가 TTS를 직접 켰는지(의도) — SceneFrame 위젯 하나의 재생 상태
  /// (`_ttsPlaying`)와는 다른 개념이다. `_ttsPlaying`은 내레이션이 자연
  /// 종료되기만 해도(사용자가 끈 게 아니어도) `false`가 되지만, 이 값은
  /// 사용자가 TTS 버튼을 직접 눌러 켜거나 끌 때만 바뀐다 — 그래서 "TTS를
  /// 한 번 켜 두면 다음 노드로 넘어가도(자동 이어재생이든, 직접 선택지를
  /// 눌러서든) 계속 들린다"를 정확히 표현한다. 리더 페이지는 새 노드를
  /// 보여줄 SceneFrame을 만들 때마다 이 값을 그대로 `autoPlayNarration`에
  /// 흘려보낸다 — 노드 전환 경로(자동 이어재생/선택지 직접 탭/"다음" 버튼)와
  /// 무관하게 항상 같은 값을 본다.
  bool _ttsUserEnabled = false;
  bool get ttsUserEnabled => _ttsUserEnabled;

  void setTtsUserEnabled(bool enabled) {
    _ttsUserEnabled = enabled;
  }

  void setAutoContinueEnabled(bool enabled) {
    _autoContinueEnabled = enabled;
  }

  void setAutoContinueTarget(String? nodeId) {
    _autoContinueTarget = nodeId;
  }

  /// SceneFrame의 내레이션 재생목록이 (일시정지가 아니라) 끝까지 자연
  /// 재생됐을 때 리더 페이지가 부른다 — 자동 이어재생이 켜져 있고 다음
  /// 대상이 있으면 [onAdvance]를 그 대상 id로 부른다. 노드가 없으면(꺼져
  /// 있거나, 선택지 분기점이라 대상이 없거나) 아무 것도 하지 않는다 —
  /// 조용히 멈추고 리더가 직접 다음으로 넘어가길 기다린다.
  void handleNarrationCompleted(ValueChanged<String> onAdvance) {
    final target = _autoContinueTarget;
    if (_autoContinueEnabled && target != null) {
      onAdvance(target);
    }
  }

  /// 노드를 새로 보여줄 때마다 부른다(리더 페이지가 `_currentNodeId`를 바꾸는
  /// 모든 지점 — 최초 진입/선택지 선택/다음 페이지/처음부터). 이 세션에서
  /// 처음 부르는 호출인지 스스로 판단해서, "상속"인데 아직 아무 것도 재생
  /// 중이 아니면 그때만 [defaultBgmId]/[defaultBgmUrl](storyPacks.defaultBgmId)로
  /// 폴백한다 — 두 번째 호출부터는 상속이어도 이미 재생 중인 트랙을 그대로
  /// 둔다(요청 사양: defaultBgmId는 세션 시작 시점에만 적용되고, 노드가
  /// BGM을 안 정했다고 매번 다시 적용되지 않는다).
  void visitNode({
    required BgmEffect? nodeBgm,
    required String? nodeBgmUrl,
    required String? defaultBgmId,
    required String? defaultBgmUrl,
  }) {
    final isSessionStart = !_sessionStarted;
    _sessionStarted = true;

    if (nodeBgm == null) {
      // 상속 — 이미 재생 중인 트랙을 그대로 둔다. 딱 하나 예외: 세션의
      // 첫 노드이고 아직 아무 것도 안 정해졌으면 팩의 기본 BGM으로 시작한다.
      // storyPacks.defaultBgmId엔 노드별 volume 개념이 없어서 기본 100%로 튼다.
      if (isSessionStart && defaultBgmId != null) {
        _currentBgmId = defaultBgmId;
        _currentVolume = 1.0;
        if (defaultBgmUrl != null && defaultBgmUrl.isNotEmpty) {
          unawaited(AudioService.instance.crossfadeToBgm(defaultBgmUrl));
        }
      }
      return;
    }

    if (nodeBgm.silence) {
      _currentBgmId = null;
      _currentVolume = null;
      unawaited(AudioService.instance.fadeOutBgm());
      return;
    }

    final bgmId = nodeBgm.bgmId;
    if (bgmId == null) return;

    if (bgmId == _currentBgmId) {
      // 트랙 자체는 그대로 이어진다 — "바뀌지 않았다"로 취급하지 않는다.
      // volume만 다르면(가장 흔한 경우인 "둘 다 같음"이 아니라면) 트랙을
      // 다시 걸지 않고 짧은 볼륨 전환만 한다(크로스페이드를 다시 태우면
      // crossfadeToBgm이 "같은 URL"이라 조용히 무시해 버리므로, 볼륨
      // 변경은 반드시 이 경로를 타야 한다).
      if (_currentVolume != nodeBgm.volume) {
        _currentVolume = nodeBgm.volume;
        unawaited(AudioService.instance.adjustBgmVolume(nodeBgm.volume));
      }
      return;
    }

    _currentBgmId = bgmId;
    _currentVolume = nodeBgm.volume;
    if (nodeBgmUrl != null && nodeBgmUrl.isNotEmpty) {
      unawaited(
        AudioService.instance.crossfadeToBgm(
          nodeBgmUrl,
          volume: nodeBgm.volume,
        ),
      );
    }
  }

  /// 리더 화면을 나갈 때(State.dispose) 부른다 — 다음 화면(카탈로그 등)까지
  /// 이 팩의 BGM이 계속 들리지 않도록 무음으로 정리한다.
  void dispose() {
    unawaited(AudioService.instance.fadeOutBgm());
  }
}
