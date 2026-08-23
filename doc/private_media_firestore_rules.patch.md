# #16 media Firestore rules hardening

`resolveStoryMedia`가 리더의 정상 미디어 경로를 서버 게이트로 옮겼더라도,
현재 체크인된 `firestore.rules`는 로그인 독자가 `images`, `sfxLibrary`,
`bgmLibrary` 색인 문서를 직접 읽는 것을 허용한다. 이 문서들에는 기존
Firebase download-token URL이 들어 있으므로 아래 세 규칙을 반드시 같이
좁혀야 #16의 reader 우회가 닫힌다.

```diff
 match /images/{imageId} {
-  allow read: if isSignedIn();
+  allow read: if isAuthorOrAdmin();
   allow create, delete: if isAuthorOrAdmin();
 }

 match /sfxLibrary/{sfxId} {
-  allow read: if isSignedIn();
+  allow read: if isAuthorOrAdmin();
   allow create, delete: if isAuthorOrAdmin();
 }

 match /bgmLibrary/{bgmId} {
-  allow read: if isSignedIn();
+  allow read: if isAuthorOrAdmin();
   allow create, delete: if isAuthorOrAdmin();
 }
```

리더의 `StoryReaderRepository`는 이 변경과 함께 `resolveStoryMedia`를 사용하므로
더 이상 위 세 컬렉션의 read 권한이 필요 없다. 작가/admin 라이브러리 화면은
기존처럼 읽을 수 있다.

주의: 이 저장소의 `firestore.rules`와 실제 Firebase 콘솔 배포 규칙이 과거에
드리프트한 기록이 있으므로, 체크인 파일뿐 아니라 실제 배포본에도 동일한
세 변경이 적용됐는지 확인해야 한다.
