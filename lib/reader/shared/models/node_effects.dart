/// storyPacks/{packId}/nodes/{nodeId}.effects — 리더 전용 파싱 모델. admin
/// 쪽 NodeEffects(lib/admin/models/node_effects.dart)와 같은 필드를 담지만,
/// 리더는 절대 lib/admin/을 import하지 않는다(모바일 빌드에서 admin 코드를
/// 끌고 들어가지 않기 위해서 — CLAUDE.md "Writer/admin web tool" 참고)는
/// 원칙 때문에 StoryNode(story_node.dart)처럼 별개 클래스로 다시 둔다.
/// 여기서는 재생에 필요한 값(초/픽셀/Color/enum)만 다루고, toJson/copyWith
/// 같은 편집기 전용 기능은 없다 — 리더는 읽기만 한다.
library;

import 'package:flutter/material.dart' show Color, Colors;

enum BlackoutDurationPreset { half, one, two }

extension BlackoutDurationPresetPlayback on BlackoutDurationPreset {
  Duration get duration => switch (this) {
    BlackoutDurationPreset.half => const Duration(milliseconds: 500),
    BlackoutDurationPreset.one => const Duration(milliseconds: 1000),
    BlackoutDurationPreset.two => const Duration(milliseconds: 2000),
  };

  static BlackoutDurationPreset fromWire(String? value) {
    return switch (value) {
      '0.5s' => BlackoutDurationPreset.half,
      '2s' => BlackoutDurationPreset.two,
      _ => BlackoutDurationPreset.one,
    };
  }
}

enum ShakeIntensityPreset { weak, normal, strong }

extension ShakeIntensityPresetPlayback on ShakeIntensityPreset {
  /// 흔들림 진폭(px) — 강도별로 다르지만, 지속 시간(SceneFrame의
  /// _shakeController)은 강도와 무관하게 항상 고정이다(요청 사양).
  double get amplitudePx => switch (this) {
    ShakeIntensityPreset.weak => 4,
    ShakeIntensityPreset.normal => 8,
    ShakeIntensityPreset.strong => 14,
  };

  static ShakeIntensityPreset fromWire(String? value) {
    return switch (value) {
      '약하게' => ShakeIntensityPreset.weak,
      '강하게' => ShakeIntensityPreset.strong,
      _ => ShakeIntensityPreset.normal,
    };
  }
}

enum FlashColorPreset { red, white, blue }

extension FlashColorPresetPlayback on FlashColorPreset {
  /// 화면 전체를 완전히 덮는 blackout과 달리, 플래시는 배경/텍스트가 살짝
  /// 비치는 반투명이어야 "번쩍임"으로 읽힌다 — 그래서 셋 다 완전 불투명이
  /// 아니라 40~55% 알파를 쓴다(하양은 대비가 약해서 조금 더 진하게).
  Color get color => switch (this) {
    FlashColorPreset.red => Colors.red.withOpacity(0.45),
    FlashColorPreset.white => Colors.white.withOpacity(0.55),
    FlashColorPreset.blue => Colors.lightBlue.withOpacity(0.4),
  };

  static FlashColorPreset fromWire(String? value) {
    return switch (value) {
      '하양(섬광)' => FlashColorPreset.white,
      '파랑(냉기)' => FlashColorPreset.blue,
      _ => FlashColorPreset.red,
    };
  }
}

enum FlashDurationPreset { short, normal, long }

extension FlashDurationPresetPlayback on FlashDurationPreset {
  Duration get duration => switch (this) {
    FlashDurationPreset.short => const Duration(milliseconds: 150),
    FlashDurationPreset.normal => const Duration(milliseconds: 300),
    FlashDurationPreset.long => const Duration(milliseconds: 500),
  };

  static FlashDurationPreset fromWire(String? value) {
    return switch (value) {
      '짧게' => FlashDurationPreset.short,
      '길게' => FlashDurationPreset.long,
      _ => FlashDurationPreset.normal,
    };
  }
}

enum HapticDurationPreset { short, long }

extension HapticDurationPresetPlayback on HapticDurationPreset {
  static HapticDurationPreset fromWire(String? value) {
    return value == '길게'
        ? HapticDurationPreset.long
        : HapticDurationPreset.short;
  }
}

class BlackoutEffect {
  final bool enabled;
  final BlackoutDurationPreset durationPreset;

  const BlackoutEffect({
    this.enabled = false,
    this.durationPreset = BlackoutDurationPreset.one,
  });

  factory BlackoutEffect.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BlackoutEffect();
    return BlackoutEffect(
      enabled: json['enabled'] as bool? ?? false,
      durationPreset: BlackoutDurationPresetPlayback.fromWire(
        json['durationPreset'] as String?,
      ),
    );
  }
}

class ShakeEffect {
  final bool enabled;
  final ShakeIntensityPreset intensityPreset;

  const ShakeEffect({
    this.enabled = false,
    this.intensityPreset = ShakeIntensityPreset.normal,
  });

  factory ShakeEffect.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ShakeEffect();
    return ShakeEffect(
      enabled: json['enabled'] as bool? ?? false,
      intensityPreset: ShakeIntensityPresetPlayback.fromWire(
        json['intensityPreset'] as String?,
      ),
    );
  }
}

