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

/// [sfxId]가 sfxLibrary/{sfxId} 참조인 것과 똑같이 [bgmId]는 bgmLibrary/{bgmId}
/// 참조다. 나머지 다섯 효과와 달리 "enabled" 불리언이 없다 — 이 값이 아예
/// null인지 아닌지 자체가 "이전과 동일(상속)" vs "지시대로 전환/무음"을
/// 가른다(리더 쪽 lib/reader/shared/models/node_effects.dart의 같은 클래스
/// doc 참고 — 재생 판단 로직도 그쪽에 있다). 그래서 이 클래스의 세 상태
/// (상속/트랙 선택/무음 전환)는 필드 조합이 아니라 "이 객체 자체가
/// null인가/silence가 true인가/아닌가"로 표현된다 — NodeEffectsEditor의
/// 라디오 3종 UI가 정확히 이 세 값을 왕복한다.
class BgmEffect {
  final String? bgmId;
  final bool silence;

  /// 0.0~1.0, 기본 1.0(원본 볼륨 그대로) — 이 노드가 재생 중일 때 크로스페이드가
  /// 끝난 뒤 정착할 목표 볼륨. [bgmId]가 설정돼 있을 때만(= "트랙 선택" 상태일
  /// 때만) 의미가 있다 — "이전과 동일"/"무음으로 전환"에서는 볼륨 슬라이더
  /// 자체가 UI에 안 보인다(NodeEffectsEditor의 _BgmEffectRow 참고). 대사가
  /// 많은 장면에서 같은 트랙을 계속 쓰되 볼륨만 낮추는 용도 — 조용한 버전을
  /// 따로 마스터링해 별도 트랙으로 올릴 필요가 없다.
  final double volume;

  const BgmEffect({this.bgmId, this.silence = false, this.volume = 1.0});

