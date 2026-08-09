# SFX 플레이스홀더

여기에 아래 파일들을 넣으면 코드 변경 없이 바로 재생된다
(`lib/core/audio/system_sfx.dart` 참고):

- `item_pickup.mp3` — 아이템 획득
- `battle_win.mp3` — 전투 승리
- `battle_lose.mp3` — 전투 패배
- `heart_lose.mp3` — 하트 감소
- `button_click.mp3` — 공용 버튼 탭

지금은 실제 파일이 없다. `AudioService`는 파일이 없어도 조용히 실패를 삼키므로
(디버그 로그만 남기고) 앱이 죽지는 않지만, 당연히 소리도 나지 않는다. 파일을
넣을 때는 여기 적힌 파일명을 그대로 맞춰야 한다.
