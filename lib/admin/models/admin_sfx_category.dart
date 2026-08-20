/// sfxLibrary/{sfxId}.category — 업로드 시 고르는 고정 분류. images의
/// AdminImageCategory와 같은 이유로 자유 태그가 아니라 고정 enum이다 —
/// 효과음 라이브러리 탭의 필터 칩, 카드 배지, 연출 효과 편집기의 효과음
/// 피커(SfxPickerField)의 카테고리 좁히기가 전부 이 값을 쓴다.
enum AdminSfxCategory { door, footsteps, scream, heartbeat, other }

extension AdminSfxCategoryJson on AdminSfxCategory {
  String get wireValue => name;

  /// 값이 없거나 모르는 문자열이면 '기타'로 취급한다 —
  /// AdminImageCategoryJson.fromWire와 같은 방어적 기본값이다.
  static AdminSfxCategory fromWire(String? value) {
    return AdminSfxCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => AdminSfxCategory.other,
    );
  }
}

extension AdminSfxCategoryLabel on AdminSfxCategory {
  String get label => switch (this) {
    AdminSfxCategory.door => '문',
    AdminSfxCategory.footsteps => '발소리',
    AdminSfxCategory.scream => '비명',
    AdminSfxCategory.heartbeat => '심장박동',
    AdminSfxCategory.other => '기타',
  };
}
