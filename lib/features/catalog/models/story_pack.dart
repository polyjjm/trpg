/// 이야기 팩의 형식 — admin 쪽 StoryPackType(interactive/linear)을 그대로
/// 반영한다(StoryPackRepository가 storyPacks.type에서 그대로 옮겨 담는다).
/// 그리드 카드/상세 화면 배지에 쓰인다.
enum StoryPackFormat { interactive, linear }

extension StoryPackFormatLabel on StoryPackFormat {
  String get label => switch (this) {
    StoryPackFormat.interactive => '인터랙티브',
    StoryPackFormat.linear => '선형',
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

  /// 이 팩의 노드에 TTS 재생을 허용할지 — SceneFrame 하단 시트의 TTS
  /// 토글은 이 값이 true일 때만 보인다(readerPrefs.ttsEnabled와는 별개로,
  /// 팩 단위로 아예 끌 수 있는 스위치).
  final bool ttsEnabled;

  /// 노드에 bgmOverride가 없을 때 재생할 기본 배경음 트랙 id. null이면
  /// 이 팩에 기본 BGM이 없다는 뜻.
  final String? ambientBgm;

  /// images/{imageId} 참조 — 어떤 노드도 배경 이미지를 명시적으로 고르지
  /// 않았을 때 인계 체인의 최종 폴백(lib/core/story/
  /// background_image_inheritance.dart). admin 쪽 defaultBackgroundImage와
  /// 달리 liveMetadata 승인 게이트를 거치지 않는 값이라, StoryPackRepository는
  /// 이 필드를 top-level storyPacks 문서에서 곧장 읽는다.
  final String? defaultBackgroundImage;

  /// 리뷰 평균 평점(1~5)과 개수 — storyPacks 문서에 비정규화된 값을 그대로
  /// 읽는다(reviews 서브컬렉션을 매번 훑어 계산하지 않는다). 이 값을 최신
  /// 상태로 유지하는 건 리뷰 쓰기를 트리거로 하는 Cloud Function
  /// (functions/src/index.ts)의 몫이다 — 클라이언트는 절대 이 두 필드에
  /// 직접 쓰지 않는다. 리뷰가 하나도 없으면 avgRating은 null.
  final double? avgRating;
  final int reviewCount;

  /// 발행된(status == 'published') 노드 총 개수. StoryPackRepository가 이미
  /// "발행된 노드가 있는 팩"을 가리려고 훑는 collectionGroup('nodes') 조회
  /// 결과를 그대로 세어 채운다(추가 조회 없음) — 내 서재 탭의 진행률 바가
  /// visitedNodeCount / publishedNodeCount로 실제 분량 대비 진행도를
  /// 보여주는 데 쓴다. 0이면(이론상 있을 수 없지만) 진행률 바 대신 배지만
  /// 보여주도록 호출부가 방어한다.
  final int publishedNodeCount;

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
    this.ttsEnabled = false,
    this.ambientBgm,
    this.defaultBackgroundImage,
    this.avgRating,
    this.reviewCount = 0,
    this.publishedNodeCount = 0,
  });

  bool get isFree => price <= 0;

  /// 카드/미리보기의 대표 장르 배지에 쓸 슬러그. 장르를 하나도 안 골랐으면
  /// GenreStyle의 "기타" fallback으로 떨어지도록 빈 문자열을 준다.
  String get primaryGenre => genres.isEmpty ? '' : genres.first;
}
