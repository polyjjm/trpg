# BGM 플레이스홀더

아직 배경음악 파일이 없고, 이 폴더를 가리키는 호출부도 아직 없다.

스토리 노드가 Firestore로 옮겨가면(`lib/admin/` 작가 편집기 참고) 노드마다
`bgmId`(선택 이미지처럼 Firebase Storage에 올린 트랙을 가리키는 값)를 들고 있을
예정이고, 그때 `AudioService.instance.playBgm(...)`으로 재생/전환한다.

그전에 로컬 번들 트랙을 테스트해보고 싶으면 이 폴더에 mp3를 넣고
`assets/audio/bgm/파일명.mp3` 경로로 `AudioService.instance.playBgm(...)`을
직접 호출하면 된다 — `AudioService`는 번들 애셋 경로와 `http(s)` URL을 모두
받아들인다.
