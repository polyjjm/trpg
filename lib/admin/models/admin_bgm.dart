import 'package:cloud_firestore/cloud_firestore.dart';

/// bgmLibrary/{bgmId} 문서. 실제 오디오 파일은 Firebase Storage에 올라가고,
/// 이 문서는 그 파일을 가리키는 색인(이름 + 다운로드 URL + 업로더/업로드
/// 시각)일 뿐이다 — sfxLibrary/{sfxId}(admin_sfx.dart)와 같은 패턴이다.
/// sfxLibrary와 달리 category가 없다 — 효과음은 "문/발소리/비명/..."처럼
/// 상황별로 골라 쓰는 라이브러리라 분류가 필요했지만, BGM은 트랙 수 자체가
/// 적고 이름만으로 구분하기 충분하다는 판단(요청 사양에도 없다).
class AdminBgm {
  final String id;
  final String name;
  final String storageUrl;
  final String? uploadedBy;
  final DateTime? createdAt;

  const AdminBgm({
    required this.id,
    required this.name,
    required this.storageUrl,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory AdminBgm.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminBgm(
      id: id,
      name: json['name'] as String? ?? '',
      storageUrl: json['storageUrl'] as String? ?? '',
      uploadedBy: json['uploadedBy'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
