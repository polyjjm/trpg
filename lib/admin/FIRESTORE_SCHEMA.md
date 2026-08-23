# 작가 편집기 Firestore 스키마

`lib/admin/`(작가 편집기, `lib/main_admin.dart`)이 쓰는(작성) 컬렉션 문서다. 게임 앱
(`lib/main.dart`, `lib/features/**`)도 이제 이 컬렉션들을 실제로 읽는다 — `liveMetadata`/
`liveSnapshot`(마지막으로 승인된 스냅샷)을 통해서다(CLAUDE.md의 "Reader system" 절 참고).
admin 쪽 모델(`lib/admin/models/*`)과 리더 쪽 모델(`lib/features/**`, `lib/reader/**`)은
Firestore 문서 모양은 같아도 서로 import하지 않는 별개 Dart 클래스다 — admin/reader가
같은 이름의 클래스를 각자 따로 갖는 게 이 코드베이스의 의도적인 관례다.

⚠️ **이 문서는 코드가 바뀔 때 수동으로 맞춰야 하는 스냅샷이다 — 실제 스키마의
원천(source of truth)은 아니다.** 필드 모양의 최종 진실은 항상 그 필드를 실제로
읽고 쓰는 Dart 모델(`lib/admin/models/*`, `lib/features/**/models/*`)이고, 보안
규칙의 최종 진실은 항상 저장소 루트의 `firestore.rules`다(그 파일이 실제로
`firebase deploy --only firestore:rules`로 배포되는 파일이며, 이 문서 아래 있던
규칙 스니펫을 손으로 복사해 오다가 실제 배포본과 어긋난 채로 방치돼 여러 번 실제
버그(승인이 permission-denied로 막히는 문제)를 냈다 — 그래서 이제 규칙은 여기 다시
옮겨 적지 않고 `firestore.rules`를 직접 열어 보라고 안내한다). 필드/규칙이 바뀔 때
이 문서도 같이 고치되, 둘이 어긋났다면 항상 코드와 `firestore.rules`가 맞다.

## storyPacks/{packId}

```
title: string                     // "지금 편집 중인" 값 — draft 콘텐츠와 같은 성격.
authorId: string                  // 소유 작가의 Firebase Auth uid. users/{uid} 참조.
authorName: string                // 생성 시점 작가 표시 이름 스냅샷(users/{uid}.displayName
                                   // 조인이 아니다 — 리더는 다른 사람의 users 문서를 읽을
                                   // 권한이 없어서, 팩 문서에 직접 박아 둔다. 작가가 나중에
                                   // 프로필 이름을 바꿔도 여기는 갱신되지 않는다).
type: 'interactive' | 'linear'    // 생성 시 작가가 고르는 값. 노드(interactive)/챕터
                                   // (linear)가 하나라도 생기면 편집기가 변경을 막는다
                                   // — 두 타입은 하위 콘텐츠 구조 자체가 달라서, 도중에
                                   // 바꾸면 이미 만든 콘텐츠가 갈 곳을 잃는다.
genres: array<string>             // genres/{genreId}의 slug 참조 배열(장르 자체 데이터는
                                   // genres 컬렉션에 있고, 여기는 slug 문자열만 담는다).
description: string               // "지금 편집 중인" 값.
coverImageId: string?             // images/{imageId} 참조. "지금 편집 중인" 값.

price: int                        // 코인 단위 정가. "지금 편집 중인" 값. 기본 0(무료).
salePrice: int?                   // 할인가(코인). null이면 할인 없음. "지금 편집 중인" 값.
discountStartAt: timestamp?       // 할인 적용 기간 시작. 둘 다 null이면 salePrice가
discountEndAt: timestamp?         // 있는 한 항상 할인 적용. "지금 편집 중인" 값.

// 1단계 승인 — 연재 시작. 팩이 독자 라이브러리에 존재 자체를 드러내도 되는지
// 가르는, 한 번만 통과하면 되는 게이트. 아래 2단계 메타데이터 승인과는 완전히
// 별개다.
//
// requestSerialization()은 발행된(status == 'published') 노드가 최소 1개
// 있어야만 draft/rejected -> pending 전이를 허용한다(AdminStoryRepository의
// 앱 계층 체크 — Firestore 규칙은 "서브컬렉션에 조건을 만족하는 문서가
// 하나라도 있는지"를 표현하지 못해 규칙으로는 강제할 수 없다). 제목/장르/설명뿐인
// 빈 팩을 admin이 검토하게 하지 않으려는 의도적인 순서다 — 노드 작성·승인
// 자체는 이 팩의 serializationStatus와 무관하게 언제든 가능하다.
serializationStatus: 'draft' | 'pending' | 'approved' | 'rejected'
serializationSubmittedAt: timestamp?
serializationReviewedBy: string?     // 검토한 admin의 uid
serializationReviewedAt: timestamp?
serializationRejectionReason: string?

// 2단계 승인 — 메타데이터 수정. serializationStatus == 'approved' 이후,
// title/genres/description/coverImageId/price/salePrice/discountStartAt/
// discountEndAt/defaultBgmId를 바꿀 때마다 반복되는 게이트. 개별 노드 콘텐츠
// 승인(아래 nodes의 status/pendingAction/liveSnapshot)과는 완전히 별개의
// 흐름이다. serializationStatus가 아직 'approved'가 아닌 팩은 애초에
// pendingMetadataAction을 'edit'로 만들 수 없다(firestore.rules가 강제 —
// 연재 시작 승인을 한 번도 못 받은 draft 팩은 이 2단계 게이트 자체를 탈
// 이유가 없고, draft 필드는 saveDraftPackSettings로 승인 없이 자유롭게
// 고치면 된다).
pendingMetadataAction: 'edit' | null
liveMetadata: { title, genres, description, coverImageId, price, salePrice,
                discountStartAt, discountEndAt, defaultBgmId, defaultTtsVoiceId } | null
  // 마지막으로 승인된 메타데이터 스냅샷 — 독자 앱은 이 값을 읽는다(위 top-level
  // 필드들이 아니라). 연재 시작 승인 전까지는 null. effectivePrice(아래 참고)도
  // 오직 이 스냅샷만 읽는다 — 승인 전 draft 가격 변경은 독자에게 전혀 영향을
  // 주지 않는다.
metadataSubmittedAt: timestamp?
metadataReviewedBy: string?
metadataReviewedAt: timestamp?
metadataRejectionReason: string?

avgRating: number?                // 리뷰 평균(1~5). 리뷰가 하나도 없으면 null.
reviewCount: int                  // 기본 0.
viewCount: int                    // 기본 0. 리더가 리딩 세션을 시작할 때 +1(정확히
                                   // +1인 업데이트만 규칙이 허용). 랭킹 스냅샷의 원천.

defaultBackgroundImage: string?   // images/{imageId} 참조. 어떤 노드도 배경을
                                   // 명시적으로 안 골랐을 때의 최종 폴백
                                   // (lib/core/story/background_image_inheritance.dart).
                                   // liveMetadata 승인 게이트를 거치지 않는다 —
                                   // 순수 렌더링 기본값이라 저장 즉시 반영된다.
defaultBgmId: string?             // bgmLibrary/{bgmId} 참조. 리딩 세션 시작
                                   // 시점(첫 노드가 effects.bgm을 아예 안
                                   // 정했을 때만) 재생할 시작 BGM. ⚠️
                                   // defaultBackgroundImage와 반대로 **위
                                   // liveMetadata 승인 게이트를 그대로
                                   // 거친다** — "지금부터 뭐가 재생될지"는
                                   // 검토가 필요한 콘텐츠라는 판단(작가가 이
                                   // 값을 draft로 자유롭게 바꿔도, 독자에게
                                   // 실제로 반영되려면 승인이 필요하다). 그래서
                                   // StoryPackRepository는 이 값을 top-level이
                                   // 아니라 liveMetadata.defaultBgmId에서 읽는다.
defaultTtsVoiceId: string?        // Typecast 보이스 id(`tc_...`). 노드가
                                   // effects.tts(아래 참고)를 아예 안 정했을 때
                                   // synthesizeNodeTts가 fallback으로 쓰는 팩
                                   // 기본 내레이터 보이스. defaultBgmId와 똑같이
                                   // **liveMetadata 승인 게이트를 그대로 거친다**
                                   // — "지금부터 뭐가 재생될지"는 검토가 필요한
                                   // 콘텐츠라는 같은 판단이다(defaultBackgroundImage와는
                                   // 다르다 — 이쪽은 게이트를 안 거친다). 리더 쪽
                                   // Dart 모델에는 이 필드가 아예 없다 — 값 resolve는
                                   // 전부 서버(synthesizeNodeTts, Admin SDK로
                                   // liveMetadata를 직접 읽는다)에서만 일어나고,
                                   // 클라이언트는 packId/nodeId만 넘기면 되기
                                   // 때문이다(아래 "TTS 내레이션" 절 참고).
```

`authorId`/`authorName`/`type`/`genres`/`description`/`coverImageId`/승인 관련
필드는 다중 작가 구조로 가면서 새로 추가되는 필드다. 기존에 만들어진 스토리팩
문서(예: 좀비 이야기 팩)는 이 필드가 없으므로, 읽을 때 없음을 각각 "소유자
미지정"/""/`'interactive'`/`[]`/""/null/`'draft'`로 취급해야 하고, 실제로는 한 번
수동 백필이 필요하다(백필하지 않으면 `serializationStatus`가 `'draft'`로
읽혀 독자 라이브러리에도 계속 보이지 않는다). **이 필드 결여는 규칙에서도 실제
버그를 냈다** — `firestore.rules`의 storyPacks update 규칙이 한동안 이 필드들을
점(`.`) 표기로 비교하고 있었는데, 값이 없는 문서에서 점 표기 접근 자체가
"속성을 찾을 수 없음" 에러로 요청 전체를 permission-denied로 거부시켰다(아래
"보안 규칙" 절 참고) — 지금은 전부 `get(key, null)`로 안전하게 비교한다.

독자 라이브러리 노출 조건은 `serializationStatus == 'approved'` **그리고**
발행된(`status == 'published'`) 노드가 최소 1개 있어야 한다. `requestSerialization()`이
이미 발행된 노드를 요구하기 때문에 승인 시점엔 이 조건이 구조적으로 항상
참이지만, 나중에 그 노드가 반려/삭제되어 발행된 노드가 하나도 안 남는 엣지
케이스에 대비한 방어적 이중 체크로 유지한다. 리더 쪽 `StoryPackRepository`
(lib/features/catalog/data/story_pack_repository.dart)가 이 AND 조건을
클라이언트에서 조합한다.

### effectivePrice — 지금 실제로 적용되는 가격

`price`/`salePrice`/`discountStartAt`/`discountEndAt` 네 필드를 직접 비교하는
대신, "지금 이 순간 독자가 실제로 내야 하는 가격"은 항상 이 계산을 거친다 —
salePrice가 있고 (discountStartAt이 없거나 이미 지났고) (discountEndAt이 없거나
아직 안 지났으면) salePrice, 아니면 price. 이 계산은 세 곳에 각각 존재한다(서로
import하지 않는 별개 구현이지만 모양은 반드시 같아야 한다):

- `firestore.rules`의 `effectivePrice(packId)` 함수 — `isPackFree(packId)`가
  이 값을 쓴다(`readerOwnsPack`과 함께 리뷰/댓글 작성 자격을 가른다). **오직
  liveMetadata만 읽는다** — top-level draft 필드를 읽으면 작가가 승인 없이
  즉시 가격/무료 판정을 바꿀 수 있게 되어 버린다.
- `lib/admin/models/admin_story_pack.dart`의 `AdminStoryPack.effectivePrice` —
  admin 미리보기용. draft 필드(`price`/`salePrice`/...) 기준이라, 아직 승인 전인
  값을 보여준다는 점이 규칙 쪽과 다르다.
- `lib/features/catalog/models/story_pack.dart`의 `StoryPack.effectivePrice` —
  `StoryPackRepository`가 liveMetadata에서 읽어 채운 값 기준. `isFree`/구매(`purchasePack`
  Cloud Function)/미리보기 한도 판단이 전부 이 값을 쓴다(원래 `price`를 직접 쓰면
  할인이 무시된다).

```
avgRating: number?   // 리뷰 평균(1~5). 리뷰가 하나도 없으면 null.
reviewCount: int      // 기본 0.
```

이 둘은 클라이언트가 직접 쓰지 않는다 — `storyPacks/{packId}/reviews`(아래) 쓰기를
트리거로 하는 Cloud Function(`functions/src/index.ts`의 `onReviewWritten`)이
Admin SDK로 갱신한다. `firestore.rules`의 `storyPacks/{packId}` update 규칙
어디에도 이 두 필드를 클라이언트가 쓰도록 허용한 조항이 없다 — Admin SDK는
애초에 규칙 자체를 우회하므로 별도 예외 규칙도 필요 없다.

## storyPacks/{packId}/reviews/{uid}

```
rating: int              // 1~5.
text: string
createdAt: timestamp
updatedAt: timestamp
authorDisplayName: string
authorPhotoUrl: string?
```

문서 id가 작성자 uid다 — "이 팩에 유저 하나당 리뷰 하나"가 스키마 자체로
강제된다. 다시 쓰면(재작성) 같은 문서를 update하고, `createdAt`은 절대 안
바뀐다(규칙이 강제) — `updatedAt`만 매번 서버 타임스탬프로 갱신된다.

## storyPacks/{packId}/comments/{commentId}

```
uid: string
text: string
createdAt: timestamp
authorDisplayName: string
authorPhotoUrl: string?
isDeleted: bool             // 기본 false. 소프트 삭제 — 본인 댓글만, 이 필드만 바꿀 수 있다.
parentCommentId: string?    // null이면 최상위 댓글, 아니면 부모 댓글 id(답글 — 한 단계만).
likeCount: int               // 기본 0. 클라이언트가 직접 안 쓴다(아래 likes 참고).
```

리뷰와 달리 문서 id가 자동 생성이다(한 유저가 여러 개 남길 수 있어서) —
그래서 작성자를 알아보려면 `uid` 필드가 필요하다.

답글은 `parentCommentId`로 딱 한 단계만 중첩된다 — 답글의 답글은 UI에도
없고, `firestore.rules`의 `isValidParentComment()`가 `parentCommentId`가
가리키는 문서 자신도 `parentCommentId == null`이어야 한다고 검증해서 서버
쪽에서도 막는다. 최상위 댓글 목록은 `where('isDeleted', isEqualTo: false)
.where('parentCommentId', isEqualTo: null).orderBy('createdAt', descending:
true)`로 페이지네이션하고(복합 색인 필요, 아래 참고), 답글은 각 최상위
댓글마다 `where('parentCommentId', isEqualTo: 부모id).where('isDeleted',
isEqualTo: false).orderBy('createdAt')`로 따로 조회한다(페이지네이션 없이
한 번에, 스레드가 보통 짧아서 — `StoryPackCommentRepository.fetchReplies`).
실제 삭제나 텍스트 수정은 없다(관리자 모더레이션 UI는 이후 범위).

## storyPacks/{packId}/comments/{commentId}/likes/{uid}

```
createdAt: timestamp
```

