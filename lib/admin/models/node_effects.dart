/// 노드 연출 효과 — 프리셋 전용(자유 설정 없음)이라 작가가 값을 몰라도
/// 안전하게 고를 수 있다. 다섯 종(암전/화면 흔들림/효과음/화면 플래시/진동)
/// 전부 SceneFrame(lib/reader/shared/scene_frame.dart)이 실제로 재생한다 —
/// 리더는 이 파일을 직접 쓰지 않고, 같은 필드를 다시 파싱하는 별개 모델
/// (lib/reader/shared/models/node_effects.dart)로 읽는다(admin 코드를 리더
/// 빌드에 끌고 들어가지 않기 위해서 — CLAUDE.md 참고).
library;

enum BlackoutDurationPreset { half, one, two }

extension BlackoutDurationPresetJson on BlackoutDurationPreset {
  String get wireValue => switch (this) {
    BlackoutDurationPreset.half => '0.5s',
    BlackoutDurationPreset.one => '1s',
    BlackoutDurationPreset.two => '2s',
  };

  String get label => wireValue;

  static BlackoutDurationPreset fromWire(String? value) {
    return BlackoutDurationPreset.values.firstWhere(
      (p) => p.wireValue == value,
      orElse: () => BlackoutDurationPreset.one,
    );
  }
}

enum ShakeIntensityPreset { weak, normal, strong }

extension ShakeIntensityPresetJson on ShakeIntensityPreset {
  String get wireValue => switch (this) {
    ShakeIntensityPreset.weak => '약하게',
    ShakeIntensityPreset.normal => '보통',
    ShakeIntensityPreset.strong => '강하게',
  };

  String get label => wireValue;

  static ShakeIntensityPreset fromWire(String? value) {
    return ShakeIntensityPreset.values.firstWhere(
      (p) => p.wireValue == value,
      orElse: () => ShakeIntensityPreset.normal,
    );
  }
}

enum FlashColorPreset { red, white, blue }

extension FlashColorPresetJson on FlashColorPreset {
  String get wireValue => switch (this) {
    FlashColorPreset.red => '빨강(피격)',
    FlashColorPreset.white => '하양(섬광)',
    FlashColorPreset.blue => '파랑(냉기)',
  };

  String get label => wireValue;

  static FlashColorPreset fromWire(String? value) {
    return FlashColorPreset.values.firstWhere(
      (p) => p.wireValue == value,
      orElse: () => FlashColorPreset.red,
    );
  }
}

enum FlashDurationPreset { short, normal, long }

extension FlashDurationPresetJson on FlashDurationPreset {
  String get wireValue => switch (this) {
    FlashDurationPreset.short => '짧게',
    FlashDurationPreset.normal => '보통',
    FlashDurationPreset.long => '길게',
  };

  String get label => wireValue;

  static FlashDurationPreset fromWire(String? value) {
    return FlashDurationPreset.values.firstWhere(
      (p) => p.wireValue == value,
      orElse: () => FlashDurationPreset.normal,
    );
  }
}

enum HapticDurationPreset { short, long }

extension HapticDurationPresetJson on HapticDurationPreset {
  String get wireValue => switch (this) {
    HapticDurationPreset.short => '짧게',
    HapticDurationPreset.long => '길게',
  };

  String get label => wireValue;

