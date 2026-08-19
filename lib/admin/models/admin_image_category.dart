/// images/{imageId}.category — 업로드 시 고르는 고정 분류. 자유 태그/폴더가
/// 아니라 3개짜리 enum으로 고정한다 — 라이브러리 그리드의 필터 칩, 카드
/// 배지, 이미지 피커(ImagePickerField)의 카테고리 좁히기가 전부 이 값을 쓴다.
enum AdminImageCategory { background, choice, other }

extension AdminImageCategoryJson on AdminImageCategory {
  String get wireValue => name;

  /// 값이 없거나 모르는 문자열이면(카테고리 필드가 생기기 전에 올라간 기존
  /// 이미지 포함) '기타'로 취급한다 — 별도 마이그레이션 없이 자동으로
  /// "미분류 → 기타" 기본값이 적용된다.
  static AdminImageCategory fromWire(String? value) {
    return AdminImageCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => AdminImageCategory.other,
    );
  }
}

extension AdminImageCategoryLabel on AdminImageCategory {
  String get label => switch (this) {
    AdminImageCategory.background => '배경',
    AdminImageCategory.choice => '선택지',
    AdminImageCategory.other => '기타',
  };
}
