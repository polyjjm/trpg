/// 노드 본문 블록 하나 — 이번 마이그레이션은 paragraph만 지원한다. beat/image
/// 블록, 드래그 재정렬, TTS override는 다음 패스에서 붙일 예정이라 지금은
/// text 한 필드만 mutable로 들고 있는다.
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

  AdminNodeBlock({this.text = ''});

  factory AdminNodeBlock.fromJson(Map<String, dynamic> json) {
    return AdminNodeBlock(text: json['text'] as String? ?? '');
  }

  /// type은 이번 패스에서 늘 'paragraph'로 고정한다 — beat/image가 생기면
  /// 그때 이 클래스에 type 필드를 추가한다.
  Map<String, dynamic> toJson() => {
        'type': 'paragraph',
        'text': text,
      };
}
