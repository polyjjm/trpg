import 'package:cloud_firestore/cloud_firestore.dart';

/// users/{uid}/readerPrefs 문서 — 리더 화면 전반(SceneFrame)의 표시/재생
/// 설정. 게임 세이브(users/{uid}/save/current)와는 별개의, 기기가 아니라
/// 계정에 묶인 리더 환경설정이다.
///
/// [lastNoticeReadAt]은 나머지 필드와 성격이 다르다 — SceneFrame 설정이
/// 아니라 CatalogShellPage(공지사항 탭을 열 때)가 쓴다. 그래서
/// [toFirestore]에는 일부러 포함하지 않는다 — ReaderPrefsRepository.save()가
/// 이 문서를 merge:true로 쓰긴 하지만, 나중에 누군가 merge:false로 바꾸면
/// 이 필드가 조용히 지워질 수 있다. 실제 쓰기는 markNoticesRead()가 별도
/// merge 쓰기로 한다.
class ReaderPrefs {
  final String fontId;
  final bool animationEnabled;
  final int typingSpeedMs;
  final bool ttsEnabled;

  /// 내레이션이 끝까지 재생되면(일시정지가 아니라) 자동으로 다음 노드로
  /// 넘어갈지 — 기본 켜짐(요청 사양: "auto-continue should be the default
  /// behavior but not forced"). ReaderSessionController가 이 값을
  /// 받아(setAutoContinueEnabled) 실제 자동 이어재생 여부를 판단한다.
  final bool ttsAutoContinueEnabled;

  /// BGM 마스터 볼륨(리더 본인의 취향) — 0.0(무음)~1.0(원본 그대로), 기본
  /// 1.0. 노드 작성자가 정한 effects.bgm.volume(0.0~1.0)과는 별개의, 곱해지는
  /// 값이다 — 최종 재생 볼륨 = authoredVolume × bgmMasterVolume
  /// (`AudioService`의 `_effectiveVolume` 참고). 슬라이더를 드래그하는 동안은
  /// [ReaderPrefsRepository]에 매 프레임 저장하지 않는다(SceneFrame이 로컬로만
  /// 반영하다가 손을 뗄 때 한 번 저장한다) — 오디오 자체는 드래그 중에도
  /// AudioService.setBgmMasterVolume으로 즉시 반영된다.
  final double bgmMasterVolume;

  /// 책 읽기 모드(배경 이미지가 없는 노드)에서 한 쪽씩 볼지 두 쪽을 펼칠지 —
  /// 'single' | 'spread'. 배경 이미지가 있는 노드는 시네마틱 레이아웃이라
  /// 이 값을 보지 않는다(설정 화면에도 그렇게 적어 둔다).
  ///
  /// 좁은 폭에서는 두 쪽을 펼칠 자리가 없어 항상 한 쪽으로 그린다 — 값 자체는
  /// 유지되므로 데스크톱으로 돌아오면 다시 두 쪽이 된다.
  final String pageMode;

  /// 본문 글자 색 — 'ivory'(기본) / 'white' / 'sepia' / 'gray'.
  final String textColorId;

  /// 본문 글자 크기 배율 — 0.9(작게) / 1.0(보통) / 1.15(크게).
  /// 리더 설정에서 고르고, SceneFrame이 문단·비트 크기에 곱한다.
  final double fontScale;

  final DateTime? lastNoticeReadAt;

  const ReaderPrefs({
    required this.fontId,
    required this.animationEnabled,
    required this.typingSpeedMs,
    required this.ttsEnabled,
    required this.ttsAutoContinueEnabled,
    required this.bgmMasterVolume,
    required this.pageMode,
    required this.fontScale,
    required this.textColorId,
    this.lastNoticeReadAt,
  });

  /// 문서가 아직 없는(최초 진입) 계정에 쓰는 기본값 —
  /// TypewriterText의 기존 기본 속도(40ms/글자)를 그대로 따른다.
  static const defaults = ReaderPrefs(
    fontId: 'default',
    animationEnabled: true,
    typingSpeedMs: 40,
    ttsEnabled: false,
    ttsAutoContinueEnabled: true,
    bgmMasterVolume: 1.0,
    pageMode: pageModeSingle,
    fontScale: 1.0,
    textColorId: 'ivory',
  );

  /// 설정에 노출하는 글자 색 선택지 — 지면(어두운 배경) 위에서 읽히는 값만.
  static const List<({String id, String label, int argb})> textColorOptions = [
    (id: 'ivory', label: '기본', argb: 0xFFE2D4BF),
    (id: 'white', label: '흰색', argb: 0xFFF5F5F5),
    (id: 'sepia', label: '세피아', argb: 0xFFD9B98C),
    (id: 'gray', label: '회색', argb: 0xFFA8A8A2),
  ];

