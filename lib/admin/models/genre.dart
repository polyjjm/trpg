/// genres/{genreId} 문서. Dart 하드코딩이 아니라 Firestore가 관리하는 데이터라,
/// 관리자가 앱 재배포 없이 장르를 추가/수정할 수 있다.
class Genre {
  final String id;
  final String name;
  final String slug;
  final int sortOrder;
  final bool active;

  const Genre({
    required this.id,
    required this.name,
    required this.slug,
    required this.sortOrder,
    required this.active,
  });

  factory Genre.fromFirestore(String id, Map<String, dynamic> json) {
    return Genre(
      id: id,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
    );
  }
}