  static HapticDurationPreset fromWire(String? value) {
    return HapticDurationPreset.values.firstWhere(
      (p) => p.wireValue == value,
      orElse: () => HapticDurationPreset.short,
    );
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
      durationPreset: BlackoutDurationPresetJson.fromWire(
        json['durationPreset'] as String?,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'durationPreset': durationPreset.wireValue,
  };

  BlackoutEffect copyWith({
    bool? enabled,
    BlackoutDurationPreset? durationPreset,
  }) {
    return BlackoutEffect(
      enabled: enabled ?? this.enabled,
      durationPreset: durationPreset ?? this.durationPreset,
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
      intensityPreset: ShakeIntensityPresetJson.fromWire(
        json['intensityPreset'] as String?,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'intensityPreset': intensityPreset.wireValue,
  };

  ShakeEffect copyWith({bool? enabled, ShakeIntensityPreset? intensityPreset}) {
    return ShakeEffect(
      enabled: enabled ?? this.enabled,
      intensityPreset: intensityPreset ?? this.intensityPreset,
    );
  }
}

/// [sfxId]는 sfxLibrary/{sfxId} 참조다(URL 아님) — images의 backgroundImage와
/// 같은 패턴. 프리셋 고정값이었던 예전 SfxPreset 대신, 작가가 효과음
/// 라이브러리(sfx_library_tab.dart)에 업로드한 실제 파일을 가리킨다.
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

  Map<String, dynamic> toJson() => {'enabled': enabled, 'sfxId': sfxId};

  /// sfxId는 다른 프리셋 필드와 달리 "선택 해제"가 곧 null이라, 일반적인
  /// `sfxId ?? this.sfxId` 패턴을 쓰면 null로 되돌릴 방법이 없어진다 —
  /// [clearSfxId]를 true로 주면 [sfxId] 인자와 무관하게 null로 지운다.
  SfxEffect copyWith({bool? enabled, String? sfxId, bool clearSfxId = false}) {
    return SfxEffect(
      enabled: enabled ?? this.enabled,
      sfxId: clearSfxId ? null : (sfxId ?? this.sfxId),
    );
  }
}

/// 피격/섬광/냉기처럼 색으로 의미가 갈리는 화면 플래시 — 순간적으로 색이
/// 확 들어왔다 durationPreset에 걸쳐 빠지는 연출이다. blackout(암전)과 같은
/// "화면 전체 오버레이" 계열이지만 색이 검정 고정이 아니라 프리셋으로
/// 고른다는 점이 다르다 — 그래서 durationPreset도 blackout과 값 구간이 달라
/// (0.5s/1s/2s가 아니라 짧게/보통/길게) 별개 enum(FlashDurationPreset)을 쓴다.
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
      colorPreset: FlashColorPresetJson.fromWire(
        json['colorPreset'] as String?,
      ),
      durationPreset: FlashDurationPresetJson.fromWire(
        json['durationPreset'] as String?,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'colorPreset': colorPreset.wireValue,
    'durationPreset': durationPreset.wireValue,
  };

  FlashEffect copyWith({
    bool? enabled,
    FlashColorPreset? colorPreset,
    FlashDurationPreset? durationPreset,
  }) {
    return FlashEffect(
      enabled: enabled ?? this.enabled,
      colorPreset: colorPreset ?? this.colorPreset,
      durationPreset: durationPreset ?? this.durationPreset,
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
      durationPreset: HapticDurationPresetJson.fromWire(
        json['durationPreset'] as String?,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'durationPreset': durationPreset.wireValue,
  };

  HapticEffect copyWith({bool? enabled, HapticDurationPreset? durationPreset}) {
    return HapticEffect(
      enabled: enabled ?? this.enabled,
      durationPreset: durationPreset ?? this.durationPreset,
    );
  }
}

/// storyPacks/{packId}/nodes/{nodeId}.effects — 넷 다 선택적이고 기본은
/// 꺼짐이다. 문서에 effects 필드 자체가 없는 기존 노드도 전부 꺼진
/// 기본값으로 읽힌다(fromJson(null)).
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

  Map<String, dynamic> toJson() => {
    'blackout': blackout.toJson(),
    'shake': shake.toJson(),
    'sfx': sfx.toJson(),
    'flash': flash.toJson(),
    'haptic': haptic.toJson(),
  };

  NodeEffects copyWith({
    BlackoutEffect? blackout,
    ShakeEffect? shake,
    SfxEffect? sfx,
    FlashEffect? flash,
    HapticEffect? haptic,
  }) {
    return NodeEffects(
      blackout: blackout ?? this.blackout,
      shake: shake ?? this.shake,
      sfx: sfx ?? this.sfx,
      flash: flash ?? this.flash,
      haptic: haptic ?? this.haptic,
    );
  }
}
