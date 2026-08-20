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

class NodeEffects {
  final BlackoutEffect blackout;
  final ShakeEffect shake;
  final SfxEffect sfx;
  final FlashEffect flash;
  final HapticEffect haptic;

  const NodeEffects({
    this.blackout = const BlackoutEffect(),
    this.shake = const ShakeEffect(),
    this.sfx = const SfxEffect(),
    this.flash = const FlashEffect(),
    this.haptic = const HapticEffect(),
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
    );
  }
}
