# PR #6 + #7 통합 계획

PR #6(유료 노드 하드닝)과 #7(draft/live 분리)을 함께 랜딩하기 위한 계획.
둘 다 자기 롤아웃 문서에서 **단독 배포 금지**를 명시했고, 둘 다 현재
엔트리포인트와 충돌한다. 이 문서는 구현 **전에** 순서 결정을 못박아 두려고
먼저 쓴다.

전제: #1~#5는 이미 머지·배포됐다. 지금 라이브는
`functions/package.json` `"main": "lib/secure_entrypoint_v2.js"`이고,
`storage.rules`가 버전 관리되며, `sfxLibrary`/`bgmLibrary` read는
author/admin으로 좁혀져 있고 **`images`는 의도적으로 `isSignedIn()`**이다
(카탈로그 표지 경로 때문 — 그 규칙 위 주석 참고).

---

## 1. 엔트리포인트 통합

### 문제

두 PR 모두 자기 엔트리포인트를 만들고 `package.json`의 `"main"`을 그쪽으로
옮긴다. 그런데 둘 다 이렇게 시작한다:

```ts
export * from "./index";   // ← PR #6, PR #7 둘 다
```

`index.ts`는 `synthesizeNodeTts` / `previewNodeTts` /
`onNodeApprovedGenerateTts`의 **legacy 원본**을 export한다. `secure_entrypoint.ts`
가 그 셋을 보안 래퍼로 교체해 둔 게 #4의 핵심인데, `export * from "./index"`로
시작하면 그 교체가 통째로 무효가 된다 — 컴파일도 되고 배포도 되고 함수 이름도
전부 그대로라 **아무 증상 없이** 5분짜리 signed URL 대신 영구 Firebase
download-token URL을 다시 내보내기 시작한다. `secure_entrypoint_v2.ts` 맨 위
경고 주석이 정확히 이 상황을 위해 있는 것이다.

### 설계 — 선형 체인, 각 층이 앞 층 위에 쌓인다

파일을 새로 만들지 않고 **기존 `secure_entrypoint_v2.ts`를 최상위 층으로
계속 쓴다.** 두 PR의 엔트리포인트 파일은 삭제한다(`export * from "./index"`
라는 함정을 저장소에 남겨 두지 않는다).

```
index.ts                     (기반: 15개 함수, TTS 3개는 legacy 원본)
   ↓ import * as legacy
secure_entrypoint.ts         (#4: 비-TTS 12개 이름 재노출 + TTS 3개 보안 래퍼로 교체
                                  + migrateLegacyTtsTokens{Now,Scheduled})
   ↓ export *
secure_entrypoint_v2.ts      (#4: + resolveStoryMedia
                              #6: + fetchReaderStoryNodes / maintainPublishedNodeCount
                                    / backfillPublishedNodeCounts
                              #7: + backfillNodeDraftDocuments)
```

`"main"`은 `lib/secure_entrypoint_v2.js`로 **그대로 둔다**. 배포 시 함수 소스
경로가 바뀌지 않는 게 부수 효과로 따라온다.

**지켜야 하는 불변식**: 어떤 층도 `export * from "./index"`를 하지 않는다.
`index.ts`를 참조하는 건 `secure_entrypoint.ts`의 `import * as legacy` 하나뿐이고,
그건 이름을 하나씩 골라 재노출하므로 뒤 층의 래퍼를 가릴 수 없다.

**검증 방법**(정적 grep 말고 실제 빌드 산출물로):

```bash
npm run build
node -e "const m=require('./lib/secure_entrypoint_v2.js');
         console.log(Object.keys(m).sort().join('\n'))"
```

그리고 TTS 3개가 래퍼로 해석되는지는 소스 위치로 확인한다 — 래퍼는
`secure_entrypoint.ts`에 정의돼 있으므로 `index.ts`의 원본과 **다른 함수 객체**여야
한다.

### 기대 export 목록 (18 → 22)

기존 18개는 하나도 사라지면 안 된다. 사라진 이름은 다음 functions 배포에서
**삭제**된다.

