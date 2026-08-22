import 'package:cloud_firestore/cloud_firestore.dart';

/// notices/{noticeId} 문서 — 앱 전체 공지사항 한 건(하단 탭의 "공지사항").
/// 스토리팩 하나에 딸린 작가 공지(writerNotices, lib/admin/models/writer_notice.dart와
/// 짝을 이루는 다른 컬렉션)와는 완전히 별개다 — 이름이 비슷해서 헷갈리기
/// 쉽지만, 이건 팩과 무관한 플랫폼 전체 공지다.
class Notice {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;

  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory Notice.fromFirestore(String id, Map<String, dynamic> json) {
    return Notice(
      id: id,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
