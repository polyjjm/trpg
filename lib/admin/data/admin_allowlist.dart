/// 작가 편집기(lib/admin/) 접근이 허용된 이메일 목록.
///
/// 지금은 본사/대리점/가맹점 같은 역할 체계가 없어, 로그인한 Firebase 계정의
/// 이메일이 이 목록에 있는지만으로 접근을 막는다 — 나중에 역할 기반 권한이
/// 생기면 Firestore 문서 기반 권한 체크로 대체할 자리다.
///
/// 새 작가/관리자를 추가하려면 이 목록에 이메일을 더하면 된다.
const List<String> adminEmailAllowlist = [
  'wnwhd788@gmail.com',
];

bool isAllowedAdminEmail(String? email) {
  if (email == null || email.isEmpty) return false;
  final normalized = email.toLowerCase();
  return adminEmailAllowlist.any((allowed) => allowed.toLowerCase() == normalized);
}