문서 존재 = 좋아요, 부재 = 좋아요 안 함(리뷰와 같은 "문서 id = uid" upsert
패턴, 자기 좋아요 카운트를 따로 쿼리할 필요가 없다). 본인 uid 경로만
만들거나 지울 수 있다. `likeCount`(위 댓글 문서)는 이 서브컬렉션 쓰기를
트리거로 하는 Cloud Function(`functions/src/index.ts`의
`onCommentLikeWritten`, `onReviewWritten`과 완전히 같은 재집계 패턴)이
갱신한다 — 클라이언트는 매 렌더링마다 `likes`를 세지 않고, 댓글 문서의
`likeCount`만 구독한다. 내 좋아요 여부는 `likes/{내 uid}` 문서 하나의
존재 여부만 보고 판단한다(서브컬렉션 전체를 훑지 않는다).

## storyPacks/{packId}/nodes/{nodeId}

⚠️ **2025년 blocks 스키마 마이그레이션으로 필드가 완전히 바뀌었다.** 예전의
평평한 `day`/`title`/`body`/`bgImageId`/`choices`(move/battle/encounter/merchant/
item 분기) 구조는 아래 모양으로 완전히 대체됐다 — 어떤 현재 노드 문서에도 옛
필드는 존재하지 않는다. 이 필드명 불일치가 `firestore.rules`의 approveNode/
rejectNode 규칙에서 실제로 오래 방치된 버그였다(옛 필드명을 점 표기로 비교하다가
"속성을 찾을 수 없음" 에러로 모든 노드 승인이 permission-denied로 막혔다) —
아래 "보안 규칙" 절 참고.

```
order: int                        // 선형 스토리의 챕터 순서. 배경 이미지 인계
                                   // (background_image_inheritance.dart)와
                                   // 사이드바 드래그 재정렬 기준.
blocks: array<{
  type: 'paragraph',
  text: string,
  ttsVoiceId: string?,             // 블록 단위 TTS 재정의(요청 사양 Part 3,
  ttsEmotion: string?,             // 다중 화자 대사 지원) — 다섯 다 선택이고
  ttsEmotionIntensity: number?,    // 필드 단위로 개별 폴백한다: 블록 →
  ttsPitch: number?,               // effects.tts(노드 기본) → defaultTtsVoiceId/
  ttsTempo: number?,               // 중립값(팩 기본). 아래 "tts" 절의
}>                                 // "블록 단위 보이스 재정의" 참고.
                                   // 본문 문단 배열. 이번 패스는 paragraph만
                                   // 지원한다(beat/image는 다음 패스).
backgroundImage: string?          // images/{imageId} 참조. 이 노드가 명시적으로
                                   // 고른 배경. null이면 인계 체인을 따른다.
backgroundAppliesForward: bool    // 기본 true. backgroundImage가 있을 때만 의미
                                   // 있음 — false면 이 노드에만 적용되고 다음
                                   // 노드는 그 이전 값을 그대로 물려받는다.
choices: array<{ label: string, nextNodeId: string }> | null
                                   // storyPack.type == 'interactive'일 때만.
nextNodeId: string?                // storyPack.type == 'linear'일 때만.
effects: { blackout, shake, sfx, flash, haptic, bgm, tts } | 없음(전부 꺼짐/상속 기본값)
                                   // 아래 "effects" 절 참고. 필드 자체가 없는
                                   // 기존 노드도 전부 꺼진 기본값으로 읽힌다.
status: 'draft' | 'published'
pendingAction: 'create' | 'edit' | 'delete' | null
liveSnapshot: { order, blocks, backgroundImage, backgroundAppliesForward,
                choices, nextNodeId, effects } | null
rejectionReason: string?          // admin이 반려할 때 남긴 사유. 재제출하면
                                   // (requestApprovalForNode) 지워진다 —
                                   // 아래 "승인 대기함" 절 참고.

// TTS 오디오 캐시 — synthesizeNodeTts(Cloud Function, Typecast 연동, 아래
// "TTS 내레이션" 절 참고)만 채운다. liveSnapshot 안이 아니라 최상단에 바로
// 있다 — 작가가 쓴 콘텐츠가 아니라 서버가 그 콘텐츠로부터 만들어 낸 캐시
// 산출물이라 승인 흐름과 무관하다(viewCount/avgRating과 같은 대우). ⚠️
// AdminStoryNode.toFirestoreJson()은 매번 문서 전체를 .set()으로 다시 쓴다
// (병합이 아니다) — 그래서 이 두 필드는 반드시 AdminStoryNode 모델을 그대로
// 통과해서(읽을 때 그대로 들고 있다가 저장할 때 그대로 다시 써 넣는 식으로)
// 왕복해야 한다. 빠뜨리면 작가가 본문과 전혀 무관한 필드 하나만 고쳐 임시저장해도
// 이미 만들어 둔 TTS 캐시가 조용히 사라지고, 다음 리더가 방문할 때 불필요하게
// Typecast를 다시 호출하게 된다.
ttsAudioUrl: string?                        // Storage 다운로드 URL. 독자용
                                             // "공식" 캐시 — 리더는 항상 이 값만
                                             // 읽는다.
ttsAudioGeneratedForBodyHash: string?       // 이 오디오를 생성할 때 쓴 입력값
                                             // (블록별 resolve된 텍스트+보이스/
                                             // 감정/피치/템포 전체)의 해시. 이
                                             // 중 어느 블록의 설정 하나라도
                                             // 바뀌면 다른 해시가 나와서 재생성한다
                                             // — Typecast API를 매번 다시 부르지
                                             // 않기 위한 캐시 무효화 키다.

// "미리듣기" 잠정 캐시 — previewNodeTts만 채운다(요청 사양 Part 1-1). 위
// ttsAudioUrl과 똑같은 "그냥 보존만 하는" 서버 캐시 필드지만, 독자에게 보이는
// 공식 값이 아니라 저자가 편집 중에 눌러 본 미리듣기 결과일 뿐이다 — 아래
// "TTS 생성 트리거" 절 참고.
ttsPreviewAudioUrl: string?
ttsPreviewAudioGeneratedForBodyHash: string?
```

- `status`/`pendingAction`/`liveSnapshot`은 초안 → 승인 대기 → 발행(연재중)
  흐름을 나타낸다. `liveSnapshot`은 마지막으로 **승인된** 콘텐츠 스냅샷이고,
  최상단 필드(order/blocks/...)는 지금 편집 중인(승인 전일 수도 있는) 내용이다
  — 즉 문서 하나가 "지금 보이는 버전"과 "다음에 반영될 버전"을 동시에 들고 있다.
  **admin "승인 대기함"의 diff 화면(아래 절 참고)이 정확히 이 둘을
  before(liveSnapshot)/after(최상단 필드)로 비교해서 보여준다** — 새로
  계산하는 값이 아니라 이미 문서에 있는 두 스냅샷을 그대로 쓰는 것이다.
- `liveSnapshot == null`이면 한 번도 승인된 적 없는 순수 신규 노드라는 뜻이고,
  편집기는 이걸로 "신규 등록 요청"과 "수정 요청"을 구분한다.
- `rejectionReason`은 `status`/`pendingAction`/`liveSnapshot`과 같은 "검토
  메타데이터" 필드이지 콘텐츠가 아니다 — `admin`의 승인/반려 규칙이 콘텐츠
  필드(order/blocks/...)만 불변으로 잠그고 이 필드는 자유롭게 두는 것과
  같은 이유(아래 "보안 규칙" 절 참고). 작가 쪽 화면 두 곳에 그대로 노출된다:
  사이드바 노드 목록의 상태 배지("반려됨", `StatusTag`)와 노드 편집 화면
  상단 배너(`NodeEditor`, 반려 사유 원문 그대로 표시). 작가가 노드를 고쳐서
  다시 제출하면(승인 요청 재전송) 그 시점에 서버 값이 지워진다 — 재제출한
  새 버전에 옛 사유가 계속 붙어 있으면 안 되기 때문이다.
- 노드 문서 id는 `choices[].nextNodeId`/`nextNodeId`가 가리키는 대상이기도
  하다 — 편집기는 이미 발행된 적 있는 노드의 id를 그 자리에서 바꾸지 못하게
  막는다(Firestore 문서 id는 rename이 없어서, 바꾸려면 새 문서 생성 + 기존
  문서 삭제 + 그 노드를 가리키던 다른 모든 선택지 갱신이 필요한데 지금
  단계에서는 다루지 않는다).
- Dart 모델: `lib/admin/models/admin_story_node.dart`(admin, mutable 편집
  세션용)와 `lib/reader/shared/models/story_node.dart`(리더, 읽기 전용) — 문서
  모양은 같지만 서로 import하지 않는 별개 클래스다.

### effects (노드 연출 효과)

전부 프리셋 전용(자유 설정 없음)이고 기본은 꺼짐이다 — `lib/admin/models/node_effects.dart`
(admin, 재생 안 함)와 `lib/reader/shared/models/node_effects.dart`(리더, `SceneFrame`이
실제로 재생) 둘 다 같은 필드 모양의 별개 클래스다. **`bgm`/`tts`는 예외** —
재생을 트리거하는 쪽이 `SceneFrame`이 아니거나(`bgm`), 아예 리더 쪽 모델에
필드 자체가 없다(`tts`, 아래 참고).

```
blackout: { enabled: bool, durationPreset: '0.5s' | '1s' | '2s' }
shake: { enabled: bool, intensityPreset: '약하게' | '보통' | '강하게' }
sfx: { enabled: bool, sfxId: string? }        // sfxLibrary/{sfxId} 참조.
flash: { enabled: bool, colorPreset: '빨강(피격)' | '하양(섬광)' | '파랑(냉기)',
         durationPreset: '짧게' | '보통' | '길게' }
haptic: { enabled: bool, durationPreset: '짧게' | '길게' }
bgm: { bgmId: string?, silence: bool, volume: number } | null
                                                // bgmLibrary/{bgmId} 참조. 아래
                                                // "bgm — 배경음악 전환" 절 참고.
tts: { voiceId: string?, emotion: string?, emotionIntensity: number,
       pitch: number, tempo: number } | null
                                                // Typecast 내레이션 설정. 아래
                                                // "tts — Typecast 내레이션" 절 참고.
```

블랙아웃/흔들림/효과음/플래시/진동 다섯은 **본문 타이핑이 끝나는 시점**에
`SceneFrame`이 한 번에 트리거한다(모두 "연출 효과"가 자유 설정 없이 프리셋만
받는 이유는 CLAUDE.md "Node content schema" 참고). `bgm`은 이 다섯과 완전히
다른 모양과 트리거 지점을 갖는다:

- **다른 다섯과 달리 `enabled` 불리언이 없다.** `bgm` 필드 자체가 있는지
  없는지가 곧 의미다 — `null`(필드 없음)이면 **상속**(이전 노드에서 재생
  중이던 BGM이 그대로 이어진다, 아무 것도 안 바뀜), 있으면 그 안의
  `bgmId`/`silence`가 지시하는 대로 트랙 전환/무음 전환을 한다.
- **트리거 지점이 `SceneFrame`이 아니라 리더 페이지(InteractiveReader/
  LinearReader)다.** 다섯 효과는 `SceneFrame`이 타이핑 완료 시점에 트리거하는데,
  `SceneFrame`은 노드가 바뀔 때마다 새 인스턴스로 다시 만들어지는 위젯이라
  "지금 재생 중인 BGM이 뭔지" 같은 세션 상태를 이어서 들고 있을 수 없다. 그래서
  BGM 세션 상태(`BgmSessionController`, `lib/reader/shared/bgm_session_controller.dart`)는
  리더 페이지가 노드를 바꾸는 시점(최초 진입/선택지 선택/다음 페이지/재시작)에
  같이 갱신된다 — "타이핑이 끝난 뒤"가 아니라 "그 노드가 화면에 나타나는
  시점"이라는 뜻이다. BGM은 다섯 효과처럼 서사의 클라이맥스에 맞춰 터지는
  연출이 아니라 장면 전체에 깔리는 배경 음향에 더 가깝다는 판단.
- 실제 재생은 `AudioService`(`lib/core/audio/audio_service.dart`)가 `just_audio`
  기반 크로스페이드 엔진으로 한다(아래 "bgm — 배경음악 전환" 절 참고).

### bgm — 배경음악 전환 (상속/트랙 선택/무음 전환)

`effects.bgm`은 세 가지 상태 중 하나를 표현한다:

1. **상속(`bgm` 필드 없음/`null`)** — 이전 노드에서 재생 중이던 BGM이 그대로
   이어진다. 대부분의 노드는 BGM을 안 건드리므로 이게 사실상 기본값이다.
2. **트랙 전환(`{ bgmId: '<id>', silence: false, volume: 0.0~1.0 }`)** —
   지금 재생 중인 트랙에서 `bgmId`가 가리키는 트랙으로 크로스페이드한다(1초,
   dual-player 볼륨 페이드 — 한쪽 볼륨을 올리는 동시에 다른 쪽을 내린다,
   `AudioService.crossfadeToBgm`). **`volume`은 "완전히 페이드인된" 상태의
   목표 볼륨이다 — 항상 100%가 아니라 이 값까지만 올라간다**(기본 1.0). 대사가
   많은 장면에서 같은 트랙을 계속 쓰되 볼륨만 낮추는 용도 — 조용한 버전을
   따로 마스터링해 별도 파일로 올릴 필요가 없다. `bgmId`가 없거나
   `silence: true`일 때는 `volume`이 의미가 없다(UI에도 그때는 슬라이더
   자체가 안 보인다). ⚠️ 이 `volume`은 작성자가 정하는 값일 뿐이고, 리더
   본인이 설정 패널에서 고르는 `users/{uid}/readerPrefs/settings.bgmMasterVolume`
   (아래 참고)과 곱해진 값이 실제 재생 볼륨이다 — 어느 한쪽이 다른 쪽을
   덮어쓰지 않는다.
3. **무음 전환(`{ bgmId: null, silence: true }`)** — `bgmId`와 무관하게 지금
   재생 중인 BGM을 1초에 걸쳐 무음으로 페이드아웃한다(`AudioService.fadeOutBgm`).
   기존 블랙아웃/플래시 프리셋처럼 노드마다 고를 수 있는 페이드 지속시간
   프리셋은 없다 — 요청 사양에도 없어서 고정 1초를 썼다(짧고 일관된 기본값).

**같은 트랙이 이어지는 채로 `volume`만 바뀐 경우**(다음 노드가 같은 `bgmId`를
그대로 쓰면서 `volume`만 다르게 지정)는 "바뀌지 않았다"로 취급하지
않는다 — 트랙을 다시 크로스페이드로 걸지 않고(`crossfadeToBgm`은 URL이
같으면 아무 것도 안 하므로 이 경로로는 못 잡는다), `AudioService.
adjustBgmVolume`으로 짧게(0.4초) 볼륨만 새 목표치로 전환한다
(`BgmSessionController.visitNode`가 "트랙 id는 같은데 volume만 다르다"를
감지해서 이 메서드를 부른다). 승인 diff 쪽에서도 이 경우를 "변경 없음"으로
누락하지 않는다 — `NodeDiff.effectsChanged`가 `effects` 전체를 구조적으로
비교하므로, `bgmId`가 같고 `volume`만 다른 것도 다른 map으로 인식돼 자동으로
"변경됨"으로 잡힌다("작가 쪽 — 노드별 저장은 그대로, 제출은 일괄로" 절의
"버그였다가 고침 (3)" 참고 — 하위 필드를 나열하지 않는 통째 비교라 이런
조합도 별도 처리 없이 저절로 커버된다).

