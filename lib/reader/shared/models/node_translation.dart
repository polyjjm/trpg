import 'package:cloud_firestore/cloud_firestore.dart';

import 'node_block.dart';

/// storyPacks/{storyId}/nodes/{nodeId}/translations/{langCode} 문서 —
/// 부모 노드 blocks와 같은 모양의 번역본. [sourceHash]는 번역 시점의 원문
/// blocks 해시로, 원문이 이후 바뀌면 [sourceHash]가 최신 원문 해시와
/// 달라져 "번역이 원문보다 오래됐다"를 판별하는 데 쓴다.
class NodeTranslation {
  final List<NodeBlock> blocks;
  final String sourceHash;
  final DateTime? translatedAt;

  const NodeTranslation({
    required this.blocks,
    required this.sourceHash,
    this.translatedAt,
  });

  factory NodeTranslation.fromFirestore(Map<String, dynamic> json) {
    return NodeTranslation(
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((e) => NodeBlock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      sourceHash: json['sourceHash'] as String? ?? '',
      translatedAt: (json['translatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'sourceHash': sourceHash,
        'translatedAt': translatedAt != null ? Timestamp.fromDate(translatedAt!) : FieldValue.serverTimestamp(),
      };
}