  /// 설정에 노출하는 글자 크기 선택지.
  static const List<({double value, String label})> fontScaleOptions = [
    (value: 0.9, label: '작게'),
    (value: 1.0, label: '보통'),
    (value: 1.15, label: '크게'),
  ];

  static const String pageModeSingle = 'single';
  static const String pageModeSpread = 'spread';

  bool get isSpread => pageMode == pageModeSpread;

  factory ReaderPrefs.fromFirestore(Map<String, dynamic> json) {
    return ReaderPrefs(
      fontId: json['fontId'] as String? ?? defaults.fontId,
      animationEnabled:
          json['animationEnabled'] as bool? ?? defaults.animationEnabled,
      typingSpeedMs:
          (json['typingSpeedMs'] as num?)?.toInt() ?? defaults.typingSpeedMs,
      ttsEnabled: json['ttsEnabled'] as bool? ?? defaults.ttsEnabled,
      ttsAutoContinueEnabled:
          json['ttsAutoContinueEnabled'] as bool? ??
          defaults.ttsAutoContinueEnabled,
      bgmMasterVolume: _readBgmMasterVolume(json),
      // 모르는 값이 들어와도(예: 옛 문서, 오타) 조용히 한 쪽으로 떨어진다 —
      // 화면이 깨지는 것보다 낫다.
      pageMode: json['pageMode'] == pageModeSpread
          ? pageModeSpread
          : defaults.pageMode,
      // 범위를 벗어난 값이 들어와도 화면이 깨지지 않게 잠근다.
      fontScale: ((json['fontScale'] as num?)?.toDouble() ?? defaults.fontScale)
          .clamp(0.8, 1.4),
      textColorId: textColorOptions.any((o) => o.id == json['textColorId'])
          ? json['textColorId'] as String
          : defaults.textColorId,
      lastNoticeReadAt: (json['lastNoticeReadAt'] as Timestamp?)?.toDate(),
    );
  }

  /// [bgmMasterVolume]은 예전 `bgmEnabled`(bool) 필드를 대체한다 — 문서에
  /// 이미 새 필드가 있으면 그대로 쓰고, 없는데(마이그레이션 전 계정) 옛
  /// `bgmEnabled`만 있으면 그 값을 1.0/0.0으로 한 번 옮겨 읽는다. 옛 필드도
  /// 새 필드도 둘 다 없으면(최초 진입) 기본값 1.0.
  static double _readBgmMasterVolume(Map<String, dynamic> json) {
    final volume = json['bgmMasterVolume'] as num?;
    if (volume != null) return volume.toDouble().clamp(0.0, 1.0);
    final legacyEnabled = json['bgmEnabled'] as bool?;
    if (legacyEnabled != null) return legacyEnabled ? 1.0 : 0.0;
    return defaults.bgmMasterVolume;
  }

  Map<String, dynamic> toFirestore() => {
    'fontId': fontId,
    'animationEnabled': animationEnabled,
    'typingSpeedMs': typingSpeedMs,
    'ttsEnabled': ttsEnabled,
    'ttsAutoContinueEnabled': ttsAutoContinueEnabled,
    'bgmMasterVolume': bgmMasterVolume,
    'pageMode': pageMode,
    'fontScale': fontScale,
    'textColorId': textColorId,
  };

  ReaderPrefs copyWith({
    String? fontId,
    bool? animationEnabled,
    int? typingSpeedMs,
    bool? ttsEnabled,
    bool? ttsAutoContinueEnabled,
    double? bgmMasterVolume,
    String? pageMode,
    double? fontScale,
    String? textColorId,
  }) {
    return ReaderPrefs(
      fontId: fontId ?? this.fontId,
      animationEnabled: animationEnabled ?? this.animationEnabled,
      typingSpeedMs: typingSpeedMs ?? this.typingSpeedMs,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      ttsAutoContinueEnabled:
          ttsAutoContinueEnabled ?? this.ttsAutoContinueEnabled,
      bgmMasterVolume: bgmMasterVolume ?? this.bgmMasterVolume,
      pageMode: pageMode ?? this.pageMode,
      fontScale: fontScale ?? this.fontScale,
      textColorId: textColorId ?? this.textColorId,
      lastNoticeReadAt: lastNoticeReadAt,
    );
  }
}
