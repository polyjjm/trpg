/// 코드에서 직접 트리거하는 "기본" 효과음 이벤트들.
///
/// 실제 파일은 assets/audio/sfx/에 있어야 하지만, 지금은 자리표시자만 있다
/// (assets/audio/sfx/README.md 참고) — 파일이 없어도 [AudioService]가 조용히
/// 실패를 삼키므로 앱이 죽지는 않는다.
///
/// 나중에 선택지가 Firestore의 sfxId(선택 이미지처럼 업로드된 파일을 가리키는
/// URL)를 들고 있게 되면, 호출부는 `choice.sfxId ?? SystemSfx.itemPickup.assetPath`
/// 처럼 이 기본값을 폴백으로만 쓰면 된다 — [AudioService.playSfx]는 번들 애셋
/// 경로와 URL을 구분 없이 받는다.
enum SystemSfx {
  itemPickup('assets/audio/sfx/item_pickup.mp3'),
  battleWin('assets/audio/sfx/battle_win.mp3'),
  battleLose('assets/audio/sfx/battle_lose.mp3'),
  heartLose('assets/audio/sfx/heart_lose.mp3'),
  buttonClick('assets/audio/sfx/button_click.mp3');

  final String assetPath;

  const SystemSfx(this.assetPath);
}
