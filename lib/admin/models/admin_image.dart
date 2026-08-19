import 'admin_image_category.dart';

/// images/{imageId} 문서. 실제 파일은 Firebase Storage에 올라가고, 이 문서는
/// 그 파일을 가리키는 색인(이름 + 다운로드 URL + 분류)일 뿐이다.
class AdminImage {
  final String id;
  final String name;
  final String url;
  final AdminImageCategory category;

  const AdminImage({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
  });

  factory AdminImage.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminImage(
      id: id,
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      category: AdminImageCategoryJson.fromWire(json['category'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'category': category.wireValue,
  };
}
