/// homeEvents/{eventId} 문서 — 리더 쪽 모델. admin의
/// lib/admin/models/home_event.dart와 필드 모양은 같지만, lib/features/**가
/// lib/admin/을 import하지 않는 프로젝트 규칙 때문에 따로 둔 사본이다
/// (homeBanners/genres와 같은 패턴).
///
/// [linkedPackId]는 homeBanners의 같은 필드와 정확히 같은 규칙 — 새 링크
/// 스킴을 만드는 대신, 이미 있는 "이 이벤트가 어떤 스토리팩과 연결돼
/// 있는가" 자원 참조를 그대로 재사용한다. 외부 URL로 열 방법은 이 프로젝트에
/// 아직 없고(open_external_link.dart는 admin↔독자 앱 전환 전용, 모바일에서는
/// 아무 동작도 안 하는 웹 전용 유틸이라 이 용도로 못 쓴다), 그래서 여기서도
/// 내부 팩 연결 하나만 지원한다.
class HomeEvent {
  final String id;
  final String imageUrl;
  final String? title;
  final String? linkedPackId;
  final int sortOrder;

  const HomeEvent({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.linkedPackId,
    required this.sortOrder,
  });

  factory HomeEvent.fromFirestore(String id, Map<String, dynamic> json) {
    return HomeEvent(
      id: id,
      imageUrl: json['imageUrl'] as String? ?? '',
      title: json['title'] as String?,
      linkedPackId: json['linkedPackId'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
