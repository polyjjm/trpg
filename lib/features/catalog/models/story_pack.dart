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

  /// 코인 단위 정가 — storyPacks 문서의 liveMetadata(admin이 승인한 마지막
  /// 스냅샷)에서 그대로 읽는다. 실제로 지금 이 팩에 적용할 가격은 이 필드가
  /// 아니라 [effectivePrice]다(할인 중이면 salePrice가 적용된다).
  final int price;

  /// 할인가 — null이면 할인 없음.
  final int? salePrice;

  /// 할인 적용 기간 — 둘 다 null이면 salePrice가 있는 한 항상 할인 적용.
  final DateTime? discountStartAt;
  final DateTime? discountEndAt;

  final StoryPackFormat format;

  /// genres/{genreId}.slug와 같은 어휘(horror, romance, scifi, fantasy,
  /// thriller, slice_of_life)를 쓰는 장르 슬러그 목록. 팩 하나가 여러 장르에
  /// 걸칠 수 있어 리스트다 — 카드/미리보기는 첫 번째 장르를 대표로 보여준다.
  final List<String> genres;

  /// 미구매 상태에서도 무료로 진행할 수 있는 노드 수.
  /// 무료 팩(price == 0)은 이 값을 아예 쓰지 않는다.
  final int previewNodeLimit;

  /// images/{imageId} 참조 — 어떤 노드도 배경 이미지를 명시적으로 고르지
  /// 않았을 때 인계 체인의 최종 폴백(lib/core/story/
  /// background_image_inheritance.dart). admin 쪽 defaultBackgroundImage와
  /// 달리 liveMetadata 승인 게이트를 거치지 않는 값이라, StoryPackRepository는
  /// 이 필드를 top-level storyPacks 문서에서 곧장 읽는다.
  final String? defaultBackgroundImage;

  /// bgmLibrary/{bgmId} 참조 — 리딩 세션이 시작될 때(첫 노드가 effects.bgm을
  /// 아예 안 정했을 때만) 재생할 시작 BGM. defaultBackgroundImage와 달리
  /// **liveMetadata 승인 게이트를 그대로 거친다**(admin/data/
  /// admin_story_repository.dart의 _metadataSnapshot) — "지금부터 뭐가
  /// 재생될지"는 검토가 필요한 콘텐츠라는 판단. 그래서 StoryPackRepository는
  /// 이 필드를 top-level이 아니라 liveMetadata에서 읽는다.
  final String? defaultBgmId;

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
    this.salePrice,
    this.discountStartAt,
    this.discountEndAt,
    required this.format,
    required this.genres,
    this.previewNodeLimit = 3,
    this.defaultBackgroundImage,
    this.defaultBgmId,
    this.avgRating,
    this.reviewCount = 0,
    this.publishedNodeCount = 0,
  });

  /// [at] 시점에 할인가가 적용 중인지 — lib/admin/models/admin_story_pack.dart의
  /// AdminStoryPack.isDiscountActiveAt/lib/features/wallet/models/point_package.dart의
  /// PointPackage.isDiscountActiveAt과 같은 모양(전부 "코인 + 선택적 할인
  /// 기간" 가격 모델을 공유한다).
  bool isDiscountActiveAt(DateTime at) {
    if (salePrice == null) return false;
    final start = discountStartAt;
    if (start != null && at.isBefore(start)) return false;
    final end = discountEndAt;
    if (end != null && at.isAfter(end)) return false;
    return true;
  }

  bool get hasActiveDiscount => isDiscountActiveAt(DateTime.now());

  /// 지금 실제로 적용되는 가격 — 할인 중이면 salePrice, 아니면 price.
  /// 구매/미리보기 등 "얼마를 내야 하는지"를 판단하는 모든 곳은 반드시 이
  /// 값을 써야 한다(원래 price를 직접 쓰면 할인이 무시된다).
  int get effectivePrice => hasActiveDiscount ? salePrice! : price;

  bool get isFree => effectivePrice <= 0;

  /// 카드/미리보기의 대표 장르 배지에 쓸 슬러그. 장르를 하나도 안 골랐으면
  /// GenreStyle의 "기타" fallback으로 떨어지도록 빈 문자열을 준다.
  String get primaryGenre => genres.isEmpty ? '' : genres.first;
}
