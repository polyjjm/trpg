/// genres/{genreId} 문서 — 리더 쪽 모델. lib/admin/models/genre.dart와 필드
/// 모양은 같지만, lib/features/**는 lib/admin/을 절대 import하지 않는다는
/// 프로젝트 규칙(CLAUDE.md, 모바일 빌드가 admin 코드를 안 끌어오게) 때문에
/// 일부러 따로 둔 별개 클래스다 — admin의 AdminStoryPack/StoryPack이 이름만
/// 같고 무관한 클래스인 것과 같은 패턴.
class Genre {
  final String id;
  final String name;
  final String slug;
  final int sortOrder;

  const Genre({
    required this.id,
    required this.name,
    required this.slug,
    required this.sortOrder,
  });

  factory Genre.fromFirestore(String id, Map<String, dynamic> json) {
    return Genre(
      id: id,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
