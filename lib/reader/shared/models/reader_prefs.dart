import 'package:cloud_firestore/cloud_firestore.dart';

/// users/{uid}/readerPrefs 문서 — 리더 화면 전반(SceneFrame)의 표시/재생
/// 설정. 게임 세이브(users/{uid}/save/current)와는 별개의, 기기가 아니라
/// 계정에 묶인 리더 환경설정이다.
///
/// [lastNoticeReadAt]은 나머지 필드와 성격이 다르다 — SceneFrame 설정
/// 시트가 아니라 CatalogShellPage(공지사항 탭을 열 때)가 쓴다. 그래서
/// [toFirestore]에는 일부러 포함하지 않는다 — ReaderPrefsRepository.save()가
/// (fontId 등을 바꿀 때마다) 이 문서를 merge:true로 쓰긴 하지만, 혹시라도
/// 나중에 누군가 merge:false로 바꾸면 이 필드가 조용히 지워질 수 있다.
/// 아예 그 경로에서 손대지 않게 분리해 두는 쪽이 더 안전하다 — 실제 쓰기는
/// ReaderPrefsRepository.markNoticesRead()가 별도 merge 쓰기로 한다.
class ReaderPrefs {
  final String fontId;
  final bool animationEnabled;
  final int typingSpeedMs;
  final bool ttsEnabled;
  final bool bgmEnabled;
  final DateTime? lastNoticeReadAt;

  const ReaderPrefs({
    required this.fontId,
    required this.animationEnabled,
    required this.typingSpeedMs,
    required this.ttsEnabled,
    required this.bgmEnabled,
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
  );

  factory ReaderPrefs.fromFirestore(Map<String, dynamic> json) {
    return ReaderPrefs(
      fontId: json['fontId'] as String? ?? defaults.fontId,
      animationEnabled: json['animationEnabled'] as bool? ?? defaults.animationEnabled,
      typingSpeedMs: (json['typingSpeedMs'] as num?)?.toInt() ?? defaults.typingSpeedMs,
      ttsEnabled: json['ttsEnabled'] as bool? ?? defaults.ttsEnabled,
      bgmEnabled: json['bgmEnabled'] as bool? ?? defaults.bgmEnabled,
      lastNoticeReadAt: (json['lastNoticeReadAt'] as Timestamp?)?.toDate(),
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
      lastNoticeReadAt: lastNoticeReadAt,
    );
  }
}
