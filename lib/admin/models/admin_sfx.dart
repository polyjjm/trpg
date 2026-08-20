import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_sfx_category.dart';

/// sfxLibrary/{sfxId} 문서. 실제 오디오 파일은 Firebase Storage에 올라가고,
/// 이 문서는 그 파일을 가리키는 색인(이름 + 다운로드 URL + 분류 +
/// 업로더/업로드 시각)일 뿐이다 — images/{imageId}(admin_image.dart)와 같은
/// 패턴이다. uploadedBy/createdAt은 images에는 없는 필드인데, 효과음은
/// 여러 작가가 파일을 공유해서 올리는 라이브러리라 "누가 언제 올렸는지"를
/// 처음부터 같이 남겨 둔다.
class AdminSfx {
  final String id;
  final String name;
  final AdminSfxCategory category;
  final String storageUrl;
  final String? uploadedBy;
  final DateTime? createdAt;

  const AdminSfx({
    required this.id,
    required this.name,
    required this.category,
    required this.storageUrl,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory AdminSfx.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminSfx(
      id: id,
      name: json['name'] as String? ?? '',
      category: AdminSfxCategoryJson.fromWire(json['category'] as String?),
      storageUrl: json['storageUrl'] as String? ?? '',
      uploadedBy: json['uploadedBy'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
