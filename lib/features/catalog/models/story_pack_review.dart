import 'package:cloud_firestore/cloud_firestore.dart';

/// storyPacks/{packId}/reviews/{uid} 문서 — 문서 id가 곧 작성자 uid라서
/// "이 팩에 유저 하나당 리뷰 하나"가 스키마 자체로 강제된다(재작성 시 같은
/// 문서를 덮어쓴다). [uid]는 문서 id를 그대로 들고 있는 것뿐이라 별도 필드로
/// 저장하지 않는다 — comments/{commentId}는 id가 자동 생성이라 uid를 필드로
/// 저장하는 것과 대조된다.
class StoryPackReview {
  final String uid;
  final int rating;
  final String text;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String authorDisplayName;
  final String? authorPhotoUrl;

  const StoryPackReview({
    required this.uid,
    required this.rating,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
  });

  factory StoryPackReview.fromFirestore(String uid, Map<String, dynamic> json) {
    return StoryPackReview(
      uid: uid,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      authorDisplayName: json['authorDisplayName'] as String? ?? '익명',
      authorPhotoUrl: json['authorPhotoUrl'] as String?,
    );
  }
}