`storyPacks.defaultBgmId`는 **리딩 세션이 시작될 때(팩을 열어 첫 노드를
보여주는 순간), 그 첫 노드의 `effects.bgm`이 상속(위 1번)일 때만** 폴백으로
쓰인다 — 노드가 BGM을 안 정했다고 매번 다시 적용되는 게 아니라 세션당 딱
한 번만 관여한다(`BgmSessionController.visitNode`의 `isSessionStart` 가드).
그 다음 노드부터 상속이면 그냥 지금 재생 중인 트랙이 계속된다. `defaultBgmId`
자체엔 노드별 `volume` 개념이 없어서 항상 100%로 시작한다.

작가 쪽 UI(`NodeEffectsEditor`의 "배경음악" 행)는 세 상태를 "이전과
동일(기본값)"/"트랙 선택"/"무음으로 전환" 3지선다로 보여준다 — 다른 다섯
효과의 체크박스+프리셋 드롭다운과 다른 모양이지만, 표현하는 값 자체(위 세
JSON 모양)는 정확히 대응한다. 볼륨 슬라이더(0%~100%)는 "트랙 선택" 상태일
때만 나타난다.

**폐기된 예전 설계**: 리더 쪽 `StoryNode`에 한때 `bgmOverride`(`trackId`/
`fadeInMs`/`loop`)라는 필드가, `StoryPack`에 `ambientBgm`이라는 필드가 있었다
— 둘 다 파싱 코드만 있고 admin 쪽 쓰기 경로도, 실제 재생 코드도 전혀 없던
죽은 스캐폴딩이었다(이번 BGM 기능 구현 전 조사에서 발견, 완전히 삭제했다).
지금의 `effects.bgm`/`storyPacks.defaultBgmId`가 그 자리를 대체한다 — 옛
필드명을 찾아도 코드베이스 어디에도 없다.

### tts — Typecast 내레이션

`bgm`과 마찬가지로 재생 트리거 지점이 남다르지만(아래 참고), 그 이전에
**작동 방식 자체가 다른 다섯 효과와 근본적으로 다르다** — 나머지는 전부
클라이언트(`SceneFrame`)가 즉석에서 재생하는 연출이지만, TTS 오디오는 Typecast
API를 부른 결과물이라 **서버(Cloud Functions)가 미리 만들어 Storage에 캐시해
둔 파일**을 리더가 재생한다 — 주로 노드가 승인되는 시점에(`onNodeApprovedGenerateTts`),
`synthesizeNodeTts`는 그 캐시가 아직 없을 때만 타는 폴백이다(아래 "TTS 생성
트리거" 절 참고). Typecast API 키
(`TYPECAST_API_KEY`)는 Functions 시크릿에만 있고 클라이언트 Dart 코드 어디에도
없다 — 이 API를 부르는 코드는 오직 `functions/src/index.ts`뿐이다.

```
effects.tts: {
  voiceId: string?,          // Typecast 보이스 id(tc_...). null이면 이 노드는
                              // 보이스를 재정의하지 않는다 — storyPacks.
                              // defaultTtsVoiceId로 fallback.
  emotion: string?,          // Typecast 감정 프리셋 7종 중 하나(ssfm-v30 기준
                              // EmotionEnum과 대조 확인한 실제 값:
                              // normal/happy/sad/angry/whisper/toneup/tonedown).
                              // null이면 Typecast의 Smart Emotion(본문을 보고
                              // 자동으로 감정을 판단)에 맡긴다 — "감정을 안
                              // 골랐다"가 곧 "자동"이라는 뜻이라, effects의
                              // 다른 다섯처럼 enabled 플래그가 따로 없다.
  emotionIntensity: number,  // 0.0~2.0, 기본 1.0. emotion이 null이면(Smart
                              // Emotion) 의미 없다 — UI에도 그때는 슬라이더가
                              // 안 보인다.
  pitch: number,              // -12~12(반음 단위), 기본 0.
  tempo: number                // 0.5~2.0, 기본 1.0.
} | null
```

`effects.tts == null`은 **"이 노드는 보이스/감정/피치/템포를 전혀 재정의하지
않는다"**는 뜻이다 — `bgm`의 `null`(= 상속, 이전 노드의 재생 상태를 그대로
이어받음)과 겉보기엔 비슷해 보이지만 의미가 다르다. **`tts`에는 상속 개념
자체가 없다** — TTS 내레이션은 리딩 세션을 가로질러 이어지는 재생 상태가
아니라 노드 하나마다 완전히 독립적으로 생성되는 오디오 파일이기 때문이다
(`bgm`처럼 "지금 재생 중이던 게 계속됨"이라고 할 대상 자체가 없다). 그래서
`null`은 그냥 "보이스는 `storyPacks.defaultTtsVoiceId`, 감정은 Smart Emotion,
피치/템포는 중립값(0/1.0)을 그대로 쓴다"는 뜻일 뿐이다.

#### 블록 단위 보이스 재정의 (다중 화자 대사, interactive 팩)

`effects.tts`는 노드 전체의 기본값일 뿐이고, `blocks[].ttsVoiceId`/`ttsEmotion`/
`ttsEmotionIntensity`/`ttsPitch`/`ttsTempo`(위 "storyPacks/{packId}/nodes/
{nodeId}" 절의 `blocks` 필드 모양 참고)로 문단 하나하나를 다시 재정의할 수
있다 — 한 노드 안에서 내레이션 목소리와 캐릭터 A/B의 대사를 서로 다른
보이스로 읽게 하려는 용도다(요청 사양 Part 3). 해석 순서는 **필드 하나하나
단위로 개별 폴백**한다: 블록의 값 → 노드 `effects.tts`의 같은 필드 → (voiceId만)
`storyPacks.defaultTtsVoiceId` / (나머지는) 중립값. 예를 들어 블록이
`ttsVoiceId`만 재정의하고 `ttsEmotion`은 `null`로 뒀으면, 감정은 노드
`effects.tts.emotion`을 그대로 물려받는다 — "블록에 뭐라도 설정하면 전부
블록 값을 쓴다"가 아니다. 다섯 필드 전부 `null`/없음인 블록(공통 케이스,
저자가 손대지 않은 대부분의 문단)은 그냥 노드 기본값을 그대로 물려받는다 —
이게 항상 저자 추가 작업 없이 성립하는 기본 상태다. admin UI는 interactive
팩에서만 이 컨트롤을 보여준다(`NodeBodyBlocksEditor`의 `showTtsOverride`,
`lib/admin/widgets/node_body_blocks_editor.dart`) — linear 팩은 이 복잡도를
볼 필요가 없다는 판단일 뿐, 데이터 모델/생성 로직 자체는 팩 타입과 무관하게
항상 블록 단위로 동작한다.

**세그먼트 병합 + 오디오 이어붙이기** — 리더가 재생하는 파일은 노드 하나당
여전히 하나뿐이다(Part 1의 캐싱/Part 2의 이어재생 구조를 그대로 유지하기
위해서). 여러 보이스가 섞인 노드도 서버가 내부적으로 하나로 합친다
(`functions/src/index.ts`의 `groupIntoSegments`/`synthesizeNodeAudio`):
1. 블록을 순서대로 훑으며, **연속된 블록 중 보이스/감정/강도/피치/템포가
   완전히 같은 것들을 하나의 세그먼트**로 묶는다(= Typecast 호출 한 번) —
   화자가 안 바뀌는 구간을 굳이 여러 번 나눠 부르지 않기 위해서다. 설정이
   하나라도 다르면 새 세그먼트로 끊는다.
2. 세그먼트가 하나뿐이면(다중 보이스를 안 쓰는 절대다수의 노드) 기존 그대로
   `mp3` 하나만 요청하고 그대로 업로드한다 — 파일이 작고 검증된 경로라 손대지
   않았다.
3. 세그먼트가 둘 이상이면 각 세그먼트를 **wav**(Typecast 문서 기준 16-bit PCM
   mono 44100Hz 고정 포맷)로 받아, 각 파일의 PCM 데이터만 뽑아 순서대로 이어
   붙이고 새 wav 헤더 하나로 감싼다(`concatenateWavSegments`) — mp3 프레임을
   그냥 이어 붙이면 디코더에 따라 끊김/잡음이 날 수 있어 신뢰할 수 없고,
   ffmpeg 같은 네이티브 의존성 없이 Cloud Functions 안에서 안전하게 이어
   붙일 수 있는 포맷이 PCM wav뿐이라 이 경우에만 wav를 쓴다. Storage 확장자도
   그에 맞춰 `.mp3`/`.wav`로 갈린다(`admin/story_tts/{packId}/{nodeId}.mp3`
   또는 `.wav`) — 둘 다 같은 `ttsAudioUrl` 필드에 URL로만 남으므로 리더 쪽은
   차이를 몰라도 된다.
4. **캐시 해시는 세그먼트로 묶기 전, 블록 단위 그대로** 계산한다
   (`hashTtsInput`) — 세그먼트 묶는 방식이 나중에 바뀌어도 해시 안정성에
   영향 없게 하려는 목적이자, 블록 하나의 설정만 바뀌어도 정확히 캐시가
   무효화되게 하기 위해서다.

#### TTS 생성 트리거 — 미리듣기 / 승인 시점 / 리더 방문 시 폴백 (요청 사양 Part 1)

TTS 오디오를 만드는 지점이 세 곳이다 — 목적에 따라 어떤 콘텐츠를 읽는지,
어느 캐시 필드에 쓰는지가 다르다. 셋 다 같은 캐싱/생성 핵심 로직
(`synthesizeOrReuseTts`/`synthesizeNodeAudio`)을 공유한다:

1. **`previewNodeTts({ packId, nodeId, blocks, effectsTts, defaultTtsVoiceId })`**
   (callable, author/admin) — 노드 편집기의 "미리듣기" 버튼(`_TtsPreviewButton`,
   `lib/admin/widgets/node_effects_editor.dart`)이 부른다. `synthesizeNodeTts`와
   달리 **Firestore의 liveSnapshot을 읽지 않는다** — 저자가 지금 타이핑 중인
   초안은 임시저장 전까지 Firestore에 아예 없기 때문에(세션 캐시,
   `NodeEditSessionCache`, 메모리에만 있음), 클라이언트가 현재 화면의 blocks/
   effects.tts/팩 기본 보이스를 요청 본문에 직접 실어 보낸다. 결과는
   `ttsAudioUrl`이 아니라 `ttsPreviewAudioUrl`/`ttsPreviewAudioGeneratedForBodyHash`
   에 저장한다(Storage 경로도 `admin/story_tts_preview/{packId}/{nodeId}.*`로
   따로 둔다) — "잠정적" 캐시라는 뜻이고, 몇 번을 다시 눌러도(설정을 안
   바꿨으면) 캐시된 파일을 그대로 재생한다.
2. **`onNodeApprovedGenerateTts`** — `storyPacks/{packId}/nodes/{nodeId}`
   문서 변경 트리거(`onDocumentWritten`). 승인(`approveNode`,
   `lib/admin/data/admin_story_repository.dart`)은 admin 앱이 Firestore에
   직접 `.update()`하는 클라이언트 쓰기라 Cloud Function 훅으로 가로챌 수
   없다 — 그래서 그 쓰기가 만든 결과(`status`가 `'published'`로 바뀌거나,
   이미 published인 노드의 `liveSnapshot`이 바뀜)를 문서 트리거로 감지한다.
   감지되면 그 시점 `liveSnapshot`으로 해시를 계산해서: (a) 이미 `ttsAudioUrl`
   해시가 일치하면 아무 것도 안 하고, (b) `ttsPreviewAudioGeneratedForBodyHash`
   가 일치하면(= 저자가 마지막으로 미리들은 내용이 그대로 승인됐다)
   Typecast를 다시 부르지 않고 그 URL을 그대로 `ttsAudioUrl`로 승격만 하고,
   (c) 그것도 아니면 새로 생성한다. `before`/`after`의 `status`/`liveSnapshot`이
   둘 다 같은 이벤트(= 이 트리거 자신이 방금 `ttsAudioUrl`만 갱신한 두 번째
   이벤트)는 건너뛴다 — 안 그러면 자기 쓰기가 자기를 다시 불러 무한 루프가
   된다. 본문이 비었거나 보이스를 못 찾으면 승인 자체는 막지 않고 조용히
   건너뛴다(TTS는 부가 기능이라 이것 때문에 콘텐츠 승인이 막히면 안 된다).
   Typecast 호출이 실패해도 마찬가지로 조용히 넘어간다 — 아래 3번 폴백이
   있다.
