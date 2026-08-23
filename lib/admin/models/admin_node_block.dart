import 'node_effects.dart';

/// 노드 본문 블록 하나 — 이번 마이그레이션은 paragraph만 지원한다. beat/image
/// 블록, 드래그 재정렬은 다음 패스에서 붙일 예정이라 지금은 text 필드만
/// mutable로 들고 있는다. TTS override(ttsVoiceId 등 5개)는 붙었다 —
/// 인터랙티브 팩의 다중 화자 대사 지원(요청 사양)을 위해서다.
///
/// 리더 쪽 NodeBlock(lib/reader/shared/models/node_block.dart)과 Firestore
/// 문서 모양은 같지만, 이건 텍스트 필드를 실시간으로 mutate하는 편집 세션
/// 전용 클래스라 별도로 둔다 — NodeBlock은 필드가 전부 final이라 한 글자
/// 입력할 때마다 리스트 안의 인스턴스를 통째로 교체해야 하는데, 그러면 이
/// 블록에 매긴 ObjectKey(story_node_editor의 관례, node_editor.dart의
/// ObjectKey(choice) 참고)도 매번 바뀌어서 TextFormField가 포커스/커서 위치를
/// 잃는다.
class AdminNodeBlock {
  String text;

  /// 노드 기본 TTS(effects.tts)를 재정의하는 블록 단위 보이스/감정/강도/
  /// 피치/템포 — 전부 선택이고, 다섯 다 null이면(공통 케이스, 저자가 아무
  /// 것도 안 건드리면 이 상태다) 노드 기본값을 그대로 물려받는다(요청 사양:
  /// "A block with all these fields null/absent simply inherits the
  /// node-level resolved settings"). Cloud Function의 resolveBlockTts
  /// (functions/src/index.ts)가 정확히 이 필드 이름 그대로 Firestore
  /// JSON에서 읽는다 — 필드명을 바꾸면 그쪽도 같이 바꿔야 한다. 노드 레벨
  /// TtsEffect와 달리 필드 하나하나가 독립적으로 폴백한다 — "블록이 voiceId만
  /// 재정의하면 감정/피치/템포는 그대로 노드 값을 쓴다"는 뜻.
  String? ttsVoiceId;
  TtsEmotionPreset? ttsEmotion;
  double? ttsEmotionIntensity;
  double? ttsPitch;
  double? ttsTempo;

  AdminNodeBlock({
    this.text = '',
    this.ttsVoiceId,
    this.ttsEmotion,
    this.ttsEmotionIntensity,
    this.ttsPitch,
    this.ttsTempo,
  });

  factory AdminNodeBlock.fromJson(Map<String, dynamic> json) {
    return AdminNodeBlock(
      text: json['text'] as String? ?? '',
      ttsVoiceId: json['ttsVoiceId'] as String?,
      ttsEmotion: TtsEmotionPresetJson.fromWire(json['ttsEmotion'] as String?),
      ttsEmotionIntensity: (json['ttsEmotionIntensity'] as num?)?.toDouble(),
      ttsPitch: (json['ttsPitch'] as num?)?.toDouble(),
      ttsTempo: (json['ttsTempo'] as num?)?.toDouble(),
    );
  }

  /// type은 이번 패스에서 늘 'paragraph'로 고정한다 — beat/image가 생기면
  /// 그때 이 클래스에 type 필드를 추가한다.
  Map<String, dynamic> toJson() => {
    'type': 'paragraph',
    'text': text,
    'ttsVoiceId': ttsVoiceId,
    'ttsEmotion': ttsEmotion?.wireValue,
    'ttsEmotionIntensity': ttsEmotionIntensity,
    'ttsPitch': ttsPitch,
    'ttsTempo': ttsTempo,
  };

  /// 이 블록이 노드 기본값을 하나라도 재정의했는지 — 블록 에디터의 "보이스
  /// 설정" 섹션이 접힌 채로 시작할지(재정의 없음, 공통 케이스) 펼친 채로
  /// 시작할지 고를 때 쓴다.
  bool get hasTtsOverride =>
      ttsVoiceId != null ||
      ttsEmotion != null ||
      ttsEmotionIntensity != null ||
      ttsPitch != null ||
      ttsTempo != null;
}
