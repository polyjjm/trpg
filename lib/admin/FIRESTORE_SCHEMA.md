# 작가 편집기 Firestore 스키마

`lib/admin/`(작가 편집기, `lib/main_admin.dart`)이 읽고 쓰는 컬렉션 문서다. 게임 앱
(`lib/main.dart`, `lib/features/**`)은 아직 이 컬렉션들을 읽지 않는다 — 지금은
편집기 쪽 워크플로만 동작하고, 게임이 실제로 이 데이터를 소비하도록 바꾸는 건
CLAUDE.md에서 말하는 "이후 데이터 마이그레이션 단계"의 몫이다.

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
// title/genres/description/coverImageId를 바꿀 때마다 반복되는 게이트.
// 개별 노드 콘텐츠 승인(아래 nodes의 status/pendingAction/liveSnapshot)과는
// 완전히 별개의 흐름이다.
pendingMetadataAction: 'edit' | null
liveMetadata: { title, genres, description, coverImageId } | null
  // 마지막으로 승인된 메타데이터 스냅샷 — 독자 앱은 이 값을 읽는다(위 top-level
  // title/genres/description/coverImageId가 아니라). 연재 시작 승인 전까지는 null.
metadataSubmittedAt: timestamp?
metadataReviewedBy: string?
metadataReviewedAt: timestamp?
metadataRejectionReason: string?
```

`authorId`/`authorName`/`type`/`genres`/`description`/`coverImageId`/승인 관련
필드는 다중 작가 구조로 가면서 새로 추가되는 필드다. 기존에 만들어진 스토리팩
문서(예: 좀비 이야기 팩)는 이 필드가 없으므로, 읽을 때 없음을 각각 "소유자
미지정"/""/`'interactive'`/`[]`/""/null/`'draft'`로 취급해야 하고, 실제로는 한 번
수동 백필이 필요하다(백필하지 않으면 `serializationStatus`가 `'draft'`로
읽혀 독자 라이브러리에도 계속 보이지 않는다).

독자 라이브러리 노출 조건은 `serializationStatus == 'approved'` **그리고**
발행된(`status == 'published'`) 노드가 최소 1개 있어야 한다. `requestSerialization()`이
이미 발행된 노드를 요구하기 때문에 승인 시점엔 이 조건이 구조적으로 항상
참이지만, 나중에 그 노드가 반려/삭제되어 발행된 노드가 하나도 안 남는 엣지
케이스에 대비한 방어적 이중 체크로 유지한다. 리더 쪽 `StoryPackRepository`
(lib/features/catalog/data/story_pack_repository.dart)가 이 AND 조건을
클라이언트에서 조합한다.

게임 쪽 `StoryPack`(lib/features/catalog/models/story_pack.dart)과 이름을 맞춰,
나중에 `price`(int, 원 단위) 필드를 추가할 여지도 남겨 둔다.

## storyPacks/{packId}/nodes/{nodeId}

```
day: int
title: string
body: string
bgImageId: string?           // images/{imageId} 참조. 선택 안 하면 null.
choices: array<Choice>
status: 'draft' | 'published'
pendingAction: 'create' | 'edit' | 'delete' | null
liveSnapshot: { title, day, body, bgImageId, choices } | null
```

- `status`/`pendingAction`/`liveSnapshot`은 초안 → 승인 대기 → 발행(연재중)
  흐름을 나타낸다. `liveSnapshot`은 마지막으로 **승인된** 콘텐츠 스냅샷이고,
  최상단 필드(title/day/body/...)는 지금 편집 중인(승인 전일 수도 있는) 내용이다
  — 즉 문서 하나가 "지금 보이는 버전"과 "다음에 반영될 버전"을 동시에 들고 있다.
- `liveSnapshot == null`이면 한 번도 승인된 적 없는 순수 신규 노드라는 뜻이고,
  편집기는 이걸로 "신규 등록 요청"과 "수정 요청"을 구분한다.
- 노드 문서 id는 스토리 그래프 안에서 다른 노드가 가리키는 대상 id이기도 하다
  (`choices[].target`, `winNode`, `loseNode`, `escapeNode` 등) — 편집기는 이미
  발행된 적 있는 노드의 id를 그 자리에서 바꾸지 못하게 막는다(Firestore 문서
  id는 rename이 없어서, 바꾸려면 새 문서 생성 + 기존 문서 삭제 + 그 노드를
  가리키던 다른 모든 선택지 갱신이 필요한데 지금 단계에서는 다루지 않는다).

### Choice (choices 배열의 원소, embedded map)

모든 타입이 같은 필드 모양을 공유하는 평평한(flat) 구조다 — 선택지 타입을
바꿔도 이전에 입력해 둔 다른 타입 필드 값이 사라지지 않는다.

```
text: string
type: 'move' | 'battle' | 'encounter' | 'merchant' | 'item'
imageId: string?             // 선택지 전용 이미지. null이면 노드 배경 사용.

