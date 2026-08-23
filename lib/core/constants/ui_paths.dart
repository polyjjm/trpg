class UiPaths {
  // Telo 로고
  static const String logo = 'assets/images/telo_logo.svg';
  // Telo 로고 — 종이색(#F7F1E6) 라운드 스퀘어 안에 마크(favicon/앱 아이콘 원본).
  static const String logoIcon = 'assets/images/telo_icon.svg';

  // 홈 탭 상단 책장 삽화 배경 — 래스터(PNG) placeholder. 이 배경을 쓰던
  // LibraryHeader는 삭제됐고(데스크톱은 CatalogDesktopNavBar가 대체), 지금은
  // 아무 데서도 참조하지 않는다 — 나중에 홈 상단 헤더를 다시 만들 때 쓰라고
  // 남겨 둔다. 실제 삽화로 교체될 때도 SVG가 아니라 PNG/WebP 같은 래스터로
  // 두는 걸 권장한다 — SvgPicture.asset이 일부 실사용 브라우저(CanvasKit)에서
  // 헤더를 완전 검정으로 만드는 원인으로 지목돼 래스터로 교체했다(끝내 해결
  // 되지 않은 버그다 — doc/library_header_black_screen_investigation.md 참고).
  static const String bookshelfBackground = 'assets/images/bookshelf_bg.png';

  // 스토리 선택지 버튼 배경
  static const String choiceBg =
      'assets/images/system/selectButtonbg.png';

  // 전투 카드 이미지
  static const String failCard =
      'assets/images/system/failCard.png';
  static const String lightAttackCard =
      'assets/images/system/lightAttackCard.png';
  static const String attackCard =
      'assets/images/system/attackCard.png';
  static const String heavyAttackCard =
      'assets/images/system/heavyAttackCard.png';
  static const String backCard =
      'assets/images/system/backCard.png';

  // 하단 패널 메뉴 아이콘
  static const String statusIcon =
      'assets/images/system/status.png';
  static const String equipmentIcon =
      'assets/images/system/equipment.png';
  static const String inventoryIcon =
      'assets/images/system/inventory.png';
}