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
  final bool bgmEnabled;

  /// 책 읽기 모드(배경 이미지가 없는 노드)에서 한 쪽씩 볼지 두 쪽을 펼칠지 —
  /// 'single' | 'spread'. 배경 이미지가 있는 노드는 시네마틱 레이아웃이라
  /// 이 값을 보지 않는다(설정 화면에도 그렇게 적어 둔다).
  ///
  /// 좁은 폭에서는 두 쪽을 펼칠 자리가 없어 항상 한 쪽으로 그린다 — 값 자체는
  /// 유지되므로 데스크톱으로 돌아오면 다시 두 쪽이 된다.
  final String pageMode;

  final DateTime? lastNoticeReadAt;

  const ReaderPrefs({
    required this.fontId,
    required this.animationEnabled,
    required this.typingSpeedMs,
    required this.ttsEnabled,
    required this.bgmEnabled,
    required this.pageMode,
    this.lastNoticeReadAt,
  });

  /// 문서가 아직 없는(최초 진입) 계정에 쓰는 기본값 —
  /// TypewriterText의 기존 기본 속도(40ms/글자)를 그대로 따른다.
  static const defaults = ReaderPrefs(
    fontId: 'default',
    animationEnabled: true,
    typingSpeedMs: 40,
    ttsEnabled: false,
    bgmEnabled: true,
    pageMode: pageModeSingle,
  );

  static const String pageModeSingle = 'single';
  static const String pageModeSpread = 'spread';

  bool get isSpread => pageMode == pageModeSpread;

  factory ReaderPrefs.fromFirestore(Map<String, dynamic> json) {
    return ReaderPrefs(
      fontId: json['fontId'] as String? ?? defaults.fontId,
      animationEnabled: json['animationEnabled'] as bool? ?? defaults.animationEnabled,
      typingSpeedMs: (json['typingSpeedMs'] as num?)?.toInt() ?? defaults.typingSpeedMs,
      ttsEnabled: json['ttsEnabled'] as bool? ?? defaults.ttsEnabled,
      bgmEnabled: json['bgmEnabled'] as bool? ?? defaults.bgmEnabled,
      // 모르는 값이 들어와도(예: 옛 문서, 오타) 조용히 한 쪽으로 떨어진다 —
      // 화면이 깨지는 것보다 낫다.
      pageMode: json['pageMode'] == pageModeSpread ? pageModeSpread : defaults.pageMode,
      lastNoticeReadAt: (json['lastNoticeReadAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fontId': fontId,
        'animationEnabled': animationEnabled,
        'typingSpeedMs': typingSpeedMs,
        'ttsEnabled': ttsEnabled,
        'bgmEnabled': bgmEnabled,
        'pageMode': pageMode,
      };

  ReaderPrefs copyWith({
    String? fontId,
    bool? animationEnabled,
    int? typingSpeedMs,
    bool? ttsEnabled,
    bool? bgmEnabled,
    String? pageMode,
  }) {
    return ReaderPrefs(
      fontId: fontId ?? this.fontId,
      animationEnabled: animationEnabled ?? this.animationEnabled,
      typingSpeedMs: typingSpeedMs ?? this.typingSpeedMs,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      bgmEnabled: bgmEnabled ?? this.bgmEnabled,
      pageMode: pageMode ?? this.pageMode,
      lastNoticeReadAt: lastNoticeReadAt,
    );
  }
}
