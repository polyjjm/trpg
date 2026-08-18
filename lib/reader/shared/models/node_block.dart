import 'node_block_type.dart';

/// StoryNode.blocks 배열의 원소(embedded map) 하나. paragraph/beat는
/// text(+선택적 ttsOverride)를, image는 url(+선택적 caption)을 쓴다 — 타입별로
/// 실제 쓰는 필드만 다르지만, 한 클래스가 모든 필드를 같이 들고 있는
/// 평평한(flat) 구조로 둔다.
class NodeBlock {
  final NodeBlockType type;

  /// type == paragraph/beat일 때의 본문.
  final String? text;

  /// TTS 재생 시 [text] 대신 읽을 텍스트. null이면 [text]를 그대로 읽는다.
  final String? ttsOverride;

  /// type == image일 때의 이미지 URL.
  final String? url;

  /// type == image일 때의 선택적 캡션.
  final String? caption;

  const NodeBlock({
    required this.type,
    this.text,
    this.ttsOverride,
    this.url,
    this.caption,
  });

  factory NodeBlock.fromJson(Map<String, dynamic> json) {
    return NodeBlock(
      type: NodeBlockTypeJson.fromWire(json['type'] as String?),
      text: json['text'] as String?,
      ttsOverride: json['ttsOverride'] as String?,
      url: json['url'] as String?,
      caption: json['caption'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.wireValue,
        'text': text,
        'ttsOverride': ttsOverride,
        'url': url,
        'caption': caption,
      };

  /// TTS가 실제로 읽을 텍스트 — [ttsOverride]가 있으면 그걸, 없으면 [text].
  String? get ttsText => ttsOverride ?? text;
}
