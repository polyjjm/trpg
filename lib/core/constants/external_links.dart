/// 독자 앱 ↔ 작가 편집기는 서로 다른 진입점으로 따로 빌드/배포되는 별도의
/// 웹 앱이라(lib/main.dart vs lib/main_admin.dart), 한쪽에서 다른 쪽으로
/// "전환"하는 건 인앱 네비게이션이 아니라 실제 URL 이동이다.
///
/// 지금은 둘 다 실제로 배포된 곳이 없어(Dockerfile은 게임 앱만 빌드하고,
/// 작가 편집기는 아직 어떤 배포 파이프라인에도 들어있지 않다) 아래 값은
/// 자리만 잡아둔 플레이스홀더다 — 실제 호스팅 주소가 정해지면 이 두 상수만
/// 바꾸면 된다.
class ExternalLinks {
  ExternalLinks._();

  /// TODO: 작가 편집기(lib/main_admin.dart)가 실제로 배포되면 그 URL로 교체.
  static const String authorToolUrl = 'https://TODO-author-tool-url.example/';

  /// TODO: 게임 앱(lib/main.dart)이 실제로 배포되면 그 URL로 교체.
  static const String readerAppUrl = 'https://TODO-reader-app-url.example/';
}
