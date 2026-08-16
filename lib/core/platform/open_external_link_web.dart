import 'dart:html' as html;

/// 새 탭에서 외부 URL을 연다 — 독자 앱 ↔ 작가 편집기 전환 링크 전용(둘 다
/// 별도로 빌드되는 웹 전용 앱이라 인앱 네비게이션이 아니라 실제 탭 이동이다).
void openExternalLink(String url) {
  html.window.open(url, '_blank');
}
