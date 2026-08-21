/// homeBanners/{bannerId} 문서 — 리더 쪽 모델. admin의
/// lib/admin/models/home_banner.dart와 필드 모양은 같지만, lib/features/**가
/// lib/admin/을 import하지 않는 프로젝트 규칙 때문에 따로 둔 사본이다
/// (genres/Genre와 같은 패턴). 이미지 전용 배너로 단순화되면서 headline/
/// subtext/backgroundColorHex는 더 안 쓴다 — imageUrl 하나로 카드 전체를
/// 채운다.
class HomeBanner {
  final String id;
  final String imageUrl;
  final String? linkedPackId;

  const HomeBanner({
    required this.id,
    required this.imageUrl,
    required this.linkedPackId,
  });

  factory HomeBanner.fromFirestore(String id, Map<String, dynamic> json) {
    return HomeBanner(
      id: id,
      imageUrl: json['imageUrl'] as String? ?? '',
      linkedPackId: json['linkedPackId'] as String?,
    );
  }
}