| 함수 | 실제 해석되는 모듈 | 상태 |
|---|---|---|
| `purchasePack` | index.ts (재노출) | 유지 |
| `purchaseBundle` | index.ts (재노출) | 유지 |
| `confirmCoinCharge` | index.ts (재노출) | 유지 |
| `refundCoinCharge` | index.ts (재노출) | 유지 |
| `kakaoSignIn` | index.ts (재노출) | 유지 |
| `setAuthorAccountDisabled` | index.ts (재노출) | 유지 |
| `onReviewWritten` | index.ts (재노출) | 유지 |
| `onCommentLikeWritten` | index.ts (재노출) | 유지 |
| `computeDailyRankingSnapshot` | index.ts (재노출) | 유지 |
| `computeDailyRevenueSnapshot` | index.ts (재노출) | 유지 |
| `refreshTypecastVoices` | index.ts (재노출) | 유지 |
| `refreshTypecastVoiceCacheScheduled` | index.ts (재노출) | 유지 |
| `synthesizeNodeTts` | **secure_entrypoint.ts (래퍼)** | 유지 |
| `previewNodeTts` | **secure_entrypoint.ts (래퍼)** | 유지 |
| `onNodeApprovedGenerateTts` | **secure_entrypoint.ts (래퍼)** | 유지 |
| `resolveStoryMedia` | secure_story_media.ts | 유지 |
| `migrateLegacyTtsTokensNow` | secure_entrypoint.ts | 유지 |
| `migrateLegacyTtsTokensScheduled` | secure_entrypoint.ts | 유지 |
| `fetchReaderStoryNodes` | secure_reader_nodes.ts | **신규 (#6)** |
| `maintainPublishedNodeCount` | secure_reader_nodes.ts | **신규 (#6)** |
| `backfillPublishedNodeCounts` | secure_reader_nodes.ts | **신규 (#6)** |
| `backfillNodeDraftDocuments` | draft_live_migration.ts | **신규 (#7)** |

---

## 2. 클라이언트 충돌 해소

### `story_reader_repository.dart` — #6 vs 현재 main (#4 + #23)

정면 충돌이다. #6은 #4 머지 **전에** 작성돼서, 파일 안에 이렇게 적혀 있다:

> "PR #4의 private story-media 전달 구조가 머지되기 전까지는 기존 공유
> 라이브러리 조인을 유지한다. #4가 머지되면 이 세 메서드는 resolveStoryMedia
> 호출로 교체할 수 있다."

즉 #6을 그대로 받으면:
- `resolveStoryMedia` 경로가 사라지고 `images`/`sfxLibrary`/`bgmLibrary` 직접
  조인으로 되돌아간다 → **sfx/bgm은 이미 author/admin으로 좁혀 놨으므로 독자에게
  permission-denied가 난다.**
- `StoryMediaSession`(#23의 signed URL 만료 대응)이 통째로 날아간다.

**해소**: 두 PR의 기여는 서로 다른 축이라 합성이 자연스럽다.
- **#6이 바꾸는 축**: 노드 *본문*을 어디서 가져오는가 → Firestore 직접 쿼리에서
  `fetchReaderStoryNodes` 호출로.
- **main이 가진 축**: 미디어 *URL*을 어디서 가져오는가 → `resolveStoryMedia` +
  `StoryMediaSession` 만료 관리.

따라서 현재 `openReadingSession()`에서 **노드 조회 부분만** 콜러블로 바꾸고,
그 뒤 `collectMediaIds` → `resolveMedia` → `StoryMediaSession` 흐름은 그대로 둔다.
#6이 지운 doc 주석 중 여전히 맞는 것은 되살린다.

### `story_pack_repository.dart` — #6

충돌 없음. `_fetchPublishedNodeCounts()`(collectionGroup 스캔) 제거 +
`publishedNodeCount` 비정규화 필드 사용. 표지용 `_fetchImageUrls`는 그대로 남는데,
이건 `images`를 `isSignedIn()`으로 남겨 둔 결정과 일관된다.

이 변경이 #4/#5 때 열어 뒀던 구멍을 실제로 닫는다 — `{path=**}/nodes`를 열어
둘 수밖에 없었던 유일한 이유가 이 스캔이었다(`codebase_audit.md` #2 참고).

### `admin_story_repository.dart` — #7

충돌 없음(파일 전체가 #7 전용). 다만 #7의 diff가 **기존 doc 주석을 대량으로
삭제**한다 — 동작과 무관한 손실이므로 되살린다. PR #1의 `rejectNode` 수정
(`liveSnapshot != null`이면 published 유지)은 #7 안에도 보존돼 있다.

---

## 3. TTS 미리듣기 공백 (#7의 알려진 이슈)

`previewNodeTts`는 `storyPacks/{packId}/nodes/{nodeId}` 존재를 확인한 뒤
그 문서에 `ttsPreviewAudioUrl` / `ttsPreviewAudioGeneratedForBodyHash` 캐시를
읽고 쓴다. 분리 후 **한 번도 발행된 적 없는 신규 초안에는 live 문서가 의도적으로
없으므로** `not-found`로 실패한다. 새 노드를 쓰고 내레이션을 미리 들어 보는 건
지극히 평범한 작가 워크플로라 방치할 수 없다.

**선택: (a) draftNodes에 미리듣기 캐시를 둔다.**

롤아웃 문서가 제시한 대안은 (b) Firestore 캐시를 건너뛰고 짧은 수명 결과만
반환하는 것인데, 다음 이유로 (a)를 고른다:

1. **미리듣기 캐시는 본질적으로 편집기 상태다.** draft/live 분리의 정의상
   draftNodes가 맞는 자리다. live 문서에 있던 게 오히려 분리 이전의 잔재다.
2. **(b)는 유료 API를 반복 호출한다.** 캐시가 없으면 미리듣기 버튼을 누를 때마다
   Typecast가 과금된다. 지금 해시 기반 재사용이 그걸 막고 있다.
3. **(b)는 승인 시점의 캐시 승격을 깨뜨린다.** `onNodeApprovedGenerateTts`는
   미리듣기 해시가 승인 콘텐츠와 같으면 Typecast를 **다시 부르지 않고** 그 파일을
   `ttsAudioUrl`로 승격한다. 이게 신규 노드에서 가장 잘 맞는 최적화인데,
   (b)를 고르면 정확히 그 경우에만 최적화가 사라진다.

**구현 범위**(세 곳):
- `index.ts`의 `previewNodeTts`: 대상 문서를 draftNodes 우선 → 없으면 legacy
  nodes로 폴백해서 찾는다(`AdminStoryRepository.fetchNode`가 쓰는 것과 같은
  폴백 — 백필 전 환경 대응).
- `index.ts`의 `onNodeApprovedGenerateTts`: 승격할 미리듣기 캐시를 draftNodes에서
  찾고, 없으면 기존처럼 live 문서 자신의 필드를 본다(마이그레이션 이전 데이터).
  **쓰기 대상인 `ttsAudioUrl`은 계속 live 문서다** — 그건 독자용 캐시다.
- `secure_entrypoint.ts`의 `previewNodeTts` 래퍼: `normalizeNodeTtsRefs` 대상도
  같은 규칙으로 고른다.

`synthesizeNodeTts`는 손대지 않는다 — 독자용이고 live 문서만 본다.

---

## 4. 규칙 순서

두 PR 모두 "클라이언트가 먼저, 규칙이 나중"이다. 규칙이 먼저 좁혀지면 아직
배포 안 된 구 클라이언트가 즉시 깨지기 때문이다.

| 규칙 | 내용 | 언제 |
|---|---|---|
| `storyPacks/{packId}/nodes/{nodeId}` read | `isPackOwnedBy \|\| isAdmin` (published 독자 갈래 제거) | 리더 클라이언트 배포 **후** |
| `{path=**}/nodes/{nodeId}` read | `isAdmin()`만 | 리더 클라이언트 배포 **후** |
| `storyPacks/{packId}/draftNodes/{nodeId}` | read/write `isPackOwnedBy \|\| isAdmin`, 독자 접근 없음 | admin 클라이언트 배포 **전** |
| `{path=**}/draftNodes/{nodeId}` read | `isAdmin()`만 | admin 클라이언트 배포 **전** |
| `nodes` 작가 write 축소 | 승인 경로만 남김 | 마이그레이션 검증 **후**(마지막) |

`{path=**}/draftNodes`를 `isAuthorOrAdmin()`이 아니라 `isAdmin()`으로 두는
이유: 이 collectionGroup을 쓰는 화면은 `watchPendingNodes()` 하나뿐이고 그건
`AdminDashboardPage`(admin 전용)에서만 열린다. author까지 열면 남의 팩 초안을
가로질러 훑을 수 있게 된다 — `{path=**}/nodes`에 `isAdmin()`을 쓴 것과 같은 판단.

**draftNodes 규칙만 클라이언트보다 먼저인 이유**: 새로 생기는 컬렉션이라 미리
열어 둬도 기존 클라이언트에 아무 영향이 없다. 반대로 `nodes` 축소는 기존
클라이언트를 깨뜨리므로 반드시 나중이다.

---

## 5. 통합 배포 순서

두 PR의 요구사항을 하나의 순서로 합친 것. 각 단계 사이에 Chrome 확인이 들어간다.

```
1. Functions 배포              (신규 4개 추가, 기존 18개 유지)
2. backfillPublishedNodeCounts 실행 (admin)      ← #6
3. backfillNodeDraftDocuments 실행 (admin)       ← #7
4. draftNodes Firestore 규칙 배포                ← 클라이언트보다 먼저(신규 컬렉션)
5. 웹 클라이언트 배포 (리더 + admin 동시)
6. nodes 잠금 규칙 배포                          ← 클라이언트보다 나중
```

**클라이언트/규칙 불일치 구간**은 5와 6 사이 하나뿐이다. 그 구간에는 노드
읽기 규칙이 아직 넓어서(published 문서를 로그인 독자가 직접 읽을 수 있음)
**보안은 아직 예전 수준**이지만, 리더는 이미 `fetchReaderStoryNodes`를 쓰므로
**기능은 정상**이다. 순서를 뒤집으면(6을 5보다 먼저) 그 구간 동안 구 클라이언트를
쓰는 모든 독자가 **읽기 자체를 못 한다** — 독자 장애가 작가 도구 잠깐의 불편보다
나쁘므로 이 순서를 택한다.

백필(2, 3)이 클라이언트 배포(5)보다 앞인 이유:
- `backfillPublishedNodeCounts`가 안 돌면 새 카탈로그 코드가 모든 팩의
  `publishedNodeCount`를 0으로 읽어 **홈 탭이 통째로 빈다**.
- `backfillNodeDraftDocuments`가 안 돌면 새 admin 코드가 draftNodes를 못 찾는다
  (`fetchNode`에 legacy 폴백이 있어 열람은 되지만, 사이드바 목록
  `watchNodeSummaries`는 draftNodes만 보므로 **노드 목록이 빈다**).

1과 2 사이에 트리거(`maintainPublishedNodeCount`)가 이미 살아 있으므로, 백필
이후 새로 승인되는 노드는 자동으로 집계가 유지된다.

---

## 5-1. 구현하면서 계획에서 벗어난 것 (기록)

계획을 쓴 뒤 실제로 머지하면서 추가로 발견해 고친 것들.

1. **`node_docs.ts`의 콜드 스타트 크래시.** 공유 헬퍼를 만들면서 모듈 최상위에
   `const db = getFirestore()`를 뒀는데, 이 모듈은 `index.ts`가 import하므로
   index.ts 본문의 `initializeApp()`보다 **먼저** 평가된다 → "The default
   Firebase app does not exist"로 **모든 함수가 콜드 스타트에서 죽는다.**
   배포 전 export 검증 스크립트가 실제로 이걸 잡았다. 접근자를 lazy 함수로
   바꿨다. (다른 모듈들이 최상위에서 불러도 괜찮은 건 전부 index 뒤에 로드되기
   때문이다 — 이 모듈만 index보다 앞선다.)

2. **`draftNodes.pendingAction` COLLECTION_GROUP 색인 누락.** PR #7이 승인
   대기함을 `collectionGroup('nodes')` → `collectionGroup('draftNodes')`로
   옮기면서 대응하는 `fieldOverrides` 항목을 안 넣었다. 그대로 배포하면
   대기함이 `FAILED_PRECONDITION`으로 죽는다 — `nodes.pendingAction` 때 이미
   똑같이 겪은 문제다(FIRESTORE_SCHEMA.md 참고). `firestore.indexes.json`에
   추가했고, 그래서 **배포 순서에 색인 단계가 하나 생겼다.**

3. **PR #7이 지운 doc 주석 89줄 복원.** 동작과 무관한 손실이라 되살렸다.

4. **`approveNode`의 `batch.update(draftRef, ...)`는 그대로 뒀다.** draft 문서가
   없으면 배치 전체가 실패한다. 백필(3단계)이 admin 클라이언트 배포(6단계)보다
   앞서므로 정상 순서에서는 일어나지 않는다. `set(merge:true)`로 바꾸면 실패는
   막지만 **콘텐츠 없는 반쪽짜리 draft 문서**가 조용히 생겨서 편집기가 빈 노드를
   보여주게 된다 — 시끄럽게 실패하는 쪽이 낫다고 판단했다.

## 5-2. 최종 배포 런북

계획의 6단계가 7단계가 됐다. 두 가지가 순서를 바꿨다:
- 색인 단계 추가(위 5-1의 2번).
- **백필 실행 수단이 admin 웹 앱 안에 있다.** 세 마이그레이션 callable을
  부르는 Dart 코드가 아예 없어서 "admin으로 실행"할 방법 자체가 없었다.
  CLI로도 안 된다 — `request.auth`를 채우려면 Firebase Auth **ID 토큰**이
  필요한데 `gcloud functions call`은 Google OIDC 토큰을 보내서 항상
  `unauthenticated`로 거부된다. 그래서 admin 대시보드에 **"유지보수" 섹션**을
  추가했고(`lib/admin/pages/maintenance_section.dart`), 그 결과 **admin 앱
  배포가 백필보다 앞서야 한다.**

리더 앱과 admin 앱은 진입점이 달라 따로 배포되므로(`lib/main.dart` /
`lib/main_admin.dart`) 이 순환을 끊을 수 있다 — admin을 먼저 올리고, 백필을
돌리고, 그다음 리더를 올린다. 그러면 **독자는 깨진 상태를 한 번도 보지 않는다.**

| # | 작업 | 명령 / 경로 | 롤백 |
|---|---|---|---|
| 1 | 색인 배포 | `firebase deploy --only firestore:indexes` | 불필요(추가만) |
| 2 | Functions 배포 | `firebase deploy --only functions` | 이전 리비전 재배포 |
| 3 | draftNodes 규칙 배포 (nodes 잠금은 아직 제외) | `firebase deploy --only firestore:rules` | 해당 match 제거 후 재배포 |
| 4 | **admin 웹 배포** | `flutter build web -t lib/main_admin.dart` → 호스팅 | 이전 빌드 재배포 |
| 5 | 백필 2건 실행 | 관리자 페이지 → 사이드바 **시스템 › 유지보수** → 1번, 2번 카드의 **실행** | 멱등, 재실행 가능 |
| 6 | **리더 웹 배포** | `flutter build web -t lib/main.dart` → 호스팅 | 이전 빌드 재배포 |
| 7 | nodes 잠금 규칙 배포 | `firebase deploy --only firestore:rules` | 독자 갈래 복원 후 재배포 |

3과 7이 둘 다 규칙 배포인 이유: `firestore.rules`는 파일 단위로 배포되므로
**나눠 배포하려면 7단계 내용을 3단계 시점에는 잠시 빼 둬야 한다.** 가장 간단한
방법은 3단계에서 전체 규칙을 배포하되 nodes 잠금 두 곳만 주석 처리하고,
7단계에서 주석을 푸는 것이다. 한 번에 합쳐 6단계 뒤에 배포하는 건 안 된다 —
4단계의 admin 클라이언트가 즉시 draftNodes를 읽기 때문이다.

**4~5 사이의 짧은 저하**: admin 앱은 배포됐는데 백필은 아직 안 돌아서 작가
편집기의 노드 목록이 잠깐 비어 보인다(`watchNodeSummaries`가 draftNodes만
본다). `fetchNode`에 legacy 폴백이 있어 이미 아는 노드를 여는 것 자체는 되고,
5단계가 끝나는 즉시 정상으로 돌아온다. 독자 쪽은 이 구간에 아무 영향이 없다.

**6~7 사이의 불일치**: 노드 읽기 규칙이 아직 넓어서 보안은 예전 수준이지만
기능은 정상이다. 순서를 뒤집으면 구 클라이언트를 쓰는 독자가 읽기 자체를 못
하므로 이 순서를 택한다.

## 6. 하지 않는 것

- **`images` read 축소**: 이번에도 하지 않는다. 카탈로그 표지 경로
  (`_toVisiblePacks`/`fetchPacksByIds`)가 여전히 직접 읽는다.
- **legacy `nodes` 문서 삭제**: #7의 롤백 속성(문서를 복사만 하고 legacy를 남김)을
  보존해야 하므로 이번 범위에서 지우지 않는다.
- **`nodes` 작가 write 축소(위 표 마지막 줄)**: 마이그레이션이 실제 운영에서
  검증된 뒤 별도로 진행한다. 지금 같이 배포하면 롤백 시 admin 클라이언트가
  legacy 경로로 되돌아갔을 때 쓰기가 막힌다.
