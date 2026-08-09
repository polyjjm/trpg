/// storyPacks/{packId} 문서. 지금은 title만 다루지만, 나중에 게임 쪽
/// StoryPack(lib/features/catalog/models/story_pack.dart)과 맞춰 price/coverImage
/// 등을 추가할 여지를 남겨 둔다.
class AdminStoryPack {
  final String id;
  final String title;

  const AdminStoryPack({required this.id, required this.title});

  factory AdminStoryPack.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminStoryPack(
      id: id,
      title: json['title'] as String? ?? '(제목 없음)',
    );
  }

  Map<String, dynamic> toJson() => {'title': title};
}