3. **`synthesizeNodeTts({ packId, nodeId })`**(callable, 인증 필요) — 리더가
   TTS 재생 버튼을 누를 때마다(`NodeTtsPlaybackController.playSequence`,
   `lib/reader/shared/node_tts_playback_controller.dart`) 부른다. 이제는
   **주 생성 경로가 아니라 폴백**이다(요청 사양: "keep generation-on-demand
   as a fallback only") — 2번 덕분에 노드가 승인되는 순간 이미 캐시가
   준비돼 있는 게 정상 경로라, 리더는 거의 항상 즉시 캐시 히트를 받는다.
   그래도 이 함수는 그대로 남아 있다 — 2번이 실패했거나(예: Typecast
   일시 장애), 이 기능이 추가되기 전에 이미 승인됐던 옛 노드처럼 캐시가
   없는 경우를 위해서다. 동작은 그대로다: `storyPacks/{packId}`와
   `storyPacks/{packId}/nodes/{nodeId}`를 Admin SDK로 읽고(**항상
   `liveSnapshot`만**, 리더가 실제로 보는 건 마지막 승인 버전이므로), 블록별로
   보이스/감정/피치/템포를 확정하고, 해시가 `ttsAudioGeneratedForBodyHash`와
   같으면 캐시 히트로 즉시 반환, 다르면 새로 생성해 `ttsAudioUrl`/해시를
   갱신한다. 두 경로 모두 `{ audioUrl, cached: bool }`을 돌려준다.

세 경로 모두 Storage 업로드는 `uploadAndGetDownloadUrl` 하나를 공유한다 —
Admin SDK엔 클라이언트 SDK의 `getDownloadURL()` 같은 헬퍼가 없어서,
`firebaseStorageDownloadTokens` 메타데이터를 직접 세팅해 클라이언트 SDK와
같은 모양의 다운로드 URL을 수동 구성한다.

✅ **Typecast 공식 문서(https://typecast.ai/docs/api-reference/text-to-speech/
text-to-speech, https://typecast.ai/docs/api-reference/voices/list-voices)와
대조 확인 완료** — 처음엔 문서를 못 본 채 일반적인 REST TTS API 관례로 최선의
추측만 해 둔 상태였는데, 대조 결과 실제로 다음 세 가지가 틀려 있었다:
- 보이스 목록 엔드포인트는 `GET /v1/voices`가 아니라 `GET /v2/voices`다(TTS
  생성 엔드포인트 `POST /v1/text-to-speech`와 버전이 다르다).
- `emotion_preset`을 쓰려면 `prompt.emotion_type`을 명시적으로 `"preset"`으로
  (Smart Emotion은 `"smart"`로) 지정해야 한다 — discriminator 필드라 생략했을
  때의 동작이 스펙에 정의돼 있지 않다. `synthesizeNodeTts`는 이제 항상 둘 중
  하나를 명시한다.
- `whisper`/`toneup`/`tonedown` 프리셋은 `ssfm-v21`엔 없고 `ssfm-v30`에서만
  지원된다 — `model`을 `ssfm-v30`으로 바꿨다. 애초에 감정 프리셋 값 자체도
  틀려 있었다(`surprise`/`fear`는 Typecast에 존재하지 않는 값이었다) — 위
  `emotion` 필드 설명의 실제 7종 목록으로 바로잡았다.

`functions/src/index.ts`의 `synthesizeNodeTts` 절 상단 주석에 같은 내용이
더 자세히 있다. 나머지(엔드포인트 URL 도메인, `X-API-KEY` 헤더, 요청 바디의
`voice_id`/`text`/`output.audio_pitch`/`output.audio_tempo`/`output.audio_format`
필드명, 응답이 오디오 바이트를 그대로 돌려준다는 점)는 원래 작성해 둔 그대로
맞았다.

**리더 쪽 Dart 모델에는 `effects.tts`/`defaultTtsVoiceId`가 아예 없다** — 보이스/
감정/피치/템포 resolve가 전부 `synthesizeNodeTts` 안에서(Admin SDK로
`liveSnapshot`/`liveMetadata`를 직접 읽어) 서버 쪽에서만 일어나기 때문에,
클라이언트는 `packId`/`nodeId` 두 값만 넘기면 된다(`NodeTtsRepository.synthesize`,
`lib/reader/shared/data/node_tts_repository.dart`). BGM/SFX처럼 리더가 직접
`sfxId`/`bgmId` → URL을 조인해서 resolve하는 것과 다른 지점이다.

**보이스 목록 캐시(`ttsVoiceCache/typecast`)** — Typecast의 `/v1/voices`
목록 조회는 자주 바뀌지 않는데도 admin 화면(팩 설정의 "기본 내레이터 보이스"
피커, 노드 편집기의 보이스 재정의 피커)을 열 때마다 부르면 낭비라, 문서
하나(`{ voices: [{id, name}], fetchedAt }`)에 캐시해 둔다.
`refreshTypecastVoiceCacheScheduled`(매일 KST 03:00 예약 실행)가 자동으로,
`refreshTypecastVoices`(callable, author/admin 누구나 — 저비용 메타데이터
조회라 admin 전용으로 좁힐 필요가 없었다)가 admin UI의 새로고침 버튼으로
수동으로 갱신한다. 둘 다 Admin SDK로 쓰므로 클라이언트는 이 문서를 절대
직접 못 쓴다(아래 "보안 규칙" 절 참고) — `AdminTtsVoiceRepository.watchVoices()`
가 읽기 전용으로 구독만 한다.

**재생(리더 쪽)** — `NodeTtsPlaybackController`(`lib/reader/shared/
node_tts_playback_controller.dart`)가 `just_audio`로 재생한다. `AudioService`
(BGM 세션 전역 싱글턴)와 달리 이 컨트롤러는 `SceneFrame` State 하나의 생애를
그대로 따라간다 — `SceneFrame`은 노드가 바뀔 때마다 새 key로 다시 만들어지는
위젯이라(클래스 doc 참고) 내레이션도 자연스럽게 노드마다 처음부터 다시
시작되고, 세션을 이어갈 필요가 없다. 본문 타이핑 애니메이션과 재생 위치를
동기화하는 건 나중 개선 과제로 남겨 뒀다. 설정 패널의 TTS 토글(위치는 예전
기기 TTS 토글과 동일 — "TTS" 아이콘 버튼)이 그대로 이 컨트롤러의 재생/
일시정지를 부른다. **예전 `flutter_tts`/`TtsController`(기기 내장 음성
합성)는 완전히 삭제됐다** — 이 기능을 대체한 것이지 나란히 존재하는 별도
옵션이 아니다.

`NodeTtsPlaybackController.playSequence({ packId, nodeIds })`는 노드 id
하나가 아니라 **순서 있는 목록**을 받는다 — 보통은 원소 하나짜리 목록이지만,
아래 "자동 이어재생" 절의 두 쪽 펼침 케이스에서는 두 개짜리 목록이 된다.
목록을 순서대로 이어 튼다(세그먼트 하나가 끝나면 화면 전환 없이 바로 다음
세그먼트로) — 목록 전체가 자연 재생 완료됐을 때만
`allCompletedStream`이 울린다.

⚠️ **`just_audio`의 `AudioPlayer.play()`가 돌려주는 `Future`는 "재생이
시작될 때"가 아니라 "재생이 끝나거나 일시정지/정지될 때" 완료된다**
(패키지 문서: "completes when the playback completes or is paused or
stopped"). 이걸 `await`하면 재생되는 내내 로딩 상태가 안 풀려서 (a) 설정
패널의 TTS 라벨이 "TTS 준비 중"에 멈춰 있고 (b) 탭 핸들러의 "로딩 중엔
무시" 가드 때문에 재생 중엔 아예 끌 수도 없게 되는 실제 버그가 났다 — 지금
은 `_player.play()`를 어디서도 `await`하지 않는다(fire-and-forget, 상태
갱신은 전부 `playerStateStream` 리스너가 한다). `NodeTtsPlaybackController`
안에 이 함수를 새로 부르는 코드를 추가할 때는 이 규칙을 반드시 지킬 것.

#### 자동 이어재생 ("오디오북" 경험, 요청 사양 Part 2)

내레이션이 끝까지 재생되면(사용자가 일시정지한 게 아니라) 자동으로 다음
노드로 넘어가서 이어 낭독한다 — linear/interactive 팩 둘 다 같은 방식으로
동작한다. 담당 코드는 세 곳으로 나뉜다:

- **`ReaderSessionController`**(`lib/reader/shared/reader_session_controller.dart`,
  예전 `BgmSessionController`를 여기로 확장·개명했다) — BGM 세션 상태(예전
  그대로)에 더해 "지금 화면의 내레이션이 끝나면 자동으로 넘어갈 다음 노드
  id"(`setAutoContinueTarget`)와 "자동 이어재생이 켜져 있는지"
  (`setAutoContinueEnabled`, readerPrefs 구독)를 같이 들고 있다. 둘 다 같은
  "노드가 바뀔 때마다 갱신되는 세션 상태"라는 성격이라 한 컨트롤러로 묶었다
  — 리더 페이지(`InteractiveReader`/`LinearReader`)가 노드를 바꾸는 지점마다
  이 컨트롤러 하나만 갱신하면 BGM과 자동 이어재생 둘 다 일관되게 따라온다.
- **`SceneFrame`**은 `narrationNodeIds`(재생할 노드 id 목록, 스프레드가 아니면
  원소 하나)와 `onNarrationCompleted` 콜백을 받는다 — 목록 전체가 자연
  재생 완료되면 그 콜백을 부른다. `autoPlayNarration: true`로 만들어지면
  화면에 들어오자마자(사용자가 TTS 버튼을 다시 안 눌러도) 내레이션을 자동
  재생한다.
- **리더 페이지**가 나머지를 조율한다: 노드마다 "자동으로 넘어갈 다음 노드가
  뭔지"(다음 항목 참고)를 계산해 `setAutoContinueTarget`으로 알려주고,
  `SceneFrame.onNarrationCompleted`가 불리면
  `ReaderSessionController.handleNarrationCompleted(onAdvance)`를 호출한다 —
  자동 이어재생이 켜져 있고 대상이 있으면 `onAdvance`가 불린다. 이때 리더
  페이지는 **"다음" 버튼/선택지 탭과 정확히 같은 기존 메서드**(`_goToNext`/
  `_handleChoice`)를 그대로 재사용해서 넘어간다 — 유료 미리보기 제한 체크
  같은 기존 부수효과가 자동 이어재생에도 똑같이 적용된다.

  다음 노드의 `SceneFrame.autoPlayNarration`은 **`ReaderSessionController.
  ttsUserEnabled`를 그대로 읽는다** — "사용자가 TTS를 직접 켰는지"를 담는
  세션 상태 하나다(`setTtsUserEnabled`, `SceneFrame.onNarrationUserToggled`가
  사용자가 TTS 버튼을 직접 눌러 켜거나 끌 때만 알려준다). ⚠️ **처음엔
  이 값을 세션 컨트롤러가 아니라 "자동 이어재생으로 넘어갈 때만 한 번 세우고
  바로 소비하는" 1회성 플래그(`_autoPlayNextNarration`, 리더 State 필드)로
  구현했었다** — 그러다 보니 자동 이어재생이 아니라 **선택지를 직접
  탭하거나 "다음" 버튼을 누른 경우**(진짜 분기점 등)엔 그 플래그가 세워질
  일이 없어서, TTS를 듣고 있다가 선택지를 고르면 다음 노드에서 소리가
  꺼져 버리는 실제 버그가 났다(BGM이 SceneFrame 재생성 때마다 상태를 잃는
  것과 같은 부류로 보였지만, 실제 원인은 "세션 상태 자체가 없어서"가 아니라
  "그 세션 상태를 갱신하는 경로가 자동 이어재생 하나뿐이었어서"였다). 지금은
  `_buildBody`가 노드를 어떻게 바꾸든(자동 이어재생/선택지 직접 탭/"다음"
  버튼) 매번 `ReaderSessionController.ttsUserEnabled`를 그대로 읽으므로,
  전환 경로와 무관하게 항상 같은 값을 본다 — 리더가 맨 처음 한 번만 TTS를
  눌러 시작하면, 그 뒤로는 어떻게 다음 노드로 가든 계속 자동으로 들린다는
  뜻이다.

**"자동으로 넘어갈 다음 노드"를 정하는 규칙**(요청 사양 Part 2):
- **linear 팩, 한 쪽 보기**: `node.nextNodeId`. 없으면(마지막 페이지)
  자동으로 넘어갈 곳 없음.
- **interactive 팩**: 그 노드의 `choices`가 **정확히 하나**일 때만 그
  선택지의 `nextNodeId`. 선택지가 없으면(엔딩) 넘어갈 곳이 없고, **둘
  이상이면 진짜 분기점이라 자동으로 넘기지 않고 멈춰서 독자가 직접
  고르길 기다린다**(요청 사양: "playback naturally pauses after finishing
  that node's narration and waits for the reader to pick"). 선택지 버튼
  자체는 선택지 개수와 무관하게 항상 그대로 보인다 — 자동 이어재생은
  추가 트리거일 뿐, 수동 진행 경로를 없애지 않는다.
- **linear 팩, 두 쪽 펼침**: `SceneFrame`에 왼쪽/오른쪽 두 노드를
  `narrationNodeIds`로 같이 넘긴다 — 왼쪽 쪽 내레이션이 끝나면 화면 전환
  없이 곧바로 오른쪽 쪽 내레이션을 잇고("요청 사양: narration should read
  through BOTH visible pages in sequence before advancing"), **오른쪽
  쪽까지 다 끝나야만** `onNarrationCompleted`가 불려서 "다음" 버튼과 같은
  대상(오른쪽 페이지의 `nextNodeId`, 두 쪽을 건너뛴 다음 스프레드)으로
  자동으로 넘어간다. 두 쪽 펼침 여부(`canSpread`) 자체는 화면 폭
  (`MediaQuery`)에 달려 있어서, 이 판단은 `_buildBody` 한 곳에서만 하고
  자동 이어재생 대상 계산도 그 판단을 그대로 재사용한다 — 판단 로직을
  두 곳에 따로 두면 어긋날 수 있어서다.

노드에 TTS가 아예 설정/캐시돼 있지 않으면 애초에 내레이션이 재생되지 않으니
`onNarrationCompleted`도 안 불리고, 자동 이어재생은 조용히 트리거되지 않는다
(요청 사양: "If a node has no TTS configured/cached, auto-advance simply
doesn't trigger from that node — silent, no error"). 노드/팩 타입에 따라
이 동작 자체를 따로 분기하지 않는다 — 위 세 규칙 중 어디에도 안 걸리면
그냥 대상이 없을 뿐, 특정 노드/팩 타입을 특별 취급하는 코드는 없다.

**끄는 방법** — 설정(Settings) 패널의 "TTS 자동 이어재생" 토글
(`readerPrefs.settings.ttsAutoContinueEnabled`, 아래 절 참고) — 기본 켜짐
(요청 사양: "auto-continue should be the default behavior but not forced"),
배경음악 볼륨/글꼴/글자 크기/글자 색/글자 애니메이션과 같은 패널의 같은
리스트 스타일로 있다(별도 인라인 토글이 아니다).

`storyPacks.defaultTtsVoiceId`가 liveMetadata 승인 게이트를 거치는 이유,
`effects` 필드 전체가 `NodeDiff.effectsChanged`(구조적 whole-map 비교)로
이미 커버되어 `tts`만을 위한 별도 diff 로직이 필요 없는 이유는 각각 위
"defaultBgmId"/"같은 트랙이 이어지는 채로 volume만 바뀐 경우" 설명과 정확히
같은 논리다.

## images/{imageId}

```
name: string          // 원본 파일명
url: string            // Firebase Storage 다운로드 URL
```

실제 이미지 파일은 Firebase Storage의 `admin/story_images/{imageId}_{원본파일명}`에
올라간다. 이 문서는 그 파일을 가리키는 색인일 뿐이다 — 노드 배경/선택지 이미지를
고를 때 이 컬렉션에서 목록을 불러온다.

## sfxLibrary/{sfxId}

```
name: string             // 원본 파일명
category: string          // '문' | '발소리' | '비명' | '심장박동' | '기타' (AdminSfxCategory)
storageUrl: string        // Firebase Storage 다운로드 URL
uploadedBy: string?       // 업로드한 유저의 uid
createdAt: timestamp
```

images/{imageId}와 같은 색인 패턴이다 — 실제 오디오 파일은 Firebase Storage의
`admin/story_sfx/{sfxId}.mp3`에 올라간다(images와 달리 원본 파일명을 경로에
이어붙이지 않고 고정 확장자를 쓴다). 노드의 연출 효과(`effects.sfx`,
node_effects.dart)가 `sfxId`로 이 컬렉션을 참조한다 — 프리셋 고정값이 아니라
작가가 직접 올린 파일을 가리킨다. 리더 쪽 StoryReaderRepository가 이 컬렉션의
`storageUrl`을 조인해 `ResolvedStoryNode.sfxUrl`로 넘겨준다(실제 재생은 아직
SceneFrame에 붙어 있지 않다 — "Reader system" 섹션 참고).

## bgmLibrary/{bgmId}

```
name: string             // 원본 파일명
storageUrl: string        // Firebase Storage 다운로드 URL
uploadedBy: string?       // 업로드한 유저의 uid
createdAt: timestamp
```

sfxLibrary와 거의 같은 색인 패턴이다(images/sfxLibrary와 같은 이유로 팩/작가
구분 없이 전체가 공유한다) — **`category`가 없다는 점만 다르다.** 효과음은
"문/발소리/비명/심장박동/기타"처럼 상황별로 골라 쓰는 라이브러리라 분류가
필요했지만, BGM은 트랙 수 자체가 적어 이름만으로 충분하다는 판단(요청
사양에도 category가 없다). 실제 오디오 파일은 Firebase Storage의
`admin/story_bgm/{bgmId}.mp3`에 올라간다(sfxLibrary와 같은 고정 확장자
패턴). 노드의 연출 효과(`effects.bgm`, 위 "bgm — 배경음악 전환" 절)와
`storyPacks.defaultBgmId`가 `bgmId`로 이 컬렉션을 참조한다. 리더 쪽
`StoryReaderRepository`가 이 컬렉션의 `storageUrl`을 조인해
`ResolvedStoryNode.bgmUrl`/반환값의 `defaultBgmUrl`로 넘겨준다 — sfxLibrary
조인과 정확히 같은 패턴(`_fetchSfxUrls`/`_fetchBgmUrls`).

"작가 도구"의 "배경음악 라이브러리" 탭(`BgmLibraryTab`,
`lib/admin/pages/bgm_library_tab.dart`)이 업로드/삭제를 관리한다 — 효과음
라이브러리 탭과 같은 화면 구조(카테고리 필터 칩만 없다).

## writerNotices/{noticeId}

```
packId: string          // storyPacks/{packId} 참조
title: string
body: string
date: string             // yyyy-MM-dd
```

작가가 자기 스토리팩에 올리는 변경사항 공지 — "작가 도구"의
`NoticesTab`(`lib/admin/pages/notices_tab.dart`)이 관리한다. ⚠️ 아래
`notices`(앱 전체 공지, 하단 탭 "공지사항")와 이름이 비슷해서 헷갈리기
쉽지만 **완전히 다른 컬렉션/기능**이다 — 이건 팩 하나에 딸린 공지고, 아직
게임 앱이 이 컬렉션을 직접 읽지 않는다(리더 쪽에 `packId`로 걸러 보여주는
화면이 없다). `lib/features/catalog/models/notice.dart`의 `Notice`는
예전엔 이 모양과 같은 하드코딩 값객체였지만, 지금은 아래 `notices`
컬렉션을 읽는 모델로 바뀌었다 — 더 이상 이 컬렉션과 같은 모양이 아니다.

## notices/{noticeId} — 앱 전체 공지사항 (하단 탭 "공지사항")

```
title: string
body: string             // 일반 텍스트. 마크다운/리치텍스트 아님.
active: bool              // false면 목록에서 숨긴다(삭제 대신) — 나중에 다시 켤 수 있다.
authorId: string           // 작성한 admin의 uid. 감사용 — 독자에게는 안 보인다.
createdAt: timestamp
```

`genres`/`homeBanners`/`pointPackages`/`packBundles`와 같은 패턴(admin만
쓰고, 로그인한 누구나 읽는다) — 승인 게이트 없이 admin이 쓰면 바로
반영된다. 리더 쪽 `NoticeRepository.watchActiveNotices()`가 `active ==
true`만, 최신순으로 읽는다(`where('active', isEqualTo: true).orderBy('createdAt',
descending: true)` — 복합 색인 필요, 아래 "복합 색인" 절 참고).

**writerNotices와 절대 혼동하지 말 것** — `notices`는 팩과 무관한 플랫폼
전체 공지고 admin 전용, `writerNotices`는 작가가 자기 팩에 올리는 공지다.
admin 쪽 모델도 이름으로 구분해 둔다: `AdminGlobalNotice`
(`lib/admin/models/global_notice.dart`, `notices` 컬렉션) vs `WriterNotice`
(`lib/admin/models/writer_notice.dart`, `writerNotices` 컬렉션).

### 안 읽음 배지 (하단 탭바의 빨간 점)

`CatalogShellPage`가 두 스트림을 실시간으로 비교한다 — 둘 다 스트림이라
앱을 켜 둔 채로 새 공지가 올라와도(또는 다른 기기에서 읽음 처리해도) 재시작
없이 바로 반영된다:
- `NoticeRepository.watchLatestNoticeAt()` — 가장 최근 활성 공지의
  `createdAt`(본문 전체를 구독하지 않고 이 값 하나만 가볍게 구독한다).
- `users/{uid}/readerPrefs/settings.lastNoticeReadAt`(아래 참고) — 이
  유저가 마지막으로 공지사항 탭을 연 시각.

`최근 공지 createdAt > lastNoticeReadAt`(또는 `lastNoticeReadAt`이 아예
없음 + 공지가 하나 이상 있음)이면 배지를 켠다. 게스트(로그인 안 함)는
서버에 읽음 상태를 남길 계정이 없어서, 공지가 하나라도 있으면 항상
안 읽음으로 취급한다.

## users/{uid}/readerPrefs/settings — 리더 표시/재생 환경설정

```
fontId: string
animationEnabled: bool
typingSpeedMs: int
ttsEnabled: bool                 // ⚠️ 더 이상 쓰지 않는다. 아래 참고.
ttsAutoContinueEnabled: bool     // 기본 true. 아래 참고 — ttsEnabled와 달리
                                  // 실제로 읽고 쓰는 살아있는 필드다.
bgmMasterVolume: number          // 0.0(무음)~1.0(원본 그대로), 기본 1.0.
lastNoticeReadAt: timestamp?     // 공지사항 탭을 마지막으로 연 시각.
```

`SceneFrame` 설정 패널(데스크톱 사이드바 / 모바일 하단 시트, 폰트/애니메이션/
TTS/TTS 자동 이어재생/BGM 볼륨)이 쓰는 문서다.

`ttsEnabled`는 예전 기기 내장 TTS(`flutter_tts`/`TtsController`, 지금은 완전히
삭제됐다 — 아래 "TTS 내레이션" 절 참고) 시절 "TTS를 켜 뒀는지" 기록용 필드였는데,
사실 그 값을 읽어서 쓰는 코드는 애초에 없었다(설정 시점에 쓰기만 하고 아무도
읽지 않는 죽은 쓰기였다). 새 Typecast 기반 내레이션은 노드마다 독립적으로
생성되는 콘텐츠라 "재생 중이었는지"를 세션 밖으로 이어갈 개념 자체가 없다
(`effects.tts`에 "상속" 개념이 없는 것과 같은 이유 — 아래 "tts — Typecast
내레이션" 절 참고) — 그래서 새 토글 핸들러는 이 필드를 아예 쓰지 않는다.
기존 문서에 남아있는 값 자체를 지우지는 않지만(`bgmEnabled`와 같은 대우),
이제 아무 코드도 이 필드를 읽거나 쓰지 않는다.

`ttsAutoContinueEnabled`는 `ttsEnabled`와 다르다 — "재생 상태 자체가 노드를
가로질러 이어지는가"(그런 개념은 여전히 없다, 위 문단 참고)가 아니라
"내레이션이 끝나면 자동으로 다음 노드로 넘어갈지"를 묻는, 세션이 아니라
계정에 묶인 **설정값**이다(위 "tts — Typecast 내레이션"의 "자동 이어재생"
절 참고). `ReaderSessionController.setAutoContinueEnabled`가 이 값을 받아
실제 자동 이어재생 여부를 판단한다.

`bgmMasterVolume`은 리더 **본인**의 BGM 취향이다 — 노드 작성자가 정하는
`effects.bgm.volume`(위 "bgm — 배경음악 전환" 절)과는 완전히 다른 값이고,
둘은 서로 override하지 않고 **곱해진다**: 실제 재생 볼륨 =
`effects.bgm.volume × bgmMasterVolume`(`AudioService._effectiveVolume`).
설정 패널의 슬라이더를 드래그하는 동안은 이 문서에 매 프레임 쓰지 않는다
— `SceneFrame`이 로컬 `ReaderPrefs` 상태와 `AudioService.setBgmMasterVolume`
(즉시 반영, 오디오가 드래그 중에도 실시간으로 들린다)만 갱신하다가, 손을
뗀 시점(`Slider.onChangeEnd`)에 한 번만 `ReaderPrefsRepository.save()`를
부른다. 스피커 아이콘을 탭하면 0%/100%를 오가는 음소거 토글이다(이전
정확한 값을 기억하지는 않는다 — `SceneFrame`은 노드가 바뀔 때마다 다시
만들어지는 위젯이라 그 사이의 로컬 상태를 들고 있을 수 없다).

**예전 `bgmEnabled`(bool) 필드를 대체한다** — `ReaderPrefs.fromFirestore`가
새 필드(`bgmMasterVolume`)가 없는 옛 문서를 만나면 옛 `bgmEnabled` 값을
1.0/0.0으로 한 번 옮겨 읽는다(`_readBgmMasterVolume`). 새로 저장할 때부터는
`bgmMasterVolume`만 쓰고 `bgmEnabled`는 더 이상 쓰지 않는다 — 기존 문서에
남아있는 `bgmEnabled` 필드 자체를 지우지는 않지만(불필요한 마이그레이션
쓰기), 그 값은 이제 아무 코드도 안 읽는다.

`lastNoticeReadAt`만 성격이 다르다 — `CatalogShellPage`가 공지사항 탭을
열 때(정확히는, 하단 탭바에서 인덱스가 공지사항으로 바뀌는 순간) 갱신한다.
⚠️ **이 필드는 `ReaderPrefsRepository.save()`(폰트 등을 바꿀 때 쓰는
경로)가 절대 건드리지 않는다** — `save()`는 `SetOptions(merge: true)`로
쓰고, `ReaderPrefs.toFirestore()`도 이 필드를 일부러 안 담는다. 그렇게
분리해 둔 이유: 만약 `save()`가 이 필드까지 포함해서 통째로 덮어썼다면,
유저가 공지 탭을 연 뒤에 폰트를 한 번만 바꿔도 `lastNoticeReadAt`이
조용히 사라져서 배지가 계속 다시 켜지는 실제 버그가 됐을 것이다 — 갱신은
오직 `ReaderPrefsRepository.markNoticesRead()`(마찬가지로 merge 쓰기,
`lastNoticeReadAt` 필드 하나만 건드린다)로만 한다.

## users/{uid}/readingProgress/{packId} — 팩별 읽기 진행 상황

```
currentNodeId: string
visitedNodeCount: int        // 유료 팩 무료 미리보기 한도 판단에 쓰임
lastReadAt: timestamp
```

`users/{uid}/save/current`(GameState 전체 — 인벤토리/레벨 등)와는 별개의
서브컬렉션이다. 예전엔 읽던 위치(currentNodeId)와 미리보기 카운트
(visitedNodeCount)가 GameState 안에 스칼라 하나로만 있어서, 한 팩을 읽다 다른
팩을 열면 서로의 진행 상황을 그냥 덮어썼다(known limitation, CLAUDE.md 참고) —
문서 id를 packId로 잡아 팩마다 독립된 문서를 두는 것으로 고쳤다. 리더
(InteractiveReader/LinearReader)가 노드 이동 시점에 직접 저장한다 — save/current를
갱신하는 CloudSyncController와는 별개의 경로다(ReadingProgressRepository).

## users/{uid}/save/current — GameState 세이브 전체 (schema v7)

```
schemaVersion: int             // 현재 7.
inventory: map<string, int>
playerAttack: int
playerDefense: int
level: int
exp: int
hearts: int
hasUsedAdRevival: bool
ownedPackIds: array<string>    // 소유한(구매/무료로 확보한) 스토리팩 id 목록.
```

`lib/core/state/game_state.dart`의 `GameState.toJson()`/`loadFromJson()`이 이
문서를 통째로 읽고 쓴다(부분 업데이트가 아니라 매번 전체 `.set()`) —
`CloudSyncController`가 `GameState`가 바뀔 때마다(어떤 필드든) 이 문서 전체를
덮어쓴다. **v7에서 `cashBalance`/`addCash`/`spendCash`가 완전히 제거됐다** —
코인 충전(Toss)도 이야기 팩 구매도 이제 전부 아래 `wallet/current.balance`
(서버만 변경)로 통합됐다. 옛 세이브에 `cashBalance` 키가 남아 있어도
`loadFromJson`이 그 키를 아예 안 읽으므로 조용히 무시된다.

`ownedPackIds`는 `purchasePack` Cloud Function이 `arrayUnion`으로 서버에서
먼저 반영하고, 클라이언트(`paywall.dart`)는 성공 응답을 받은 뒤에만
`GameState.markPackOwned()`로 로컬 상태를 맞춘다 — 그래야 그사이 다른 이유로
`GameState`가 한 번 더 저장돼도(전체 문서 덮어쓰기) 서버가 방금 부여한
소유권을 실수로 되돌리지 않는다. ⚠️ `firestore.rules`는 이 문서 전체를
`allow read, write: if isSignedIn() && myUid() == userId`로 자유롭게 허용한다
— `ownedPackIds`만 따로 잠그지 않으므로, 클라이언트가 직접 Firestore SDK로
이 배열에 임의의 packId를 써넣는 것 자체는 규칙상 막혀 있지 않다(알려진 한계,
아직 안 고침).

## users/{uid}/wallet/current — 코인 지갑

```
balance: int        // 코인 잔액. 기본(문서 없음) 0으로 취급.
```

**클라이언트는 읽기만 한다.** `balance`는 오직 `confirmCoinCharge`/`purchasePack`
Cloud Function(둘 다 Admin SDK로 실행되어 `firestore.rules` 자체를 우회한다)만
바꾼다 — 결제/구매를 서버에서 검증한 뒤에만 코인이 움직인다. `lib/features/wallet/data/wallet_repository.dart`의
`watchBalance(uid)`가 이 문서를 구독한다. `ChargePage`/홈 탭 상단 잔액 칩이
전부 이 스트림을 그대로 보여준다 — 클라이언트가 잔액을 직접 더하거나 빼는
코드는 어디에도 없다.

## users/{uid}/wallet/current/transactions/{txId}

```
type: 'charge' | 'purchase' | 'refund'
amount: int                  // 코인, 부호 있음(charge는 +, purchase/refund는 -).
uid: string                  // 이 문서가 속한 유저 — 아래 "admin 결제·정산 화면"
                              // 참고. collectionGroup 쿼리는 경로의 {uid}
                              // 세그먼트를 필터링할 수 없어서 문서 자체에도 넣는다.
displayName: string           // 쓰는 시점의 users/{uid}.displayName 스냅샷.
email: string                  // 쓰는 시점의 users/{uid}.email 스냅샷.
createdAt: timestamp

// type == 'charge'일 때만
packageId: string             // pointPackages/{packageId} 참조.
amountKRW: int                 // 실제 결제 금액(원). refundCoinCharge가 환불액을
                               // 계산하는 유일한 원천 — 이 필드가 없는(이 필드
                               // 추가 전 만들어진) 충전 건은 환불이 거부된다.
relatedPaymentKey: string?     // Toss 결제 키(paymentKey).
cardApproveNo: string?         // Toss 카드 승인번호(카드 결제가 아니면 null).
refundedCoins: int             // 기본 0. 지금까지 이 건에서 환불된 코인 누적.
refundStatus: 'none' | 'partial' | 'full'   // 기본 'none'.

// type == 'purchase'일 때만
packId: string?                // 개별 팩 구매 — storyPacks/{packId} 참조.
bundleId: string?               // 번들 구매 — packBundles/{bundleId} 참조.
packIds: array<string>?         // 번들 구매일 때만 — 그 구매로 새로 소유하게 된
                                // packId 목록(이미 갖고 있던 팩은 안 들어간다).

// type == 'refund'일 때만
originalChargeTxId: string      // 환불 대상이 된 charge 거래 문서 id.
refundedCoins: int              // 이번 환불로 깎인 코인(양수).
refundedKRW: int                 // Toss로 실제 취소된 금액(원).
tossCancelTransactionKey: string?  // Toss 취소 응답의 transactionKey.
reason: string                   // admin이 입력한 환불 사유(필수).
processedBy: string              // 처리한 admin의 uid.
```

읽기 전용은 지갑과 같은 이유(Cloud Function만 쓴다) — `confirmCoinCharge`가
`charge`를, `purchasePack`/`purchaseBundle`이 `purchase`를, `refundCoinCharge`가
`refund`를 쓴다. 문서 id로 멱등성을 보장하는 방식은 타입마다 다르다:
- `charge`: Toss `orderId`를 그대로 문서 id로 쓴다.
- `purchase`(개별 팩): `purchase_${packId}` 고정 id(소유는 영구적이라 "처음
  구매"가 한 번뿐이어야 하므로 packId 자체가 자연스러운 멱등 키다).
- `purchase`(번들): 자동 생성 id — 번들은 나중에 packIds가 늘어나면 이미
  산 유저도 새로 추가된 팩만큼 정당하게 재구매할 수 있어야 해서, 고정
  키를 쓸 수 없다(대신 트랜잭션 내부에서 매번 살아있는 ownedPackIds를
  다시 읽어 이중 청구를 막는다 — `purchaseBundle` 함수 주석 참고).
- `refund`: 자동 생성 id. 이중 환불 방지는 고정 id가 아니라 (a) 매번
  `charge` 문서의 `refundedCoins`를 다시 읽어 계산하는 것과 (b) Toss
  서버 자신이 결제 하나의 누적 취소 금액이 원래 결제 금액을 못 넘게
  강제하는 것, 이 두 겹으로 한다.

### admin 결제·정산 화면 (`lib/admin/pages/billing_dashboard_section.dart`)

"결제·정산 관리"(결제내역/코인사용내역/정산내역 3탭)가
`collectionGroup('transactions')`로 모든 유저의 거래를 가로질러 읽는다.
`firestore.rules`의 `{path=**}/transactions` 규칙이 이 조회를 admin에게만
허용한다(각 유저의 중첩 `wallet/current/transactions` 규칙은 본인만 읽는
직접 구독에만 적용되고, collectionGroup 쿼리에는 별도의 `{path=**}` 규칙이
필요하다 — `{path=**}/nodes`와 같은 이유).

**필터 조합(의도적 단순화)**: Firestore 쿼리 하나엔 범위(부등호) 조건을 가진
필드가 정렬 기준과 안전하게 맞물리려면 사실상 하나만 있는 게 안전하다.
그래서 `AdminBillingRepository`(`lib/admin/data/billing_repository.dart`)는:
- 이름 검색이 없을 때: `type`(동등) + `createdAt` 범위(기간 필터) + `createdAt`
  으로 정렬.
- 이름 검색이 있을 때: 범위/정렬 기준이 `displayName`(접두어 검색)으로
  바뀌고, 그동안 기간 필터는 서버 쿼리에서 빠지고 그 페이지 안에서
  클라이언트로만 좁혀진다.
- `uid` 검색은 동등 필터라 어느 모드와도 같이 걸 수 있다(항상 서버 쿼리에
  들어간다).
- 결제내역의 결제금액(KRW) 최소/최대 필터는 항상 클라이언트에서만 좁힌다
  (세 번째 범위 필드를 쓰지 않으려고).

이 단순화 때문에 필터가 걸린 페이지는 페이지 크기(20)보다 적은 행만 보일
수 있다 — 페이지네이션 커서 자체는 원본(필터 전) 조회 결과 기준이라
"다음"을 계속 누르면 끝까지 훑을 수 있다. `firestore.indexes.json`에 이
세 가지 쿼리 모양(type+createdAt / type+uid+createdAt / type+displayName+
createdAt, 전부 `queryScope: COLLECTION_GROUP`)의 복합 색인과, `createdAt`
단독 범위 조회(아래 `computeDailyRevenueSnapshot`용)를 위한 `fieldOverrides`
항목을 추가해 뒀다.

## users/{uid} — 프로필/역할 문서

기존 `users/{uid}/save/current`(게임 진행 데이터, CLAUDE.md의 "Auth + cloud save"
참고)와는 별개의, 같은 uid 아래 놓이는 최상위 문서다 — 하나는 세이브 데이터, 이건
신원/권한 데이터로 목적이 다르다.

```
displayName: string
email: string
role: 'reader' | 'author' | 'admin'                          // 최초 로그인 시 기본값 'reader'
authorApplicationStatus: 'none' | 'pending' | 'approved' | 'rejected'
createdAt: timestamp
```

- `role`이 접근 권한의 단일 기준이다. `'author'`/`'admin'` 둘 다 작가 편집기
  (`lib/admin/`, `lib/main_admin.dart`) 접근이 가능하고, `'admin'`만 아래
  `authorApplications` 승인 화면을 볼 수 있다. 지금 `lib/admin/data/admin_allowlist.dart`의
  이메일 화이트리스트가 이 필드로 대체될 예정이다(별도 작업 단계).
- `authorApplicationStatus`는 본인의 `authorApplications/{uid}` 문서 중 최신 상태를
  그대로 복사해 둔 값이다 — 편집기 진입 화면이 매번 두 문서를 조회하지 않고 이
  필드 하나만 보고 분기할 수 있게 하기 위한 비정규화다.
- 이 컬렉션에서 스스로를 `'admin'`으로 만들 방법은 없다 — 최초 admin 계정은
  Firebase 콘솔(또는 1회성 스크립트)로 수동 생성해야 한다.

## authorApplications/{uid} — 작가 신청서

문서 id를 uid로 고정한다(신청서 하나당 계정 하나) — "이 사람이 이미 신청했는가"를
쿼리 없이 단건 조회로 확인할 수 있고, 반려 후 재신청도 새 문서 대신 같은 문서를
덮어쓰면 된다.

```
uid: string
displayName: string
bio: string
portfolioLinks: array<string>?      // 선택. 기존 작품 링크 등.
status: 'pending' | 'approved' | 'rejected'
rejectionReason: string?
submittedAt: timestamp
reviewedBy: string?                 // 검토한 admin의 uid
reviewedAt: timestamp?
```

- 승인 시: 이 문서의 `status`를 `'approved'`로 바꾸는 동시에 `users/{uid}.role`을
  `'author'`로, `authorApplicationStatus`를 `'approved'`로 올린다.
- **이 승인은 "작가 자격"만 부여한다.** 아래 `storyPacks/{packId}/nodes`의
  draft → 승인 대기 → 발행 흐름과는 완전히 별개의 검토 단계다 — 작가 자격을 얻었다고
  콘텐츠 검토가 생략되지 않는다. 작가가 된 이후에도 실제로 쓴 노드/챕터 하나하나는
  여전히 기존 `status`/`pendingAction`/`liveSnapshot` 흐름을 그대로 거쳐야 독자
  앱에 노출된다. 이 문서는 "이 계정이 작가 편집기를 쓸 수 있는가"만 판단하고,
  "이 계정이 쓴 콘텐츠가 라이브로 나가도 되는가"는 아래 노드 승인 흐름의 몫이다.

## genres/{genreId} — 장르 태그 (관리 데이터, Dart 하드코딩 아님)

```
name: string        // 표시용 라벨, 예: "공포"
slug: string         // storyPacks.genres 배열에 저장되는 안정적인 키, 예: 'horror'
sortOrder: int
active: bool         // true→false로 바꿔 목록에서만 숨긴다(삭제 대신) — 이미 이
                     // slug를 쓰고 있는 오래된 스토리팩이 있을 수 있어서다.
```

장르 목록을 코드가 아니라 이 컬렉션에 두는 이유는, 나중에 admin이 앱 재배포 없이
장르를 추가/수정할 수 있게 하기 위해서다. 초기 목록은 이 문서를 읽는 관리 UI가
생기기 전까지 Firebase 콘솔에서 수동으로 채운다.

## homeBanners/{bannerId} — 홈 화면 히어로 배너

```
imageUrl: string          // Storage admin/home_banners/{bannerId}.jpg 다운로드 URL.
linkedPackId: string?      // storyPacks/{packId} 참조. 없으면 탭해도 이동 안 함.
sortOrder: int
active: bool
startAt: timestamp?        // 노출 기간. 둘 다 null이면 active인 한 항상 노출.
endAt: timestamp?
eyebrow: string?           // 텍스트 오버레이 — 타이틀 위 작은 라벨(대문자로 표시).
title: string?              // 텍스트 오버레이 — 큰 제목. ⚠️ 아래 규칙 참고.
subtitle: string?            // 텍스트 오버레이 — 타이틀 아래 설명.
```

`genres`와 같은 패턴(admin만 쓰고, 로그인한 누구나 읽는다). "홈 배너
관리"(`HomeBannerManagementSection`)가 드래그로 `sortOrder`를 재배열한다.
리더 쪽 `HomeBannerRepository`가 active + 기간 필터링을 클라이언트에서
조합해 지금 노출해도 되는 배너만 걸러낸다.

`eyebrow`/`title`/`subtitle`은 전부 선택이고 서로 독립적이다(예: title만
있고 subtitle은 없어도 정상 — title만 큼직하게 보인다). **단, `title`이
없으면(null이거나 빈 문자열) 텍스트 오버레이 자체를 렌더링하지 않는다 —
스크림 그라디언트도 같이 안 그려진다.** eyebrow/subtitle만 있고 title이
없는 조합은 지원 대상이 아니다 — title이 "이 배너에 텍스트 오버레이를
켤지"를 결정하는 스위치 역할까지 겸한다. 그래서 이미지만 있고 세 필드가
전부 비어 있는 기존 배너는 오늘과 완전히 같게 렌더링된다(리더 쪽
`HomeBanner.hasTextOverlay`, admin 폼의 "타이틀을 비워두면 이미지 전용
배너로 유지돼요" 안내 문구가 이 규칙을 그대로 반영한다).

## homeEvents/{eventId} — 홈 탭 진입 이벤트 팝업

```
imageUrl: string          // Storage admin/home_events/{eventId}.jpg 다운로드 URL.
title: string?             // 팝업 이미지 아래 짧은 타이틀. 없으면 이미지만.
linkedPackId: string?      // storyPacks/{packId} 참조. homeBanners와 같은 패턴 —
                           // 새 링크 스킴(예: 외부 URL)을 만들지 않고 그대로 재사용한다.
                           // 없으면 이미지를 탭해도 아무 일도 안 일어난다.
sortOrder: int             // 동시에 여러 이벤트가 active여도 이 값이 가장 작은
                           // 것 하나만 보여준다(모달을 겹쳐 띄우지 않는다).
active: bool
startDate: timestamp?      // 노출 기간. 둘 다 null이면 active인 한 항상 노출 대상.
endDate: timestamp?
```

`homeBanners`와 같은 패턴(admin만 쓰고, 로그인한 누구나 읽는다). "홈 이벤트
관리"(`HomeEventManagementSection`)가 드래그로 `sortOrder`를 재배열한다.
리더 쪽 `HomeEventRepository`(`lib/features/catalog/data/home_event_repository.dart`)가
active + 기간 필터링과 `sortOrder` 정렬까지 해서 반환하고, `HomeTab`이 그중
첫 번째(가장 작은 `sortOrder`)만 후보로 삼는다.

### 팝업 노출/닫음 상태 — Firestore가 아니라 기기 로컬에만 저장

"이 이벤트를 오늘 이미 봤는지" / "다시 보지 않기를 눌렀는지"는 계정에
동기화하지 않는다 — 최근 검색어(`home_tab.dart`의 `_recentSearchesPrefsKey`)와
같은 이유로, 기기별로 달라도 되는 정보라 `users/{uid}` 아래 문서를 새로 만들지
않고 `SharedPreferences`에만 저장한다
(`HomeEventDismissalStore`, `lib/features/catalog/data/home_event_dismissal_store.dart`).
**이 프로젝트에서 Firestore 문서로 관리하지 않는 상태이므로, 여기 스키마
문서에는 정확한 필드 모양만 남긴다** — Firestore 쪽 규칙/색인과는 무관하다.

로컬 저장 키(`home_event_dismissals`)는 eventId를 키로 하는 JSON 맵:

```json
{
  "<eventId>": { "lastShownDate": "2026-08-22", "neverShowAgain": false }
}
```

- `lastShownDate`: KST(UTC+9) 기준 "YYYY-MM-DD"(`rankingSnapshots` 문서 id와
  같은 날짜 계산 방식 — 기기 로컬 시간대가 아니라 UTC에 9시간을 명시적으로
  더한다). 오늘 날짜와 같으면 오늘은 다시 안 띄운다.
- `neverShowAgain`: true면 그 `eventId`에 한해서 영구적으로 안 띄운다 —
  **반드시 eventId별로 스코프된다.** 전역 플래그가 아니라서, 과거 이벤트를
  "다시 보지 않기"로 껐어도 admin이 새 이벤트(다른 eventId)를 만들면 그
  이벤트는 정상적으로 새로 뜬다.
- 둘 다 없는(맵에 그 eventId 키 자체가 없는) 상태가 기본값 — 아직 한 번도
  안 보여준 이벤트다.

## pointPackages/{packageId} — 충전 화면 코인 상품

```
name: string
coinAmount: int              // 기본 지급 코인.
bonusCoins: int               // 추가 보너스 코인. 기본 0.
originalPriceKRW: int         // 원화 정가.
salePriceKRW: int?            // 할인가(원화). null이면 할인 없음.
discountStartAt: timestamp?
discountEndAt: timestamp?
active: bool
sortOrder: int
platform: 'web' | 'android' | 'ios'
```

`genres`/`homeBanners`와 같은 패턴. `storyPacks`의 price/salePrice와 같은
할인 계산 모양을 공유하지만, **이건 실제 원화(KRW) 결제 상품이다** —
`storyPacks.price`(코인 단위)와 혼동하지 않는다. 충전 화면(`ChargePage`)이
`active == true && platform == 'web'`인 상품만 읽어 카드로 보여주고, 사용자가
결제하면 Toss Payments 팝업 → `confirmCoinCharge` Cloud Function이 이 문서를
Admin SDK로 다시 읽어 서버에서 가격을 재계산한 뒤 `users/{uid}/wallet/current.balance`에
`coinAmount + bonusCoins`를 더한다(클라이언트가 보낸 가격은 신뢰하지 않는다).

## packBundles/{bundleId} — 스토리팩 여러 개를 묶은 코인 할인 번들

```
name: string
packIds: array<string>        // storyPacks/{packId} 참조 여러 개.
price: int                    // 코인 단위 정가 — 구매자가 packIds를 하나도
                               // 안 가졌을 때 기준.
salePrice: int?                // 할인가(코인). null이면 할인 없음.
discountStartAt: timestamp?
discountEndAt: timestamp?
active: bool
sortOrder: int
```

`genres`/`homeBanners`/`pointPackages`와 같은 패턴(admin만 쓰고, 로그인한
누구나 읽는다) — storyPacks처럼 draft/liveMetadata 이중 게이트는 없다.
`price`/`salePrice`/할인 기간은 storyPacks의 가격 필드와 정확히 같은 모양을
공유하지만, **이건 코인 단위다**(pointPackages의 원화와 혼동하지 않는다).

**부분 보유 프로레이팅**: 구매자가 packIds 중 일부를 이미 갖고 있어도 구매를
막지 않는다 — `effectivePrice(번들) * 안 가진 팩 수 / 전체 팩 수`를 반올림한
만큼만 청구한다. 전부 이미 가졌으면 구매 자체를 막는다(더 팔 게 없어서).
이 계산은 두 곳에 있다:
- `lib/features/catalog/models/pack_bundle.dart`의 `PackBundle.amountToChargeFor` —
  화면에 "이미 N개 보유 — X코인만 더 내면돼요"를 미리 보여주는 용도.
- `functions/src/index.ts`의 `purchaseBundle` Cloud Function — 실제 청구액의
  유일한 원천. 클라이언트는 `bundleId`만 넘기고, 가격/보유 여부/잔액은 전부
  서버가 직접 다시 읽어서 계산한다(`confirmCoinCharge`/`purchasePack`과 같은
  보안 원칙).

`purchasePack`과 달리 거래 문서(`users/{uid}/wallet/current/transactions/{txId}`)
id를 `purchase_${packId}`처럼 고정하지 않고 매번 자동 생성 id를 쓴다 — 번들은
관리자가 나중에 `packIds`를 늘릴 수 있어서, 이미 산 유저도 새로 추가된 팩만큼은
정당하게 한 번 더 결제할 수 있어야 한다(고정 id를 쓰면 그 재구매가 막히거나
잘못 처리된다). 이중 청구 방지는 고정 id 대신 트랜잭션 내부에서 매번
`ownedPackIds`/`wallet.balance`를 다시 읽어 안 가진 팩 개수를 재계산하는 것으로
보장한다(Firestore 트랜잭션은 직렬화 가능하므로 재시도/동시 호출도 안전하다).

## revenueSnapshots/{date} — 일별 매출/코인 지급·사용/환불 집계 ("YYYY-MM-DD" KST)

```
revenueKRW: int        // 그날 충전(charge) 결제금액 합계.
chargeCount: int         // 그날 충전 건수.
coinsGranted: int         // 그날 지급된 코인 합계(base+bonus).
coinsSpent: int            // 그날 팩/번들 구매로 쓰인 코인 합계(절대값).
refundedKRW: int           // 그날 처리된 환불의 KRW 합계(환불이 실행된
                           // 날짜 기준이지, 환불 대상 충전이 있었던 날짜
                           // 기준이 아니다).
refundedCoins: int          // 그날 처리된 환불의 코인 합계.
generatedAt: timestamp
```

`functions/src/index.ts`의 `computeDailyRevenueSnapshot`(매일 KST 00:20 예약
실행, `computeDailyRankingSnapshot`의 00:10 바로 뒤 — 리소스 경합을 피하려고
10분 띄운 임의의 값)만 쓴다 — `collectionGroup('transactions')`를 그 직전
하루(KST)의 `createdAt` 범위로만 걸러 전 유저의 거래를 한 번에 훑고
type별로 나눠 집계한다. **그래서 "오늘" 문서는 항상 없다** — 다음날
00:20이 돼야 어제치가 생긴다. admin "정산내역" 탭이 이 컬렉션만 읽고,
거래를 매번 다시 훑지 않는다. Admin SDK로만 쓰이므로 `firestore.rules`엔
쓰기 규칙이 없다(rankingSnapshots와 같은 패턴) — 다만 읽기는
rankingSnapshots(로그인만 하면 누구나)와 달리 admin만 허용한다(매출은
운영 데이터라서).

## 결제 환불 (`refundCoinCharge` Cloud Function)

정책: **미사용 코인만 환불 가능**, admin이 결제내역 화면에서 수동으로만
처리한다(독자에게 보이는 환불 버튼은 없다). 코인은 충전 건별로 구분되지
않는 단일 지갑 잔액이라 "이 충전에서 온 코인이 아직 남아 있는지"를 정확히
알 수 없다 — 그래서 공정한 근사치로 계산한다:

```
refundableCoins = min(원래 지급 코인 - 이미 환불된 코인, 현재 지갑 잔액)
refundKRW = round(원래 결제 금액(KRW) * refundableCoins / 원래 지급 코인)
```

`refundableCoins <= 0`이면(이미 다 써서 환불할 게 없음) 거부한다. 가격/보유
여부와 마찬가지로 이 계산은 전부 서버(`refundCoinCharge`)가 하고, 클라이언트는
`uid`/`chargeTxId`/`reason`만 보낸다 — admin 여부도 클라이언트 주장을 믿지
않고 서버가 `users/{uid}.role`을 직접 다시 읽어 확인한다.

Toss 결제 취소(`POST /v1/payments/{paymentKey}/cancel`)를 `cancelAmount`
(= `refundKRW`)로 부분 취소 호출한 뒤, 성공했을 때만 Firestore에 쓴다 — 실패하면
아무것도 안 쓰고 Toss가 준 에러 메시지를 그대로 호출자에게 돌려준다. Toss는
결제 하나(paymentKey)의 누적 취소 금액이 원래 결제 금액을 못 넘도록 자체적으로
강제하므로, 이 함수의 계산이 동시 요청 등으로 살짝 어긋나 있어도 이중 환불의
최종 방어선이 되어 준다.

## 승인 대기함 조회 (collection group)

승인 대기함 탭은 모든 스토리팩을 통틀어 `pendingAction`이 설정된 노드를
`collectionGroup('nodes').where('pendingAction', whereIn: ['create','edit','delete'])`로
조회한다. Firestore 콘솔에서 이 컬렉션 그룹 쿼리용 복합 색인을 처음 한 번
만들어야 한다 — 쿼리를 처음 실행하면 콘솔 링크가 포함된 에러가 뜨고, 그 링크를
따라가면 바로 만들 수 있다.

### 작가 쪽 — 노드별 저장은 그대로, 제출은 일괄로 (`lib/admin/pages/story_tab_view.dart`)

문서 스키마/필드는 안 바뀌었지만 **제출 흐름(워크플로우) 자체는 바뀌었다** —
스키마 문서라도 이 변화를 기록해 둔다:

- 예전엔 노드 편집 화면(`NodeEditor`)마다 "임시저장"과 "승인 요청 보내기"
  버튼이 따로 있어서, 여러 노드를 고쳤으면 노드 수만큼 "승인 요청 보내기"를
  눌러야 했다.
- 지금은 `NodeEditor`에 "임시저장"만 남는다 — 승인 요청은 "노드별로 쓰기"
  사이드바(`story_node_sidebar.dart`)의 "변경사항 전체 승인요청" 버튼
  하나로 한다. 이 버튼은 이 팩에서 "임시저장은 됐지만 아직 승인 요청을
  안 보낸" 노드를 전부 찾아 한 번에 제출한다(`_requestApprovalForNode`를
  루프로 재사용 — 새 제출 경로가 아니다). 대상이 없으면 버튼이 비활성화된다.
- "제출 안 한 변경사항"을 찾는 기준은 두 갈래다: (1) 세션 캐시에 있는 노드
  (`_cachedUnsubmittedNodes()`, Firestore 조회 없이 즉시 계산), (2) 이미
  Firestore에 임시저장돼 있고(`pendingAction == null`) 세션 캐시엔 없는 노드
  (`_persistedUnsubmittedNodes`, `_refreshUnsubmittedNodes()`가 채운다) —
  둘 다 판단 자체는 `AdminStoryNode.hasUnsubmittedChanges` getter 하나만
  쓴다. "변경사항 전체 승인요청" 버튼의 개수/제출 대상은 `_allUnsubmittedNodes()`가
  이 둘을 합쳐서 만든다(세션 캐시에 있는 노드가 `_persistedUnsubmittedNodes`
  쪽에 우연히 같은 id로 남아 있어도 무시 — 캐시 쪽이 항상 더 최신이다).
  - **버그였다가 고침 (1) — 비교 로직 자체**: 처음엔 `hasUnsubmittedChanges`가
    `contentSnapshot()`과 `liveSnapshot`(Firestore에서 그대로 읽은 raw
    map)을 정규화 없이 바로 `jsonEncode`로 비교했다 — `effects` 필드가
    생기기 전에 승인된 것처럼 오래된 `liveSnapshot`은 새 필드가 아예 빠져
    있어서, canonical한 `contentSnapshot()`과 항상 달라 보여 실제로는 안
    바뀐 노드까지 "제출 대상"으로 잘못 포함시켰다. 사이드바 "수정됨"
    배지는 이 문제가 없었다(세션 캐시 존재 여부만 봤을 뿐, diff 비교
    자체를 안 했다) — 그래서 배지는 정확한데 버튼 개수만 부풀어 보이는
    것으로 드러났다. `hasUnsubmittedChanges`로 통합하면서 두 표시가 하나의
    판단 기준만 쓰게 됐다.
  - **버그였다가 고침 (2) — 새로고침 타이밍**: 위 (1)을 고친 뒤에도, 세션
    캐시에 있는 노드(1번 갈래)까지 `_refreshUnsubmittedNodes()`가 채우는 한
    목록(`_unsubmittedNodes`)에 같이 담겨 있었다 — 그 메서드는 Firestore
    조회가 섞여 있어서 "노드 상태가 실제로 바뀌는 시점"(저장/삭제/일괄
    처리 직후, 최초 로드)에만 다시 불렸는데, 노드를 편집하는 것 자체는(예:
    `effects.bgm` 트랙 선택) 그 시점에 안 들어가서, "수정됨" 배지는 매
    build마다 다시 계산돼 즉시 뜨는데 버튼 개수는 다음 저장/새로고침
    시점까지 그 변경을 못 잡는 지연이 있었다 — 특정 필드(BGM 등)의 비교
    로직 문제가 아니라 캐시 기반 판단 자체가 지연 새로고침에 얹혀 있던 게
    원인이었다. 캐시 조회는 Firestore를 안 타 매번 다시 계산해도 비용이
    없으므로, `_cachedUnsubmittedNodes()`로 완전히 분리해 지연 없이 항상
    즉시 계산하게 했다 — Firestore 조회가 필요한 (2)만
    `_refreshUnsubmittedNodes()`에 남았다.
  - **버그였다가 고침 (3) — 세 번째 독립 구현체 발견 + 완전 통합**: (1)/(2)를
    고친 뒤에도 승인 대기함(`ApprovalsTab`)의 "내용상 변경 없음" 판정은
    **완전히 별개의 세 번째 구현**이었다 — 본문/순서/배경 이미지/선택지
    네 개만 손으로 나열해서 봤고 `effects`는 아예 비교 대상에도 없었다.
    그래서 `effects.bgm`만 바꾼 노드가 "수정됨" 배지엔 뜨고 버튼 개수에도
    잡히는데, 정작 승인 화면에 들어가면 "완전히 같아요"로 나오는 어긋남이
    또 났다. 지금은 `NodeDiff.compute()`(`lib/admin/data/node_diff.dart`)
    하나가 **이 프로젝트에서 "이 노드가 liveSnapshot과 다른가"를 답하는
    유일한 곳**이고, `hasUnsubmittedChanges`는 `NodeDiff.compute(this).anyChanged`를
    그대로 위임할 뿐이다 — 사이드바 배지/버튼/승인 화면 셋 다 결국 같은
    함수를 탄다. `effects` 비교(`NodeDiff.effectsChanged`)는 blackout/
    shake/sfx/flash/haptic/bgm처럼 알려진 키를 하나씩 나열하지 않고, 두
    스냅샷을 각각 `NodeEffects.fromJson(...).toJson()`으로 정규화한 뒤
    **통째로** `jsonEncode` 비교한다 — 그래서 앞으로 새 효과 타입이 생겨도
    `NodeEffects.toJson()`/`fromJson()`에 필드를 추가하는 것(그 효과를
    동작시키려면 어차피 해야 하는 작업)만으로 diff 대상에도 자동으로
    포함된다. 이 소스 파일이 `admin_story_node.dart`를 import하고
    `admin_story_node.dart`도 `node_diff.dart`를 다시 import하는 순환
    참조지만, 둘 다 순수 클래스 정의라 Dart에서 문제없이 컴파일된다.
- "구조 보기"(`StoryMapView`)의 기존 "전체 임시저장"/"전체 승인 요청
  보내기" 툴바(`_SaveAllToolbar`)는 그대로다 — 이건 세션 캐시에 있는
  항목만 다루는, 이번 변경과는 별개의 기존 기능이다.

### admin 쪽 — 목록이 아니라 diff로 검토 (`lib/admin/pages/approvals_tab.dart`)

승인 대기함 탭은 이제 각 노드의 "지금 제출된 내용"만 나열하지 않고,
`liveSnapshot`(before)과 최상단 필드(after)를 비교한 diff를 보여준다
(`lib/admin/data/node_diff.dart`의 `NodeDiff.compute`, 추가 조회 없이
`PendingNodeRef.node`가 이미 들고 있는 두 값만 비교한다):

- **본문**: `diff_match_patch` 패키지(신규 의존성)로 단어/문장 단위 diff를
  계산해 추가는 초록, 삭제는 빨간 취소선으로 보여준다.
- **순서**(`order`): 바뀌었으면 "N번째 → M번째로 이동"으로 보여준다 —
  라이브로 나가 있는 노드의 순서가 바뀌면 독자가 실제로 읽는 흐름 자체가
  바뀌는 것이라, 본문 수정과 똑같이 검토 대상으로 다룬다(신규 노드는
  "이동"이라는 개념이 없어 이 항목을 안 보여준다). "내용상 변경 없음"
  안내는 순서를 포함해 정말로 아무것도 안 바뀌었을 때만 뜬다 — 순서만
  바뀐 걸 "변경 없음"으로 잘못 보여준 적이 있어서, 지금은 order도 반드시
  같이 확인한다.
- **배경 이미지**: `backgroundImage`가 바뀌었으면 이전/이후 썸네일을
  `images/{imageId}` 조회로 나란히 보여준다.
- **선택지**(`interactive` 팩만): before/after `choices` 배열을
  label+nextNodeId 기준으로 비교해 추가/삭제만 보여준다(안 바뀐 선택지는
  생략).
- **연출 효과**(`effects`): 위 "버그였다가 고침 (3)" 참고 — blackout/shake/
  sfx/flash/haptic/bgm/tts를 개별로 안 보여주고, "연출 효과 설정이 바뀌었어요"
  라는 뭉뚱그린 안내 + 태그 하나만 보여준다(`NodeDiff.effectsChanged`가
  통째 비교라 "정확히 뭐가 바뀌었는지"는 이 diff 계산 자체가 모른다 —
  자세한 값은 admin이 노드 편집 화면을 직접 열어서 확인해야 한다).
- 각 카드에 어떤 항목이 바뀌었는지 태그(본문 수정/순서 변경/배경 이미지
  변경/선택지 변경/연출 효과 변경)를 보여준다. 삭제 요청
  (`pendingAction == 'delete'`)은 비교할 새 콘텐츠가 없으므로 diff 대신
  안내 문구만 보여준다.
- "내용상 변경 없음" 안내는 `NodeDiff.anyChanged`가 false일 때만 뜬다 —
  본문/순서/배경 이미지/선택지/연출 효과 다섯 중 뭐라도 하나만 바뀌어도
  (신규 노드는 내용과 무관하게 항상) 뜨지 않는다.
- 승인/반려는 카드마다 독립적이다 — 하나를 처리해도 같은 배치의 다른
  카드에는 영향이 없다. 처리한 카드는 목록에서 사라지지 않고 흐리게 +
  "✓ 승인됨"/"반려됨" 배지로 표시된 채 그 자리에 남는다(`watchPendingNodes()`
  쿼리 자체는 `pendingAction`이 없어진 문서를 더 이상 안 돌려주므로, 화면
  쪽에서 방금 처리한 카드의 스냅샷을 따로 기억해 뒀다가 계속 그린다).
- **반려는 사유 입력이 필수**다(빈 채로 못 보낸다) — 그 사유가
  `rejectionReason`에 저장돼 작가에게 그대로 전달된다(위 필드 설명 참고).

## 복합 색인이 필요한 쿼리 (`firestore.indexes.json`)

동등 필터(`where(field, isEqualTo: ...)`)와 다른 필드의 `orderBy`를 함께 쓰는
쿼리는 Firestore 자동 단일 필드 색인만으로는 안 되고 복합 색인이 필요하다.
지금 코드베이스에서 여기 해당하는 쿼리 둘을 저장소 루트의 `firestore.indexes.json`에
정의해 뒀다:

- `genres`: `GenreRepository.watchActiveGenres()` — `where('active', isEqualTo: true).orderBy('sortOrder')`
- `packBundles`: `PackBundleRepository.watchActiveBundles()` — `where('active', isEqualTo: true).orderBy('sortOrder')`
  (genres/homeBanners/homeEvents/pointPackages와 같은 모양의 색인)
- `homeEvents`: `HomeEventRepository.watchActiveEvents()`(리더 쪽) —
  `where('active', isEqualTo: true).orderBy('sortOrder')` (homeBanners와 정확히 같은 모양)
- `notices`: `NoticeRepository.watchActiveNotices()`/`watchLatestNoticeAt()` —
  `where('active', isEqualTo: true).orderBy('createdAt', descending: true)`
  (같은 색인을 두 쿼리가 공유한다 — 후자는 `.limit(1)`만 추가로 붙인다)
- `storyPacks`: `AdminStoryRepository.watchPacksForAuthor(authorId)` — `where('authorId', isEqualTo: authorId).orderBy('title')`
- `comments`(최상위): `StoryPackCommentRepository.fetchPage()` — `where('isDeleted',
  isEqualTo: false).where('parentCommentId', isEqualTo: null).orderBy('createdAt',
  descending: true)`.
- `comments`(답글): `StoryPackCommentRepository.fetchReplies()` — `where('parentCommentId',
  isEqualTo: 부모id).where('isDeleted', isEqualTo: false).orderBy('createdAt')`.
  정렬 방향이 위 최상위 쿼리와 반대(오름차순)라 별개 색인이다.
  `reviews`는 색인이 필요 없다 — `StoryPackReviewRepository.fetchPage()`가 동등 필터
  없이 `orderBy('createdAt', descending: true)`만 쓰므로 Firestore 자동 단일 필드
  색인으로 충분하다.
- `transactions`(`COLLECTION_GROUP`, admin 결제·정산 화면): 세 가지 쿼리 모양
  전부 — `type`+`createdAt`(기본 조회), `type`+`uid`+`createdAt`(uid 검색),
  `type`+`displayName`+`createdAt`(이름 검색). 왜 세 개로 나뉘는지는 위
  "admin 결제·정산 화면" 절 참고.

`fieldOverrides`에는 별도로 두 개 더 있다 — `nodes` 컬렉션의 `pendingAction`
필드를 `COLLECTION_GROUP` 범위에서도 쿼리할 수 있게 하는 오버라이드,
`transactions` 컬렉션의 `createdAt` 필드를 `COLLECTION_GROUP` 범위에서
단독으로(다른 필터 없이) 쿼리할 수 있게 하는 오버라이드(computeDailyRevenueSnapshot이
하루 범위로만 걸러 모든 유저의 거래를 훑을 때 쓴다).
`AdminStoryRepository.watchPendingNodes()`의 `collectionGroup('nodes').where('pendingAction', whereIn: [...])`가
여기 해당한다 — 이건 앞서 추가한 `{path=**}/nodes/{nodeId}` 보안 규칙과는
완전히 별개의 요구사항이다: 보안 규칙은 "이 요청을 허용할지"를 정하고, 필드
색인 범위(`queryScope`)는 "이 필드를 collection-group 범위에서 필터링할 수
있는지"를 정한다 — 규칙만 고치고 이 오버라이드가 없으면, 승인 대기함 목록이
잠깐 보였다 사라지는 것처럼 보일 수 있다(캐시된 결과가 먼저 그려졌다가,
서버가 색인 부족으로 쿼리를 거부하면서 스트림이 에러 상태로 리셋되기 때문).

색인/필드 범위가 없이 이 쿼리들을 실행하면 Firestore가 `FAILED_PRECONDITION`
에러를 던지는데,
관련 화면들의 `StreamBuilder`가 `snapshot.data ?? []`만 보고 에러 여부는 따로
확인하지 않아서 "결과가 진짜 비어 있다"와 "쿼리 자체가 실패했다"가 화면에서는
똑같이 보인다 — 새 스토리팩 다이얼로그의 장르 목록에서 실제로 겪은 문제다.

`.firebaserc`(프로젝트: `trpg-213c1`)와 `firebase.json`의 `firestore.indexes` 항목이
이미 이 파일을 가리키고 있어서, `firebase deploy --only firestore:indexes`로
바로 배포할 수 있다 — 위 "승인 대기함" collection-group 색인처럼 콘솔에서 수동으로
만들어도 되지만, 이 둘은 파일로 관리해 재현 가능하게 남겨 뒀다.

## 보안 규칙 — 원본은 저장소 루트의 `firestore.rules`

**규칙 전문은 여기 옮겨 적지 않는다.** 저장소 루트의 `firestore.rules`가 실제로
`firebase deploy --only firestore:rules`로 배포되는, 지금 라이브에 적용 중인
유일한 원본이다 — 예전엔 이 문서에도 규칙 전문을 복사해 뒀는데, 코드가
바뀔 때(특히 노드의 blocks 스키마 마이그레이션) 그 사본을 갱신하지 않은 채로
방치돼서 실제 배포본과 완전히 다른 내용(예전 필드명, 없는 컬렉션)으로
어긋났다 — 그 어긋난 사본을 다시 보고 "고쳤다"고 착각해 배포하는 바람에
콘솔에서만 되어 있던 실제 수정이 되돌아가 admin 승인이 막히는 실제 장애가
여러 번 났다. 규칙을 확인하거나 고칠 때는 항상 `firestore.rules`를 직접 열어라.

읽을 때 알아두면 좋은 구조:

- **역할 기반**(`myRole()`/`isAdmin()`/`isAuthorOrAdmin()`) — `users/{uid}.role`
  하나로 접근 권한을 가른다. 예전의 이메일 화이트리스트(`lib/admin/data/admin_allowlist.dart`)는
  삭제됐다.
- **누락 필드 방어** — 문서에 없을 수 있는 필드는 전부 `resource.data.get('필드', 기본값)`으로
  읽는다(`resource.data.필드` 같은 점(`.`) 표기가 아니라). 필드가 아예 없는
  문서에 점 표기로 접근하면 "속성을 찾을 수 없음" 에러로 **요청 전체**가
  permission-denied로 거부된다 — `authorApplications`, `storyPacks`(title/genres/
  price 등), `storyPacks/.../nodes`(blocks 마이그레이션 이후 필드) 세 곳 모두
  이 패턴으로 실제 장애를 겪은 뒤 고쳤다. 새 규칙을 추가할 때도 이 패턴을
  따를 것 — 특히 오래된 문서/아직 아무도 안 건드린 신규 문서는 최신 필드가
  없을 수 있다는 걸 항상 가정해야 한다.
- **draft ↔ live 이중 게이트** — `storyPacks`/`storyPacks/.../nodes` 둘 다 "지금
  편집 중인" top-level 필드와 "마지막으로 승인된" 스냅샷(`liveMetadata`/
  `liveSnapshot`)을 같은 문서에 같이 갖는다. 작가 본인의 update 규칙은 draft
  필드를 자유롭게 허용하되 스냅샷/검토 필드는 잠그고, admin의 update 규칙은
  반대로 스냅샷/상태/검토 필드만 바꾸고 draft 필드(작가가 쓴 내용 자체)는
  안 건드린다 — 그래서 admin 규칙은 각 draft 필드가 "그대로인지"를 일일이
  확인하는 긴 동등 비교 체인이 된다. `effectivePrice()`도 이 이유로 top-level이
  아니라 반드시 `liveMetadata`만 읽는다(안 그러면 작가가 승인 없이 즉시 가격을
  바꿀 수 있게 된다). `nodes`의 "검토 필드"에는 `status`/`pendingAction`/
  `liveSnapshot`뿐 아니라 `rejectionReason`도 포함된다 — 콘텐츠가 아니라
  검토 상태의 일부라서, admin 규칙의 동등 비교 체인(콘텐츠 필드만 나열)에
  안 들어가고 자유롭게 바뀐다. 작가 본인 규칙도 이 필드를 안 잠근다 —
  재제출 시 작가 자신의 쓰기로 이 필드를 지워야 하기 때문이다
  (`requestApprovalForNode`).
- **서버 전용 필드** — `viewCount`(정확히 +1만), `avgRating`/`reviewCount`(Cloud
  Function만), `wallet/current.balance`와 `wallet/current/transactions`(Cloud
  Function만, Admin SDK가 규칙 자체를 우회) 같은 필드는 클라이언트 write 규칙이
  아예 없거나 매우 좁게 좁혀 둔다 — "write 규칙이 없다 = 기본값(거부)이 곧
  서버 전용"이라는 걸 규칙 곳곳의 주석이 명시적으로 설명해 둔다. `refundCoinCharge`/
  `computeDailyRevenueSnapshot`도 같은 패턴이다.
- **admin 전용 collection-group 읽기** — `{path=**}/transactions`(admin
  결제·정산 화면)는 `{path=**}/nodes`와 정확히 같은 이유로 존재한다: 중첩
  `match`는 uid/packId를 아는 직접 접근에만 적용되고, 여러 유저/팩을 가로질러
  훑는 `collectionGroup()` 쿼리는 별도의 `{path=**}` 규칙이 있어야 허용된다.
  다만 `nodes`(로그인만 하면 누구나 읽는다)와 달리 `transactions`는 admin만
  읽을 수 있다 — 결제 데이터라 더 좁힌다.
- `storyPacks/{packId}/nodes`는 작가의 저장(`AdminStoryRepository.saveNode`,
  content 필드만 바뀜)과 admin의 승인/반려(`approveNode`/`rejectNode`,
  status/liveSnapshot/pendingAction만 바뀜)가 같은 문서에 대해 서로 다른 필드를
  바꾸는 두 가지 쓰기 모양이라, 규칙도 그 둘을 구분해서 허용한다. **작가 자격
  승인(`authorApplications`)과 콘텐츠 승인(`storyPacks/.../nodes`)은 완전히 별개의
  검토 흐름이라 규칙에서도 서로 겹치지 않는다** — 작가 자격을 얻는다고 콘텐츠가
  자동으로 라이브에 반영되지 않는다.

`firestore.rules`가 다루는 컬렉션(2025년 기준): `users/{uid}`(+ `save`/`readerPrefs`/
`readingProgress`/`wallet`+`transactions`), `{path=**}/transactions`
(collection-group 전용, admin만), `authorApplications`, `genres`,
`homeBanners`, `homeEvents`, `pointPackages`, `packBundles`, `notices`, `storyPacks`(+ `nodes`/`reviews`/`comments`+`likes`),
`{path=**}/nodes`(collection-group 전용), `images`, `sfxLibrary`, `bgmLibrary`,
`ttsVoiceCache`(author/admin 읽기 전용, 클라이언트 write 없음), `writerNotices`,
`rankingSnapshots`, `revenueSnapshots`(admin만).

Storage 쪽 `admin/story_images/**`도 같은 role 모델을 따라야 한다. Storage 규칙에서
Firestore 문서를 직접 읽을 수 있는 `firestore.get()`(Cross-Service Rules)을 써서
동일하게 맞춘다 — Firestore 쪽 `firestore.rules`와 달리 **이 저장소에는 `storage.rules`
파일이 아예 없다**(콘솔에서만 손으로 관리된다). 그래서 위 Firestore 규칙 절과
달리 여기는 "파일을 직접 열어 보라"고 안내할 대상 자체가 없다 — 아래 스니펫이
지금 콘솔에 실제로 적용된 내용과 같다는 보장이 없으니, 확인이 필요하면 Firebase
콘솔의 Storage → Rules 탭을 직접 봐야 한다. Storage 쪽에 새 업로드 경로/역할
조건을 추가하면 콘솔에 적용한 뒤 이 스니펫도 같이 고칠 것(하지만 여기가 진실의
원천은 아니라는 점을 항상 기억할 것):

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /admin/story_images/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role in ['author', 'admin'];
    }

    // admin/story_sfx/{sfxId}.mp3 — story_images와 같은 role 모델.
    match /admin/story_sfx/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role in ['author', 'admin'];
    }

    // admin/home_banners/{bannerId}.jpg — "홈 배너 관리"(HomeBannerManagementSection)
    // 업로드 경로. story_images/story_sfx와 달리 author는 이 화면에 아예
    // 접근할 수 없다(AdminDashboardPage 전체가 admin 전용 게이트) — 그래서
    // write를 admin으로만 좁힌다.
    match /admin/home_banners/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }

    // admin/home_events/{eventId}.jpg — "홈 이벤트 관리"(HomeEventManagementSection)
    // 업로드 경로. home_banners와 완전히 같은 이유로 admin 전용 게이트 뒤에
    // 있으니 write도 admin으로만 좁힌다. ⚠️ 이 경로는 처음 배포 때 이 콘솔
    // 규칙을 추가하지 않은 채 기능만 나가서 업로드가 403(storage/unauthorized)로
    // 막힌 적이 있다 — Storage 쪽에 새 업로드 경로를 추가할 때마다 "코드가
    // 참조하는 경로 = 콘솔에 규칙이 있는 경로"인지 반드시 짝을 맞춰 확인할 것.
    match /admin/home_events/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }

    // admin/story_bgm/{bgmId}.mp3 — "배경음악 라이브러리"(BgmLibraryTab) 업로드
    // 경로, story_images/story_sfx와 같은 role 모델(author/admin 둘 다 write —
    // 이 탭은 작가 도구 전체에 있어서 author도 접근한다, home_banners/
    // home_events처럼 admin 전용 게이트 뒤가 아니다). ⚠️ 이 규칙을 콘솔에 직접
    // 추가해야 한다 — 이 저장소에는 storage.rules 파일이 없어서
    // `firebase deploy --only storage`로 못 밀어 넣는다(Firebase Console →
    // Storage → Rules에서 손으로 붙여넣을 것). 코드가 참조하는 경로
    // (lib/admin/data/admin_bgm_repository.dart) = 콘솔에 규칙이 있는 경로인지
    // 반드시 짝을 맞춰 확인할 것 — home_events 때 이 규칙을 빠뜨려서 업로드가
    // 403(storage/unauthorized)으로 막힌 적이 있다.
    match /admin/story_bgm/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role in ['author', 'admin'];
    }

    // admin/story_tts/{packId}/{nodeId}.mp3 또는 .wav — onNodeApprovedGenerateTts/
    // synthesizeNodeTts(둘 다 Cloud Function)가 생성한 Typecast 내레이션
    // 오디오 캐시(다중 보이스 노드는 .wav, 그 외엔 .mp3 — FIRESTORE_SCHEMA.md의
    // "세그먼트 병합" 절 참고). **위 셋과 role 모델이 다르다** — author/admin
    // 누구도 여기에 직접 업로드하지 않는다(작가 도구에 업로드 UI 자체가
    // 없다). 오직 Cloud Function이 Admin SDK로만 쓴다 — 그래서
    // write를 아예 막는다. read는 리더가 재생 URL을 그대로 트는 것뿐이라
    // 로그인 여부만 확인한다(story_images/story_sfx/story_bgm과 같은 read
    // 조건). ⚠️ 이 저장소가 반복적으로 겪은 "새 업로드 경로에 콘솔 규칙
    // 추가를 빠뜨려 403" 버그(story_bgm/home_events 주석 참고) 재발 방지
    // 목적으로 명시적으로 남겨 둔다 — 이 경로도 콘솔에 직접 붙여넣어야 한다.
    match /admin/story_tts/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if false;
    }

    // admin/story_tts_preview/{packId}/{nodeId}.* — previewNodeTts(Cloud
    // Function)가 만드는 "미리듣기" 잠정 캐시(요청 사양 Part 1-1). 위
    // admin/story_tts와 똑같은 role 모델(Admin SDK만 쓴다, write 금지) —
    // 저자가 임시저장도 안 한 초안으로 몇 번이고 다시 눌러 들어볼 수 있는
    // 파일이라 별도 하위 경로로 분리해 뒀다(리더용 admin/story_tts와 절대
    // 안 섞이게).
    match /admin/story_tts_preview/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```
