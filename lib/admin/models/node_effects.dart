/// 노드 연출 효과 — 프리셋 전용(자유 설정 없음)이라 작가가 값을 몰라도
/// 안전하게 고를 수 있다. 실제 재생(사운드 파일, 진동 API 연동)은 나중
/// 패스의 몫이고, 지금은 리더에 아직 반영되지 않는 "작가의 의도 기록"일
/// 뿐이다 — SceneFrame(lib/reader/shared/scene_frame.dart)이 이걸 실제로
/// 재생하게 만드는 건 별도 작업이다.
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
  final HapticEffect haptic;

  const NodeEffects({
    this.blackout = const BlackoutEffect(),
    this.shake = const ShakeEffect(),
    this.sfx = const SfxEffect(),
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
      haptic: HapticEffect.fromJson(json['haptic'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() => {
    'blackout': blackout.toJson(),
    'shake': shake.toJson(),
    'sfx': sfx.toJson(),
    'haptic': haptic.toJson(),
  };

  NodeEffects copyWith({
    BlackoutEffect? blackout,
    ShakeEffect? shake,
    SfxEffect? sfx,
    HapticEffect? haptic,
  }) {
    return NodeEffects(
      blackout: blackout ?? this.blackout,
      shake: shake ?? this.shake,
      sfx: sfx ?? this.sfx,
      haptic: haptic ?? this.haptic,
    );
  }
}
