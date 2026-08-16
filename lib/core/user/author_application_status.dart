/// users/{uid}.authorApplicationStatus — 본인의 최신 authorApplications/{uid}
/// 문서 상태를 비정규화해 둔 값. 편집기 진입 화면이 이 값 하나만 보고 분기할 수
/// 있게 하기 위함이다.
enum AuthorApplicationStatus { none, pending, approved, rejected }

extension AuthorApplicationStatusJson on AuthorApplicationStatus {
  String get wireValue => name;

  static AuthorApplicationStatus fromWire(String? value) {
    return AuthorApplicationStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => AuthorApplicationStatus.none,
    );
  }
}
