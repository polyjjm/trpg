/// writerNotices/{noticeId} 문서. 작가가 자기 스토리팩에 올리는 변경사항
/// 공지로, 게임 앱의 라이브러리/상세 화면(lib/features/catalog)에 노출된다.
class WriterNotice {
  final String id;
  final String packId;
  final String title;
  final String body;

  /// yyyy-MM-dd 형식 문자열.
  final String date;

  const WriterNotice({
    required this.id,
    required this.packId,
    required this.title,
    required this.body,
    required this.date,
  });

  factory WriterNotice.fromFirestore(String id, Map<String, dynamic> json) {
    return WriterNotice(
      id: id,
      packId: json['packId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'packId': packId,
        'title': title,
        'body': body,
        'date': date,
      };
}