// type === 'move'
mode: 'fixed' | 'random'
target: string                // mode === 'fixed'일 때 이동할 노드 id
random: array<{ node: string, pct: int }>   // mode === 'random'일 때 가중치 후보들. pct 합은 100.

// type === 'battle'
battleId: string
winNode: string
loseNode: string
escapeNode: string

// type === 'encounter'
encounterId: string
// winNode(극복 시) / escapeNode(탈출 시)는 위 필드를 재사용

// type === 'merchant'
// target(상인 화면 종료 후 이동할 노드)을 재사용

// type === 'item'
itemId: string
itemCount: int
// target(획득 후 이동할 노드)을 재사용
```

`type === 'move' && mode === 'random'`인 선택지는 `random` 배열의 `pct` 합이
100이어야 저장할 수 있다(편집기가 저장 시점에 검증한다).

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

작가가 자기 스토리팩에 올리는 변경사항 공지. 게임 앱 라이브러리/상세 화면의
`Notice`(lib/features/catalog/models/notice.dart)와 같은 모양이라, 나중에
게임이 이 컬렉션을 직접 읽게 되면 `packId`로 걸러서 그대로 매핑할 수 있다.

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
- `storyPacks`: `AdminStoryRepository.watchPacksForAuthor(authorId)` — `where('authorId', isEqualTo: authorId).orderBy('title')`

`fieldOverrides`에는 별도로 하나 더 있다 — `nodes` 컬렉션의 `pendingAction`
필드를 `COLLECTION_GROUP` 범위에서도 쿼리할 수 있게 하는 오버라이드다.
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

## 보안 규칙 (아직 이 저장소에 firestore.rules로 관리되지 않음)

클라이언트 쪽 접근 제어는 `users/{uid}.role`을 읽어 판단한다
(`lib/core/user/user_profile_repository.dart`, `lib/admin/pages/admin_gate_page.dart`)
— 예전의 이메일 화이트리스트(`lib/admin/data/admin_allowlist.dart`)는 삭제됐다.
아래는 그 role 모델을 그대로 서버 쪽에도 적용하는 규칙이다. Firebase 콘솔(또는
`firestore.rules` 파일을 만들어 `firebase deploy --only firestore:rules`)로
적용해야 한다 — 그 전까지는 로그인한 사용자라면 누구든 Firestore SDK로 이
컬렉션들을 직접 읽고 쓸 수 있다.

각 컬렉션이 실제 코드의 어떤 쓰기 패턴을 허용하는지 주석에 남겨 뒀다 — 특히
`storyPacks/{packId}/nodes`는 작가의 저장(`AdminStoryRepository.saveNode`,
content 필드만 바뀜)과 admin의 승인/반려(`approveNode`/`rejectNode`,
status/liveSnapshot/pendingAction만 바뀜)가 같은 문서에 대해 서로 다른 필드를
바꾸는 두 가지 쓰기 모양이라, 규칙도 그 둘을 구분해서 허용한다. **작가 자격
승인(`authorApplications`)과 콘텐츠 승인(`storyPacks/.../nodes`)은 완전히 별개의
검토 흐름이라 규칙에서도 서로 겹치지 않는다** — 작가 자격을 얻는다고 콘텐츠가
자동으로 라이브에 반영되지 않는다.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() {
      return request.auth != null;
    }

    function myUid() {
      return request.auth.uid;
    }

    function myRole() {
      return isSignedIn() && exists(/databases/$(database)/documents/users/$(myUid()))
        ? get(/databases/$(database)/documents/users/$(myUid())).data.role
        : 'reader';
    }

    function isAdmin() {
      return myRole() == 'admin';
    }

    function isAuthorOrAdmin() {
      return myRole() == 'author' || myRole() == 'admin';
    }

    function isPackOwnedBy(packId) {
      return isSignedIn()
        && get(/databases/$(database)/documents/storyPacks/$(packId)).data.authorId == myUid();
    }

    // 기존 게임 세이브 데이터 — 본인만 읽고 쓴다.
    match /users/{userId}/save/{saveDocId} {
      allow read, write: if isSignedIn() && myUid() == userId;
    }

    // users/{uid} — 신원/권한 문서. role/authorApplicationStatus는 본인이 함부로
    // 못 바꾼다(승인/반려 흐름을 통해서만 바뀐다).
    match /users/{userId} {
      allow read: if isSignedIn() && (myUid() == userId || isAdmin());

      // 최초 로그인(ensureProfile) — 본인이 자기 문서를 reader로 처음 만드는 것만.
      allow create: if isSignedIn() && myUid() == userId
        && request.resource.data.role == 'reader'
        && request.resource.data.authorApplicationStatus == 'none';

      // admin은 승인/반려 처리를 위해 role/authorApplicationStatus를 자유롭게 갱신.
      allow update: if isAdmin();

      // 본인 갱신은 신청 제출(submitApplication)뿐 — role은 절대 못 바꾸고,
      // authorApplicationStatus는 none/rejected → pending으로만 바뀔 수 있다.
      allow update: if isSignedIn() && myUid() == userId
        && request.resource.data.role == resource.data.role
        && request.resource.data.displayName == resource.data.displayName
        && request.resource.data.email == resource.data.email
        && resource.data.authorApplicationStatus in ['none', 'rejected']
        && request.resource.data.authorApplicationStatus == 'pending';
    }

    // authorApplications/{uid} — 문서 id == 신청자 uid.
    match /authorApplications/{applicantId} {
      allow read: if isSignedIn() && (myUid() == applicantId || isAdmin());

      // 신규 제출/반려 후 재신청 — 본인만, 항상 pending으로, 검토 필드는 비운 채로.
      allow create, update: if isSignedIn() && myUid() == applicantId
        && request.resource.data.uid == applicantId
        && request.resource.data.status == 'pending'
        && request.resource.data.reviewedBy == null
        && request.resource.data.reviewedAt == null
        && request.resource.data.rejectionReason == null;

      // 승인/반려 — admin만, 신청 내용 자체(uid/displayName/bio/portfolioLinks/
      // submittedAt)는 건드리지 않는다. 점(.) 표기 대신 get(key, null)을 쓴다 —
      // 필드가 아예 없는 문서(예: 콘솔에서 손으로 만든 테스트 문서)에 점 표기로
      // 접근하면 "속성을 찾을 수 없음" 에러로 요청 전체가 거부된다.
      allow update: if isAdmin()
        && request.resource.data.get('uid', null) == resource.data.get('uid', null)
        && request.resource.data.get('displayName', null) == resource.data.get('displayName', null)
        && request.resource.data.get('bio', null) == resource.data.get('bio', null)
        && request.resource.data.get('portfolioLinks', null) == resource.data.get('portfolioLinks', null)
        && request.resource.data.get('submittedAt', null) == resource.data.get('submittedAt', null);
    }

    // genres/{genreId} — admin이 관리하는 참고 데이터. 앱 재배포 없이 admin이
    // 콘솔이나(나중에 생길) 관리 UI로 추가/수정한다.
    match /genres/{genreId} {
      allow read: if isSignedIn();
      allow write: if isAdmin();
    }

    match /storyPacks/{packId} {
      allow read: if isSignedIn();

      // 생성: author/admin이 자기 자신을 authorId로 지정해서만. 항상 draft로
      // 시작한다 — 연재 시작 승인을 직접 approved로 건너뛸 수 없다.
      allow create: if isAuthorOrAdmin()
        && request.resource.data.authorId == myUid()
        && request.resource.data.serializationStatus == 'draft';

      // 작가 본인의 팩 설정 저장/승인 요청(saveDraftPackSettings,
      // requestSerialization, requestMetadataEdit) — liveMetadata와 검토
      // 관련 필드(reviewedBy/reviewedAt)는 이 경로로 절대 못 바꾼다. 그 필드는
      // 오직 admin의 승인/반려에서만 바뀐다. serializationStatus는 자기 자신을
      // 유지하거나 'pending'으로 넘어가는 것만 허용한다 — 'approved'/'rejected'로
      // 직접 바꿀 수는 없다(그건 아래 admin 규칙의 몫). pendingMetadataAction의
      // 정확한 전이(null -> 'edit'만 허용)까지는 강제하지 않는다 — 작가가 자기
      // 팩의 pending 플래그를 스스로 지우는 것 자체는 검토를 우회하는 게
      // 아니라서(라이브 상태엔 영향 없음) 규칙을 단순하게 유지하는 쪽을 택했다.
      allow update: if isSignedIn() && resource.data.authorId == myUid()
        && request.resource.data.authorId == resource.data.authorId
        && request.resource.data.type == resource.data.type
        && request.resource.data.get('authorName', null) == resource.data.get('authorName', null)
        && (request.resource.data.serializationStatus == resource.data.serializationStatus
            || request.resource.data.serializationStatus == 'pending')
        && request.resource.data.get('liveMetadata', null) == resource.data.get('liveMetadata', null)
        && request.resource.data.get('serializationReviewedBy', null) == resource.data.get('serializationReviewedBy', null)
        && request.resource.data.get('serializationReviewedAt', null) == resource.data.get('serializationReviewedAt', null)
        && request.resource.data.get('metadataReviewedBy', null) == resource.data.get('metadataReviewedBy', null)
        && request.resource.data.get('metadataReviewedAt', null) == resource.data.get('metadataReviewedAt', null);

      // admin의 연재 시작/메타데이터 승인·반려(approveSerialization/
      // rejectSerialization/approveMetadataEdit/rejectMetadataEdit) — 이 네
      // 액션 전부 상태/검토/liveMetadata 필드만 바꾸고, 작가가 쓴
      // title/genres/description/coverImageId 자체는 건드리지 않는다(반려 시
      // 작가가 재신청 때 그대로 다시 손볼 수 있어야 한다).
      allow update: if isAdmin()
        && request.resource.data.title == resource.data.title
        && request.resource.data.genres == resource.data.genres
        && request.resource.data.description == resource.data.description
        && request.resource.data.get('coverImageId', null) == resource.data.get('coverImageId', null)
        && request.resource.data.authorId == resource.data.authorId;

      allow delete: if isAdmin();

      match /nodes/{nodeId} {
        allow read: if isSignedIn();

        // 작가 자신의 저장(임시저장/승인요청 제출, saveNode) — status/liveSnapshot은
        // 절대 못 건드린다. 이 두 필드는 오직 admin의 승인/반려에서만 바뀐다.
        allow create: if (isPackOwnedBy(packId) || isAdmin())
          && request.resource.data.status == 'draft'
          && request.resource.data.liveSnapshot == null
          && request.resource.data.pendingAction in ['create', null];

        allow update: if (isPackOwnedBy(packId) || isAdmin())
          && request.resource.data.status == resource.data.status
          && request.resource.data.liveSnapshot == resource.data.liveSnapshot;

        // admin의 승인/반려(approveNode/rejectNode) — status/liveSnapshot/
        // pendingAction만 바뀌고 콘텐츠 필드는 그대로 둔다.
        allow update: if isAdmin()
          && request.resource.data.title == resource.data.title
          && request.resource.data.day == resource.data.day
          && request.resource.data.body == resource.data.body
          && request.resource.data.bgImageId == resource.data.bgImageId
          && request.resource.data.choices == resource.data.choices;

        // 삭제: 작가는 한 번도 발행된 적 없는(liveSnapshot == null) 자기 노드만
        // 즉시 지울 수 있다(deleteNodeDoc). 이미 발행된 노드의 삭제는 admin이
        // 삭제 요청을 승인(approveNode)하는 경로로만 이뤄진다.
        allow delete: if (isPackOwnedBy(packId) && resource.data.liveSnapshot == null) || isAdmin();
      }
    }

    // storyPacks/*/nodes 컬렉션 그룹 조회 전용 규칙 — admin 쪽
    // AdminStoryRepository.watchPendingNodes(collectionGroup('nodes').where
    // ('pendingAction', ...))뿐 아니라, 리더 쪽 StoryPackRepository.
    // watchVisiblePacks()가 "발행된 노드가 있는 팩" 집합을 구하려고 쓰는
    // collectionGroup('nodes').where('status', '==', 'published')도 이 규칙으로
    // 커버된다(firestore.indexes.json에 status 필드의 COLLECTION_GROUP
    // fieldOverrides도 같이 추가했다 — pendingAction 때와 같은 이유).
    //
    // 위 중첩 match(/storyPacks/{packId}/nodes/{nodeId})는 packId를 아는 직접
    // 접근(문서 참조, 특정 팩으로 좁힌 구독)에만 적용되고, collectionGroup()처럼
    // 상위 경로를 모르는 채로 여러 팩을 가로질러 조회하는 쿼리에는 적용되지
    // 않는다 — Firestore는 collection group 쿼리를 오직 {path=**} 형태의
    // 재귀 와일드카드 규칙으로만 허용한다. 이 규칙이 없으면 승인 대기함 탭이
    // permission-denied로 즉시 실패한다(실제로 겪은 버그).
    //
    // 읽기 전용이다 — 쓰기(saveNode/approveNode/rejectNode/deleteNodeDoc)는
    // 전부 직접 문서 참조로만 이뤄지므로 위 중첩 match의 쓰기 규칙만으로 충분하다.
    match /{path=**}/nodes/{nodeId} {
      allow read: if isSignedIn();
    }

    // images/{imageId} — 색인 문서. 실제 파일은 Storage(아래 별도 규칙)에 있다.
    // 업로더를 추적하는 필드가 아직 없어 모든 author/admin이 공유하는
    // 라이브러리다 — uploaderId가 생기면 그때 좁힐 수 있다.
    match /images/{imageId} {
      allow read: if isSignedIn();
      allow create, delete: if isAuthorOrAdmin();
    }

    // sfxLibrary/{sfxId} — images와 같은 공유 색인 문서. uploadedBy가 있지만
    // images의 uploaderId 부재와 같은 이유로 아직 본인 것만으로 좁히지 않는다
    // — 모든 author/admin이 공유하는 라이브러리다. 카테고리 변경(update)도
    // images와 마찬가지로 author/admin 누구나 할 수 있다.
    match /sfxLibrary/{sfxId} {
      allow read: if isSignedIn();
      allow create, update, delete: if isAuthorOrAdmin();
    }

    // writerNotices/{noticeId} — packId로 소유 스토리팩을 가리킨다.
    match /writerNotices/{noticeId} {
      allow read: if isSignedIn();
      allow create: if isAdmin() || isPackOwnedBy(request.resource.data.packId);
      allow delete: if isAdmin() || isPackOwnedBy(resource.data.packId);
    }
  }
}
```

Storage 쪽 `admin/story_images/**`도 같은 role 모델을 따라야 한다. Storage 규칙에서
Firestore 문서를 직접 읽을 수 있는 `firestore.get()`(Cross-Service Rules)을 써서
동일하게 맞춘다:

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
  }
}
```
