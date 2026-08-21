import 'package:cloud_firestore/cloud_firestore.dart';

/// homeBanners/{bannerId} 문서 — admin이 홈 화면 상단 히어로 배너를 관리하는
/// 원본. 리더 쪽 lib/features/catalog/models/home_banner.dart와 필드 모양은
/// 같지만, admin/reader가 서로 import하지 않는 기존 관례(genres와 같은
/// 이유)를 그대로 따라 별개 클래스로 둔다. 이미지 전용 배너로 단순화되면서
/// headline/subtext/backgroundColorHex는 더 안 쓴다.
class AdminHomeBanner {
  final String id;

  /// admin/home_banners/{bannerId}.jpg에 업로드된 배너 이미지의 다운로드 URL.
  final String imageUrl;

  final String? linkedPackId;
  final int sortOrder;
  final bool active;
  final DateTime? startAt;
  final DateTime? endAt;

  const AdminHomeBanner({
    required this.id,
    required this.imageUrl,
    required this.linkedPackId,
    required this.sortOrder,
    required this.active,
    required this.startAt,
    required this.endAt,
  });

  factory AdminHomeBanner.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminHomeBanner(
      id: id,
      imageUrl: json['imageUrl'] as String? ?? '',
      linkedPackId: json['linkedPackId'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      startAt: (json['startAt'] as Timestamp?)?.toDate(),
      endAt: (json['endAt'] as Timestamp?)?.toDate(),
    );
  }
}
