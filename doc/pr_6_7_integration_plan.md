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

## 6. 하지 않는 것

- **`images` read 축소**: 이번에도 하지 않는다. 카탈로그 표지 경로
  (`_toVisiblePacks`/`fetchPacksByIds`)가 여전히 직접 읽는다.
- **legacy `nodes` 문서 삭제**: #7의 롤백 속성(문서를 복사만 하고 legacy를 남김)을
  보존해야 하므로 이번 범위에서 지우지 않는다.
- **`nodes` 작가 write 축소(위 표 마지막 줄)**: 마이그레이션이 실제 운영에서
  검증된 뒤 별도로 진행한다. 지금 같이 배포하면 롤백 시 admin 클라이언트가
  legacy 경로로 되돌아갔을 때 쓰기가 막힌다.
