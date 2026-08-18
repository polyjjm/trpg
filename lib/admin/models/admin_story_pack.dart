import 'package:cloud_firestore/cloud_firestore.dart';

import 'pack_serialization_status.dart';
import 'story_pack_type.dart';

/// storyPacks/{packId} 문서. 게임 쪽 StoryPack(lib/features/catalog/models/story_pack.dart)과
/// 이름을 맞춰, 나중에 price 등을 추가할 여지를 남겨 둔다.
///
/// title/genres/description/coverImageId는 "지금 편집 중인" 값이다 — 노드의
/// draft 콘텐츠와 같은 성격이다. 이미 연재 시작 승인을 받은 팩이라면 독자에게는
/// 이 값이 아니라 [liveMetadata](마지막으로 승인된 메타데이터 스냅샷)가 보인다.
///
/// 두 개의 독립된 승인 레이어가 이 한 문서 위에 같이 있다:
/// - **연재 시작 승인**([serializationStatus]): 팩이 독자 라이브러리에 존재
///   자체를 드러내도 되는지 — 한 번만 통과하면 되는 게이트.
/// - **메타데이터 수정 승인**([pendingMetadataAction]/[liveMetadata]): 이미
///   연재 중인 팩의 제목/장르/설명/표지를 바꿀 때마다 반복되는 게이트. 개별
///   노드 콘텐츠 승인(status/pendingAction/liveSnapshot)과는 완전히 별개다.
///
/// 기존에 만들어진 스토리팩(예: 좀비 이야기 팩)은 authorId/type/genres가 없는
/// 채로 남아있을 수 있다 — [fromFirestore]는 그 경우 각각 소유자 미지정("")/
/// interactive/빈 배열로 다룬다(FIRESTORE_SCHEMA.md의 storyPacks 참고).
class AdminStoryPack {
  final String id;
  final String title;
  final String authorId;

  /// 생성 시점의 작가 표시 이름 스냅샷. 리더 앱이 매 조회마다 users 컬렉션을
  /// 조인하지 않아도 되도록(그리고 리더가 다른 사람의 users 문서를 읽을 권한이
  /// 없으므로) 팩 문서에 그대로 박아 둔다 — 작가가 나중에 프로필 이름을 바꿔도
  /// 여기는 갱신되지 않는다(AuthorApplication.displayName과 같은 트레이드오프).
  final String authorName;

  final StoryPackType type;
  final List<String> genres;
  final String description;
  final String? coverImageId;

  /// 노드가 배경 이미지를 명시적으로 고르지 않았을 때 팩 전체의 최종
  /// 폴백으로 쓰이는 images/{imageId} 참조(lib/core/story/
  /// background_image_inheritance.dart). liveMetadata 승인 흐름과는
  /// 무관한, 언제든 바로 저장되는 설정값이다 — 순수 렌더링 기본값일 뿐
  /// 검토가 필요한 "콘텐츠"로 보지 않는다.
  final String? defaultBackgroundImage;

  final PackSerializationStatus serializationStatus;
  final DateTime? serializationSubmittedAt;
  final String? serializationReviewedBy;
  final DateTime? serializationReviewedAt;
  final String? serializationRejectionReason;

  /// 'edit' | null. null이면 대기 중인 메타데이터 변경 요청이 없다는 뜻.
  final String? pendingMetadataAction;

  /// 마지막으로 승인된 메타데이터 스냅샷(title/genres/description/coverImageId).
  /// 연재 시작 승인을 아직 못 받았으면 null.
  final Map<String, dynamic>? liveMetadata;
  final DateTime? metadataSubmittedAt;
  final String? metadataReviewedBy;
  final DateTime? metadataReviewedAt;
  final String? metadataRejectionReason;

  const AdminStoryPack({
    required this.id,
    required this.title,
    required this.authorId,
    required this.authorName,
    required this.type,
    required this.genres,
    required this.description,
    required this.coverImageId,
    this.defaultBackgroundImage,
    required this.serializationStatus,
    this.serializationSubmittedAt,
    this.serializationReviewedBy,
    this.serializationReviewedAt,
    this.serializationRejectionReason,
    this.pendingMetadataAction,
    this.liveMetadata,
    this.metadataSubmittedAt,
    this.metadataReviewedBy,
    this.metadataReviewedAt,
    this.metadataRejectionReason,
  });

  factory AdminStoryPack.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminStoryPack(
      id: id,
      title: json['title'] as String? ?? '(제목 없음)',
      authorId: json['authorId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '',
      type: StoryPackTypeJson.fromWire(json['type'] as String?),
      genres: (json['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
      description: json['description'] as String? ?? '',
      coverImageId: json['coverImageId'] as String?,
      defaultBackgroundImage: json['defaultBackgroundImage'] as String?,
      serializationStatus: PackSerializationStatusJson.fromWire(json['serializationStatus'] as String?),
      serializationSubmittedAt: (json['serializationSubmittedAt'] as Timestamp?)?.toDate(),
      serializationReviewedBy: json['serializationReviewedBy'] as String?,
      serializationReviewedAt: (json['serializationReviewedAt'] as Timestamp?)?.toDate(),
      serializationRejectionReason: json['serializationRejectionReason'] as String?,
      pendingMetadataAction: json['pendingMetadataAction'] as String?,
      liveMetadata: json['liveMetadata'] as Map<String, dynamic>?,
      metadataSubmittedAt: (json['metadataSubmittedAt'] as Timestamp?)?.toDate(),
      metadataReviewedBy: json['metadataReviewedBy'] as String?,
      metadataReviewedAt: (json['metadataReviewedAt'] as Timestamp?)?.toDate(),
      metadataRejectionReason: json['metadataRejectionReason'] as String?,
    );
  }

  /// 생성(create) 전용 — 이후의 부분 업데이트는 AdminStoryRepository가 각자
  /// 필요한 필드만 담아 직접 쓴다(saveDraftPackSettings/requestSerialization 등).
  Map<String, dynamic> toJson() => {
        'title': title,
        'authorId': authorId,
        'authorName': authorName,
        'type': type.wireValue,
        'genres': genres,
        'description': description,
        'coverImageId': coverImageId,
        'defaultBackgroundImage': defaultBackgroundImage,
        'serializationStatus': serializationStatus.wireValue,
      };

  /// 연재 시작 승인을 (다시) 요청할 수 있는 상태인지.
  bool get canRequestSerialization =>
      serializationStatus == PackSerializationStatus.draft || serializationStatus == PackSerializationStatus.rejected;

  /// 메타데이터 변경 승인을 요청할 수 있는 상태인지 — 이미 연재 승인을 받았고,
  /// 지금 대기 중인 변경 요청이 없어야 한다.
  bool get canRequestMetadataEdit =>
      serializationStatus == PackSerializationStatus.approved && pendingMetadataAction == null;
}
