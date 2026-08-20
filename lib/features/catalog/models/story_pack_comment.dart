import 'package:cloud_firestore/cloud_firestore.dart';

/// storyPacks/{packId}/comments/{commentId} 문서 — 리뷰(reviews/{uid})와
/// 달리 한 유저가 여러 개 남길 수 있어 문서 id가 자동 생성이다. 그래서
/// 작성자를 알아보려면 [uid] 필드가 문서 안에 따로 있어야 한다.
///
/// 답글은 딱 한 단계만 허용한다 — [parentCommentId]가 null이면 최상위 댓글,
/// 특정 댓글 id를 가리키면 그 댓글의 답글이다. 답글의 답글(2단계 중첩)은
/// UI에도 없고, firestore.rules의 isValidParentComment()가 parentCommentId가
/// 가리키는 문서 자신도 parentCommentId == null이어야 한다고 검증해서 서버
/// 쪽에서도 막는다.
class StoryPackComment {
  final String id;
  final String uid;
  final String text;
  final DateTime? createdAt;
  final String authorDisplayName;
  final String? authorPhotoUrl;

  /// 소프트 삭제 플래그 — 본인 댓글만 이 값을 true로 바꿀 수 있다(보안 규칙에서
  /// 강제, 그 외 필드는 그 시점에 전부 그대로 고정). 실제 문서를 지우지 않고
  /// 이 플래그만 세우는 이유는 나중에 생길 신고/관리자 모더레이션이 지워진
  /// 댓글도 근거로 볼 수 있어야 해서다 — 그 모더레이션 UI 자체는 이번 범위
  /// 밖이다.
  final bool isDeleted;

  /// null이면 최상위 댓글, 아니면 부모 댓글의 id.
  final String? parentCommentId;

  /// storyPacks/.../comments/{commentId}/likes 서브컬렉션 문서 수를 그대로
  /// 복사해 둔 값 — Cloud Function(functions/src/index.ts의
  /// onCommentLikeWritten)이 좋아요 쓰기마다 갱신한다. 클라이언트는 이 필드에
  /// 직접 쓰지 않는다(리뷰의 avgRating/reviewCount와 같은 패턴).
  final int likeCount;

  const StoryPackComment({
    required this.id,
    required this.uid,
    required this.text,
    required this.createdAt,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
    required this.isDeleted,
    required this.parentCommentId,
    required this.likeCount,
  });

  factory StoryPackComment.fromFirestore(String id, Map<String, dynamic> json) {
    return StoryPackComment(
      id: id,
      uid: json['uid'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      authorDisplayName: json['authorDisplayName'] as String? ?? '익명',
      authorPhotoUrl: json['authorPhotoUrl'] as String?,
      isDeleted: json['isDeleted'] as bool? ?? false,
      parentCommentId: json['parentCommentId'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
    );
  }
}
