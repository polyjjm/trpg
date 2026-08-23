import 'package:cloud_firestore/cloud_firestore.dart';

/// notices/{noticeId} 문서 — 앱 전체 공지사항 하나. lib/admin/models/writer_notice.dart
/// (스토리팩 하나에 딸린 작가 공지, writerNotices 컬렉션)와는 완전히
/// 별개다 — 이름이 비슷해서 헷갈리기 쉽지만, 이건 팩과 무관한 플랫폼
/// 전체 공지고 admin만 쓴다(작가는 못 쓴다). 리더 쪽
/// lib/features/catalog/models/notice.dart와 필드 모양은 같지만,
/// admin/reader가 서로 import하지 않는 기존 관례를 그대로 따라 별개
/// 클래스로 둔다.
class AdminGlobalNotice {
  final String id;
  final String title;
  final String body;
  final bool active;
  final String authorId;
  final DateTime? createdAt;

  const AdminGlobalNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.active,
    required this.authorId,
    required this.createdAt,
  });

  factory AdminGlobalNotice.fromFirestore(
    String id,
    Map<String, dynamic> json,
  ) {
    return AdminGlobalNotice(
      id: id,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      authorId: json['authorId'] as String? ?? '',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