/// [sfxId]는 sfxLibrary/{sfxId} 참조다(URL 아님) — StoryReaderRepository가
/// images와 같은 join 패턴으로 storageUrl을 resolve해 ResolvedStoryNode.sfxUrl에
/// 담아 준다. SceneFrame은 이 sfxId를 직접 쓰지 않고 그 resolve된 URL만 받는다.
class SfxEffect {
  final bool enabled;
  final String? sfxId;

  const SfxEffect({this.enabled = false, this.sfxId});

  factory SfxEffect.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SfxEffect();
    return SfxEffect(
      enabled: json['enabled'] as bool? ?? false,
      sfxId: json['sfxId'] as String?,
    );
  }
}

class FlashEffect {
  final bool enabled;
  final FlashColorPreset colorPreset;
  final FlashDurationPreset durationPreset;

  const FlashEffect({
    this.enabled = false,
    this.colorPreset = FlashColorPreset.red,
    this.durationPreset = FlashDurationPreset.normal,
  });

  factory FlashEffect.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FlashEffect();
    return FlashEffect(
      enabled: json['enabled'] as bool? ?? false,
      colorPreset: FlashColorPresetPlayback.fromWire(
        json['colorPreset'] as String?,
      ),
      durationPreset: FlashDurationPresetPlayback.fromWire(
        json['durationPreset'] as String?,
      ),
    );
  }
}

class HapticEffect {
  final bool enabled;
  final HapticDurationPreset durationPreset;

  const HapticEffect({
    this.enabled = false,
    this.durationPreset = HapticDurationPreset.short,
  });

  factory HapticEffect.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HapticEffect();
    return HapticEffect(
      enabled: json['enabled'] as bool? ?? false,
      durationPreset: HapticDurationPresetPlayback.fromWire(
        json['durationPreset'] as String?,
      ),
    );
  }
}

/// [sfxId]는 sfxLibrary/{sfxId} 참조인 것과 똑같이 [bgmId]는 bgmLibrary/{bgmId}
/// 참조다 — StoryReaderRepository가 같은 join 패턴으로 storageUrl을 resolve해
/// ResolvedStoryNode.bgmUrl에 담아 준다.
///
/// 나머지 다섯 효과(blackout/shake/sfx/flash/haptic)와 달리 "enabled" 불리언이
/// 없다 — 이 값이 아예 null인지 아닌지 자체가 의미를 가진다(node_effects.dart
/// 관례: 노드 문서에 `effects.bgm` 필드가 없거나 null이면 "이전과 동일(상속)",
/// 있으면 이 값이 지시하는 대로 트랙 전환/무음 전환을 한다). BGM 재생/전환
/// 판단은 SceneFrame이 아니라 리더 페이지(InteractiveReader/LinearReader)가
/// BgmSessionController로 한다 — SceneFrame은 노드가 바뀔 때마다 새로 만들어져
/// "지금 재생 중인 BGM"이라는 세션 상태를 들고 있을 수 없기 때문이다
/// (lib/reader/shared/bgm_session_controller.dart 참고).
class BgmEffect {
  /// 전환할 트랙 — [silence]가 true면 이 값은 무시된다.
  final String? bgmId;

  /// true면 [bgmId]와 무관하게 지금 재생 중인 BGM을 무음으로 페이드아웃한다.
  final bool silence;

  /// 0.0~1.0, 기본 1.0 — [bgmId]가 설정돼 있을 때만 의미가 있다. 크로스페이드가
  /// (또는 같은 트랙이 이어지는 채로 볼륨만 바뀔 때는 짧은 볼륨 전환이) 끝난
  /// 뒤 정착할 목표 볼륨 — `AudioService.crossfadeToBgm`/`adjustBgmVolume`이
  /// "완전히 페이드인된 상태"를 항상 1.0이 아니라 이 값으로 취급한다
  /// (bgm_session_controller.dart 참고).
  final double volume;

  const BgmEffect({this.bgmId, this.silence = false, this.volume = 1.0});

  /// json이 null이면(필드 자체가 없거나 명시적으로 null) "상속" — 반드시 null을
  /// 돌려준다. 다른 Effect들의 `fromJson(null) → 기본값 인스턴스`와 다른
  /// 유일한 이유다.
  static BgmEffect? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return BgmEffect(
      bgmId: json['bgmId'] as String?,
      silence: json['silence'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class NodeEffects {
  final BlackoutEffect blackout;
  final ShakeEffect shake;
  final SfxEffect sfx;
  final FlashEffect flash;
  final HapticEffect haptic;
  final BgmEffect? bgm;

  const NodeEffects({
    this.blackout = const BlackoutEffect(),
    this.shake = const ShakeEffect(),
    this.sfx = const SfxEffect(),
    this.flash = const FlashEffect(),
    this.haptic = const HapticEffect(),
    this.bgm,
  });

  factory NodeEffects.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NodeEffects();
    return NodeEffects(
      blackout: BlackoutEffect.fromJson(
        json['blackout'] as Map<String, dynamic>?,
      ),
      shake: ShakeEffect.fromJson(json['shake'] as Map<String, dynamic>?),
      sfx: SfxEffect.fromJson(json['sfx'] as Map<String, dynamic>?),
      flash: FlashEffect.fromJson(json['flash'] as Map<String, dynamic>?),
      haptic: HapticEffect.fromJson(json['haptic'] as Map<String, dynamic>?),
      bgm: BgmEffect.fromJson(json['bgm'] as Map<String, dynamic>?),
    );
  }
}
