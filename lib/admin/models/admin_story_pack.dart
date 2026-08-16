import 'story_pack_type.dart';

/// storyPacks/{packId} 문서. 게임 쪽 StoryPack(lib/features/catalog/models/story_pack.dart)과
/// 이름을 맞춰, 나중에 price/coverImage 등을 추가할 여지를 남겨 둔다.
///
/// 기존에 만들어진 스토리팩(예: 좀비 이야기 팩)은 authorId/type/genres가 없는
/// 채로 남아있을 수 있다 — [fromFirestore]는 그 경우 각각 소유자 미지정("")/
/// interactive/빈 배열로 다룬다(FIRESTORE_SCHEMA.md의 storyPacks 참고).
class AdminStoryPack {
  final String id;
  final String title;
  final String authorId;
  final StoryPackType type;
  final List<String> genres;

  const AdminStoryPack({
    required this.id,
    required this.title,
    required this.authorId,
    required this.type,
    required this.genres,
  });

  factory AdminStoryPack.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminStoryPack(
      id: id,
      title: json['title'] as String? ?? '(제목 없음)',
      authorId: json['authorId'] as String? ?? '',
      type: StoryPackTypeJson.fromWire(json['type'] as String?),
      genres: (json['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'authorId': authorId,
        'type': type.wireValue,
        'genres': genres,
      };
}
