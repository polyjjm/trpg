/// 이야기 팩의 형식. 그리드 카드/상세 화면에 표시되는 배지에 쓰인다.
enum StoryPackFormat { novel, trpg }

extension StoryPackFormatLabel on StoryPackFormat {
  String get label => switch (this) {
        StoryPackFormat.novel => '노벨',
        StoryPackFormat.trpg => 'TRPG',
      };
}

/// 라이브러리(카탈로그)에 진열되는 이야기 팩 한 편.
/// StoryPackRepository(data/story_pack_repository.dart)가 storyPacks
/// Firestore 컬렉션의 liveMetadata(마지막으로 승인된 메타데이터 스냅샷)에서
/// 이 모델을 만든다.
class StoryPack {
  final String id;
  final String title;
  final String description;
  final String authorName;

  /// images/{imageId}에서 이미 resolve된 다운로드 URL. 작가가 표지를 아직
  /// 고르지 않았으면 null — StoryPackCard가 그때 그라디언트+아이콘
  /// placeholder로 대체한다.
  final String? coverImageUrl;

  /// 원 단위 가격. 결제 기능이 아직 없어 실데이터 팩은 전부 0(무료)으로 둔다.
  final int price;
  final StoryPackFormat format;

  /// genres/{genreId}.slug와 같은 어휘(horror, romance, scifi, fantasy,
  /// thriller, slice_of_life)를 쓰는 장르 슬러그 목록. 팩 하나가 여러 장르에
  /// 걸칠 수 있어 리스트다 — 카드/미리보기는 첫 번째 장르를 대표로 보여준다.
  final List<String> genres;

  /// 미구매 상태에서도 무료로 진행할 수 있는 노드 수.
  /// 무료 팩(price == 0)은 이 값을 아예 쓰지 않는다.
  final int previewNodeLimit;

  const StoryPack({
    required this.id,
    required this.title,
    required this.description,
    required this.authorName,
    required this.coverImageUrl,
    required this.price,
    required this.format,
    required this.genres,
    this.previewNodeLimit = 3,
  });

  bool get isFree => price <= 0;

  /// 카드/미리보기의 대표 장르 배지에 쓸 슬러그. 장르를 하나도 안 골랐으면
  /// GenreStyle의 "기타" fallback으로 떨어지도록 빈 문자열을 준다.
  String get primaryGenre => genres.isEmpty ? '' : genres.first;
}
