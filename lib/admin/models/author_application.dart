import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/user/author_application_status.dart';

/// authorApplications/{uid} 문서. 문서 id가 곧 신청자의 uid다 — 계정당 최신
/// 신청서 1건만 보관하고, 반려 후 재신청은 같은 문서를 덮어쓴다.
class AuthorApplication {
  final String uid;
  final String displayName;
  final String bio;
  final List<String> portfolioLinks;
  final AuthorApplicationStatus status;
  final String? rejectionReason;
  final String? reviewedBy;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  const AuthorApplication({
    required this.uid,
    required this.displayName,
    required this.bio,
    required this.portfolioLinks,
    required this.status,
    this.rejectionReason,
    this.reviewedBy,
    this.submittedAt,
    this.reviewedAt,
  });

  factory AuthorApplication.fromFirestore(String uid, Map<String, dynamic> json) {
    return AuthorApplication(
      uid: uid,
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      portfolioLinks: (json['portfolioLinks'] as List<dynamic>?)?.cast<String>() ?? const [],
      status: AuthorApplicationStatusJson.fromWire(json['status'] as String?),
      rejectionReason: json['rejectionReason'] as String?,
      reviewedBy: json['reviewedBy'] as String?,
      submittedAt: (json['submittedAt'] as Timestamp?)?.toDate(),
      reviewedAt: (json['reviewedAt'] as Timestamp?)?.toDate(),
    );
  }
}
