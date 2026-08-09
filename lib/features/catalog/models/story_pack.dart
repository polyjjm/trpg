/// 이야기 팩의 형식. 그리드 카드/상세 화면에 표시되는 배지에 쓰인다.
enum StoryPackFormat { novel, trpg }

extension StoryPackFormatLabel on StoryPackFormat {
  String get label => switch (this) {
        StoryPackFormat.novel => '노벨',
        StoryPackFormat.trpg => 'TRPG',
      };
}

/// 라이브러리(카탈로그)에 진열되는 이야기 팩 한 편.
/// 지금은 [data/story_packs.dart]에 하드코딩되어 있지만, 나중에 Firestore 등
/// 원격 콘텐츠 DB로 옮길 것을 고려해 필드를 id 기반으로 구성했다.
class StoryPack {
  final String id;
  final String title;
  final String description;
  final String authorName;
  final String coverImage;

  /// 원 단위 가격. 0이면 무료.
  final int price;
  final StoryPackFormat format;

  /// 미구매 상태에서도 무료로 진행할 수 있는 노드 수.
  /// 무료 팩(price == 0)은 이 값을 아예 쓰지 않는다.
  final int previewNodeLimit;

  const StoryPack({
    required this.id,
    required this.title,
    required this.description,
    required this.authorName,
    required this.coverImage,
    required this.price,
    required this.format,
    this.previewNodeLimit = 3,
  });

  bool get isFree => price <= 0;
}
