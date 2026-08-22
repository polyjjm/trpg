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
// discountEndAt을 바꿀 때마다 반복되는 게이트. 개별 노드 콘텐츠 승인(아래
// nodes의 status/pendingAction/liveSnapshot)과는 완전히 별개의 흐름이다.
// serializationStatus가 아직 'approved'가 아닌 팩은 애초에 pendingMetadataAction을
// 'edit'로 만들 수 없다(firestore.rules가 강제 — 연재 시작 승인을 한 번도
// 못 받은 draft 팩은 이 2단계 게이트 자체를 탈 이유가 없고, draft 필드는
// saveDraftPackSettings로 승인 없이 자유롭게 고치면 된다).
pendingMetadataAction: 'edit' | null
liveMetadata: { title, genres, description, coverImageId, price, salePrice,
                discountStartAt, discountEndAt } | null
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
blocks: array<{ type: 'paragraph', text: string }>
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
effects: { blackout, shake, sfx, flash, haptic } | 없음(전부 꺼짐 기본값)
                                   // 아래 "effects" 절 참고. 필드 자체가 없는
                                   // 기존 노드도 전부 꺼진 기본값으로 읽힌다.
status: 'draft' | 'published'
pendingAction: 'create' | 'edit' | 'delete' | null
liveSnapshot: { order, blocks, backgroundImage, backgroundAppliesForward,
                choices, nextNodeId, effects } | null
```

- `status`/`pendingAction`/`liveSnapshot`은 초안 → 승인 대기 → 발행(연재중)
  흐름을 나타낸다. `liveSnapshot`은 마지막으로 **승인된** 콘텐츠 스냅샷이고,
  최상단 필드(order/blocks/...)는 지금 편집 중인(승인 전일 수도 있는) 내용이다
  — 즉 문서 하나가 "지금 보이는 버전"과 "다음에 반영될 버전"을 동시에 들고 있다.
- `liveSnapshot == null`이면 한 번도 승인된 적 없는 순수 신규 노드라는 뜻이고,
  편집기는 이걸로 "신규 등록 요청"과 "수정 요청"을 구분한다.
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
실제로 재생) 둘 다 같은 필드 모양의 별개 클래스다.

```
blackout: { enabled: bool, durationPreset: '0.5s' | '1s' | '2s' }
shake: { enabled: bool, intensityPreset: '약하게' | '보통' | '강하게' }
sfx: { enabled: bool, sfxId: string? }        // sfxLibrary/{sfxId} 참조.
flash: { enabled: bool, colorPreset: '빨강(피격)' | '하양(섬광)' | '파랑(냉기)',
         durationPreset: '짧게' | '보통' | '길게' }
haptic: { enabled: bool, durationPreset: '짧게' | '길게' }
```

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
ttsEnabled: bool
bgmEnabled: bool
lastNoticeReadAt: timestamp?     // 공지사항 탭을 마지막으로 연 시각.
```

`SceneFrame` 하단 설정 시트(폰트/애니메이션/TTS/BGM 토글)가 쓰는 문서다.
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

## 복합 색인이 필요한 쿼리 (`firestore.indexes.json`)

동등 필터(`where(field, isEqualTo: ...)`)와 다른 필드의 `orderBy`를 함께 쓰는
쿼리는 Firestore 자동 단일 필드 색인만으로는 안 되고 복합 색인이 필요하다.
지금 코드베이스에서 여기 해당하는 쿼리 둘을 저장소 루트의 `firestore.indexes.json`에
정의해 뒀다:

- `genres`: `GenreRepository.watchActiveGenres()` — `where('active', isEqualTo: true).orderBy('sortOrder')`
- `packBundles`: `PackBundleRepository.watchActiveBundles()` — `where('active', isEqualTo: true).orderBy('sortOrder')`
  (genres/homeBanners/pointPackages와 같은 모양의 색인)
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
  바꿀 수 있게 된다).
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
`homeBanners`, `pointPackages`, `packBundles`, `notices`, `storyPacks`(+ `nodes`/`reviews`/`comments`+`likes`),
`{path=**}/nodes`(collection-group 전용), `images`, `sfxLibrary`, `writerNotices`,
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
  }
}
```
