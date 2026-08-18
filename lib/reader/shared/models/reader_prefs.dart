/// users/{uid}/readerPrefs 문서 — 리더 화면 전반(SceneFrame)의 표시/재생
/// 설정. 게임 세이브(users/{uid}/save/current)와는 별개의, 기기가 아니라
/// 계정에 묶인 리더 환경설정이다.
class ReaderPrefs {
  final String fontId;
  final bool animationEnabled;
  final int typingSpeedMs;
  final bool ttsEnabled;
  final bool bgmEnabled;

  const ReaderPrefs({
    required this.fontId,
    required this.animationEnabled,
    required this.typingSpeedMs,
    required this.ttsEnabled,
    required this.bgmEnabled,
  });

  /// 문서가 아직 없는(최초 진입) 계정에 쓰는 기본값 —
  /// TypewriterText의 기존 기본 속도(40ms/글자)를 그대로 따른다.
  static const defaults = ReaderPrefs(
    fontId: 'default',
    animationEnabled: true,
    typingSpeedMs: 40,
    ttsEnabled: false,
    bgmEnabled: true,
  );

  factory ReaderPrefs.fromFirestore(Map<String, dynamic> json) {
    return ReaderPrefs(
      fontId: json['fontId'] as String? ?? defaults.fontId,
      animationEnabled: json['animationEnabled'] as bool? ?? defaults.animationEnabled,
      typingSpeedMs: (json['typingSpeedMs'] as num?)?.toInt() ?? defaults.typingSpeedMs,
      ttsEnabled: json['ttsEnabled'] as bool? ?? defaults.ttsEnabled,
      bgmEnabled: json['bgmEnabled'] as bool? ?? defaults.bgmEnabled,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fontId': fontId,
        'animationEnabled': animationEnabled,
        'typingSpeedMs': typingSpeedMs,
        'ttsEnabled': ttsEnabled,
        'bgmEnabled': bgmEnabled,
      };

  ReaderPrefs copyWith({
    String? fontId,
    bool? animationEnabled,
    int? typingSpeedMs,
    bool? ttsEnabled,
    bool? bgmEnabled,
  }) {
    return ReaderPrefs(
      fontId: fontId ?? this.fontId,
      animationEnabled: animationEnabled ?? this.animationEnabled,
      typingSpeedMs: typingSpeedMs ?? this.typingSpeedMs,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      bgmEnabled: bgmEnabled ?? this.bgmEnabled,
    );
  }
}
