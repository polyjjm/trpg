/// homeBanners/{bannerId} 문서 — 리더 쪽 모델. admin의
/// lib/admin/models/home_banner.dart와 필드 모양은 같지만, lib/features/**가
/// lib/admin/을 import하지 않는 프로젝트 규칙 때문에 따로 둔 사본이다
/// (genres/Genre와 같은 패턴). 이미지 전용 배너로 단순화되면서 headline/
/// subtext/backgroundColorHex는 더 안 쓴다 — imageUrl 하나로 카드 전체를
/// 채운다.
///
/// [eyebrow]/[title]/[subtitle]은 전부 선택적인 텍스트 오버레이 — 셋 다
/// 서로 독립적이지만(예: title만 있고 subtitle은 없어도 정상), [title]이
/// 없으면([title]이 null이거나 빈 문자열) 오버레이 자체(스크림 그라디언트
/// 포함)를 렌더링하지 않는다 — 기존 이미지 전용 배너가 그대로 유지되게
/// 하는 게 이 필드의 핵심 규칙이다(HeroBannerSection 참고).
class HomeBanner {
  final String id;
  final String imageUrl;
  final String? linkedPackId;
  final String? eyebrow;
  final String? title;
  final String? subtitle;

  const HomeBanner({
    required this.id,
    required this.imageUrl,
    required this.linkedPackId,
    this.eyebrow,
    this.title,
    this.subtitle,
  });

  factory HomeBanner.fromFirestore(String id, Map<String, dynamic> json) {
    return HomeBanner(
      id: id,
      imageUrl: json['imageUrl'] as String? ?? '',
      linkedPackId: json['linkedPackId'] as String?,
      eyebrow: json['eyebrow'] as String?,
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
    );
  }

  /// [title]이 있어야 텍스트 오버레이(스크림 포함)를 그린다 — eyebrow/subtitle만
  /// 있고 title이 없는 조합은 지원 대상이 아니다(요청사항).
  bool get hasTextOverlay => title != null && title!.isNotEmpty;
}
