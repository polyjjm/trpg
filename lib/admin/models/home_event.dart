import 'package:cloud_firestore/cloud_firestore.dart';

/// homeEvents/{eventId} 문서 — admin이 홈 화면 진입 시 뜨는 이벤트 팝업을
/// 관리하는 원본. 리더 쪽 lib/features/catalog/models/home_event.dart와
/// 필드 모양은 같지만, admin/reader가 서로 import하지 않는 기존 관례
/// (homeBanners/genres와 같은 이유)를 그대로 따라 별개 클래스로 둔다.
///
/// [linkedPackId]는 AdminHomeBanner의 같은 필드와 정확히 같은 규칙 —
/// 새 링크 스킴 없이 기존 "이벤트 ↔ 스토리팩" 참조를 그대로 재사용한다.
class AdminHomeEvent {
  final String id;

  /// admin/home_events/{eventId}.jpg에 업로드된 이벤트 이미지의 다운로드 URL.
  final String imageUrl;

  final String? title;
  final String? linkedPackId;
  final int sortOrder;
  final bool active;
  final DateTime? startDate;
  final DateTime? endDate;

  const AdminHomeEvent({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.linkedPackId,
    required this.sortOrder,
    required this.active,
    required this.startDate,
    required this.endDate,
  });

  factory AdminHomeEvent.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminHomeEvent(
      id: id,
      imageUrl: json['imageUrl'] as String? ?? '',
      title: json['title'] as String?,
      linkedPackId: json['linkedPackId'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      startDate: (json['startDate'] as Timestamp?)?.toDate(),
      endDate: (json['endDate'] as Timestamp?)?.toDate(),
    );
  }
}
