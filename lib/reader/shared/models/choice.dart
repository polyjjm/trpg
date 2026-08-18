/// StoryNode.choices 배열의 원소(embedded map) 하나 — 인터랙티브 스토리팩의
/// 노드에서만 쓰인다(storyPack.type == 'interactive'). admin 쪽 편집 세션
/// 전용 모델인 AdminNodeChoice(lib/admin/models/admin_node_choice.dart)와
/// Firestore 문서 모양은 같다.
class Choice {
  final String label;
  final String nextNodeId;

  const Choice({
    required this.label,
    required this.nextNodeId,
  });

  factory Choice.fromJson(Map<String, dynamic> json) {
    return Choice(
      label: json['label'] as String? ?? '',
      nextNodeId: json['nextNodeId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'nextNodeId': nextNodeId,
      };
}
