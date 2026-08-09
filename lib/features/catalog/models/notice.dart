/// 라이브러리 상단 공지사항 한 건.
/// 지금은 [data/notices.dart]에 하드코딩되어 있지만, 나중에 원격 콘텐츠 DB로
/// 옮길 것을 고려해 단순한 값 객체로 구성했다.
class Notice {
  final String title;
  final String date;
  final String body;

  const Notice({
    required this.title,
    required this.date,
    required this.body,
  });
}
