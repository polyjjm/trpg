/// 독자 앱 ↔ 작가 편집기는 서로 다른 진입점으로 따로 빌드/배포되는 별도의
/// 웹 앱이라(lib/main.dart vs lib/main_admin.dart), 한쪽에서 다른 쪽으로
/// "전환"하는 건 인앱 네비게이션이 아니라 실제 URL 이동이다.
///
/// 지금은 둘 다 실제로 배포된 곳이 없어(Dockerfile은 게임 앱만 빌드하고,
/// 작가 편집기는 아직 어떤 배포 파이프라인에도 들어있지 않다) 아래 두 값은
/// 자리만 잡아둔 플레이스홀더다 — 실제 호스팅 주소가 정해지면 그 두 상수만
/// 바꾸면 된다.
class ExternalLinks {
  ExternalLinks._();

  /// TODO: 작가 편집기(lib/main_admin.dart)가 실제로 배포되면 그 URL로 교체.
  static const String authorToolUrl = 'https://TODO-author-tool-url.example/';

  /// TODO: 게임 앱(lib/main.dart)이 실제로 배포되면 그 URL로 교체.
  static const String readerAppUrl = 'https://TODO-reader-app-url.example/';

  /// 관리자 페이지를 새 창으로 열 때 쓰는 URL.
  ///
  /// 관리자 페이지는 작가 편집기와 **같은 앱**(main_admin.dart) 안의 화면이라
  /// 별도 배포물이 아니다. 그래서 고정 주소를 적어 둘 수 없고, 지금 보고 있는
  /// 주소에 `admin=1`만 붙인다 — localhost:3000에서 개발 중이든 실제 도메인에
  /// 올라갔든 그대로 동작한다(Uri.base는 웹에서 현재 URL이다).
  ///
  /// 그 창이 뜨면 AuthorToolPage가 [isAdminDeepLink]를 보고 관리자 페이지를
  /// 곧바로 띄운다. 로그인/역할 확인은 AdminGatePage가 평소처럼 먼저 처리한다.
  static String get adminDashboardUrl => Uri.base
      .replace(
    queryParameters: {...Uri.base.queryParameters, _adminFlag: '1'},
  )
      .toString();

  /// 이 창이 "관리자 페이지로 바로 가라"고 열린 창인지.
  static bool get isAdminDeepLink =>
      Uri.base.queryParameters[_adminFlag] == '1';

  static const String _adminFlag = 'admin';
}
