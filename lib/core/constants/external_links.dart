/// 독자 앱 ↔ 작가 편집기는 서로 다른 진입점으로 따로 빌드/배포되는 별도의
/// 웹 앱이라(lib/main.dart vs lib/main_admin.dart), 한쪽에서 다른 쪽으로
/// "전환"하는 건 인앱 네비게이션이 아니라 실제 URL 이동이다.
///
/// 지금은 둘 다 실제로 배포된 곳이 없어(Dockerfile은 게임 앱만 빌드하고,
/// 작가 편집기는 아직 어떤 배포 파이프라인에도 들어있지 않다) 아래 값은
/// 자리만 잡아둔 플레이스홀더다 — 실제 호스팅 주소가 정해지면 이 상수들만
/// 바꾸면 된다.
class ExternalLinks {
  ExternalLinks._();

  /// TODO: 작가 편집기(lib/main_admin.dart)가 실제로 배포되면 그 URL로 교체.
  static const String authorToolUrl = 'https://TODO-author-tool-url.example/';

  /// TODO: 게임 앱(lib/main.dart)이 실제로 배포되면 그 URL로 교체.
  static const String readerAppUrl = 'https://TODO-reader-app-url.example/';

  /// 관리자 페이지 — 작가 도구에서 "관리자 페이지"를 새 창으로 열 때 쓴다.
  ///
  /// 관리자 페이지는 작가 편집기와 같은 앱(main_admin.dart) 안의 화면이라
  /// 별도 배포물이 아니다. 그래서 기본값은 빈 문자열이고, 이때 작가 도구는
  /// 예전처럼 같은 창에서 Navigator.push로 이동한다 — 새 창이 안 되는 것보다
  /// 그쪽이 낫다. 라우팅이 붙어 실제 주소(예: '/admin')가 생기면 여기에
  /// 채우면 그때부터 새 창으로 열린다.
  static const String adminDashboardUrl = '';
}