  factory BgmEffect.fromJson(Map<String, dynamic> json) {
    return BgmEffect(
      bgmId: json['bgmId'] as String?,
      silence: json['silence'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'bgmId': bgmId,
    'silence': silence,
    'volume': volume,
  };

  BgmEffect copyWith({String? bgmId, bool? silence, double? volume}) {
    return BgmEffect(
      bgmId: bgmId ?? this.bgmId,
      silence: silence ?? this.silence,
      volume: volume ?? this.volume,
    );
  }
}

/// Typecast의 감정 프리셋 — https://typecast.ai/docs/api-reference/
/// text-to-speech/text-to-speech의 `EmotionEnum`(ssfm-v30 기준)과 대조
/// 확인해서 실제 값으로 맞췄다: normal/happy/sad/angry/whisper/toneup/
/// tonedown 7종. surprise/fear는 Typecast에 존재하지 않는 값이었다(대조 전
/// 최선의 추측으로 넣었던 것 — 삭제). toneup/tonedown은 ssfm-v21에는 없고
/// ssfm-v30에서만 지원돼서, functions/src/index.ts의 `callTypecastTts`도
/// model을 ssfm-v30으로 맞춰 뒀다 — 이 enum과 그쪽 model 값은 반드시 같이
/// 바뀌어야 한다(ssfm-v21로 되돌리면 whisper/toneup/tonedown 요청이 거부된다).
enum TtsEmotionPreset { normal, happy, sad, angry, whisper, toneup, tonedown }

extension TtsEmotionPresetJson on TtsEmotionPreset {
  String get wireValue => switch (this) {
    TtsEmotionPreset.normal => 'normal',
    TtsEmotionPreset.happy => 'happy',
    TtsEmotionPreset.sad => 'sad',
    TtsEmotionPreset.angry => 'angry',
    TtsEmotionPreset.whisper => 'whisper',
    TtsEmotionPreset.toneup => 'toneup',
    TtsEmotionPreset.tonedown => 'tonedown',
  };

  String get label => switch (this) {
    TtsEmotionPreset.normal => '보통',
    TtsEmotionPreset.happy => '기쁨',
    TtsEmotionPreset.sad => '슬픔',
    TtsEmotionPreset.angry => '화남',
    TtsEmotionPreset.whisper => '속삭임',
    TtsEmotionPreset.toneup => '톤 업(밝게)',
    TtsEmotionPreset.tonedown => '톤 다운(차분하게)',
  };

  static TtsEmotionPreset? fromWire(String? value) {
    if (value == null) return null;
    for (final preset in TtsEmotionPreset.values) {
      if (preset.wireValue == value) return preset;
    }
    return null;
  }
}

/// [voiceId]가 null이면 팩의 기본 내레이터 보이스(storyPacks.defaultTtsVoiceId)를
/// 그대로 쓴다는 뜻 — bgmId가 없을 때 팩 기본 배경음을 쓰는 것과 같은 패턴이다.
/// [emotion]이 null이면 Typecast의 Smart Emotion(자동 감정 추론)에 맡긴다 —
/// 이때 [emotionIntensity]는 의미가 없다(UI에도 emotion을 골랐을 때만
/// 슬라이더가 보인다). [pitch]/[tempo]는 항상 적용된다(중립값이 0/1.0).
///
/// BgmEffect와 달리 "노드 간 이어짐(상속)" 개념이 없다 — 내레이션은 노드마다
/// 독립적으로 생성되는 콘텐츠라, 이 필드 자체가 null이어도 "이전 노드 설정을
/// 이어받는다"는 뜻이 아니라 그냥 "이 노드는 커스터마이즈 없이 팩 기본값 +
/// 자동 감정 + 중립 피치/템포로 생성한다"는 뜻이다.
class TtsEffect {
  final String? voiceId;
  final TtsEmotionPreset? emotion;

  /// 0.0~2.0, 기본 1.0 — [emotion]이 설정됐을 때만 의미가 있다.
  final double emotionIntensity;

  /// -12~12(반음 단위), 기본 0.
  final double pitch;

  /// 0.5~2.0, 기본 1.0.
  final double tempo;

  const TtsEffect({
    this.voiceId,
    this.emotion,
    this.emotionIntensity = 1.0,
    this.pitch = 0,
    this.tempo = 1.0,
  });

  factory TtsEffect.fromJson(Map<String, dynamic> json) {
    return TtsEffect(
      voiceId: json['voiceId'] as String?,
      emotion: TtsEmotionPresetJson.fromWire(json['emotion'] as String?),
      emotionIntensity: (json['emotionIntensity'] as num?)?.toDouble() ?? 1.0,
      pitch: (json['pitch'] as num?)?.toDouble() ?? 0,
      tempo: (json['tempo'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'voiceId': voiceId,
    'emotion': emotion?.wireValue,
    'emotionIntensity': emotionIntensity,
    'pitch': pitch,
    'tempo': tempo,
  };

  /// [voiceId]/[emotion]은 다른 nullable 필드들과 같은 이유로 clear 플래그가
  /// 필요하다 — null ?? 패턴만으로는 "명시적으로 null로 되돌리기"를 표현할
  /// 수 없다.
  TtsEffect copyWith({
    String? voiceId,
    bool clearVoiceId = false,
    TtsEmotionPreset? emotion,
    bool clearEmotion = false,
    double? emotionIntensity,
    double? pitch,
    double? tempo,
  }) {
    return TtsEffect(
      voiceId: clearVoiceId ? null : (voiceId ?? this.voiceId),
      emotion: clearEmotion ? null : (emotion ?? this.emotion),
      emotionIntensity: emotionIntensity ?? this.emotionIntensity,
      pitch: pitch ?? this.pitch,
      tempo: tempo ?? this.tempo,
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

  /// null이면 "이전과 동일(기본값)" — 상속. NodeEffectsEditor.copyWith가
  /// 이 필드를 지우려면(상속으로 되돌리려면) 반드시 [clearBgm]을 써야 한다 —
  /// SfxEffect.clearSfxId와 같은 이유(null ?? 패턴으로는 "명시적으로
  /// null로 되돌리기"를 표현할 수 없다).
  final BgmEffect? bgm;

  /// null이면 "커스터마이즈 없음(팩 기본 보이스 + 자동 감정 + 중립 피치/템포)".
  /// TtsEffect 클래스 doc 참고 — bgm과 달리 "이전 노드에서 이어받는다"는
  /// 뜻이 아니다.
  final TtsEffect? tts;

  const NodeEffects({
    this.blackout = const BlackoutEffect(),
    this.shake = const ShakeEffect(),
    this.sfx = const SfxEffect(),
    this.flash = const FlashEffect(),
    this.haptic = const HapticEffect(),
    this.bgm,
    this.tts,
  });

  factory NodeEffects.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NodeEffects();
    final bgmJson = json['bgm'] as Map<String, dynamic>?;
    final ttsJson = json['tts'] as Map<String, dynamic>?;
    return NodeEffects(
      blackout: BlackoutEffect.fromJson(
        json['blackout'] as Map<String, dynamic>?,
      ),
      shake: ShakeEffect.fromJson(json['shake'] as Map<String, dynamic>?),
      sfx: SfxEffect.fromJson(json['sfx'] as Map<String, dynamic>?),
      flash: FlashEffect.fromJson(json['flash'] as Map<String, dynamic>?),
      haptic: HapticEffect.fromJson(json['haptic'] as Map<String, dynamic>?),
      bgm: bgmJson != null ? BgmEffect.fromJson(bgmJson) : null,
      tts: ttsJson != null ? TtsEffect.fromJson(ttsJson) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'blackout': blackout.toJson(),
    'shake': shake.toJson(),
    'sfx': sfx.toJson(),
    'flash': flash.toJson(),
    'haptic': haptic.toJson(),
    'bgm': bgm?.toJson(),
    'tts': tts?.toJson(),
  };

  NodeEffects copyWith({
    BlackoutEffect? blackout,
    ShakeEffect? shake,
    SfxEffect? sfx,
    FlashEffect? flash,
    HapticEffect? haptic,
    BgmEffect? bgm,
    bool clearBgm = false,
    TtsEffect? tts,
    bool clearTts = false,
  }) {
    return NodeEffects(
      blackout: blackout ?? this.blackout,
      shake: shake ?? this.shake,
      sfx: sfx ?? this.sfx,
      flash: flash ?? this.flash,
      haptic: haptic ?? this.haptic,
      bgm: clearBgm ? null : (bgm ?? this.bgm),
      tts: clearTts ? null : (tts ?? this.tts),
    );
  }
}
