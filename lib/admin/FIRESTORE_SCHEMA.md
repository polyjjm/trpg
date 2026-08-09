# 작가 편집기 Firestore 스키마

`lib/admin/`(작가 편집기, `lib/main_admin.dart`)이 읽고 쓰는 컬렉션 문서다. 게임 앱
(`lib/main.dart`, `lib/features/**`)은 아직 이 컬렉션들을 읽지 않는다 — 지금은
편집기 쪽 워크플로만 동작하고, 게임이 실제로 이 데이터를 소비하도록 바꾸는 건
CLAUDE.md에서 말하는 "이후 데이터 마이그레이션 단계"의 몫이다.

## storyPacks/{packId}

```
title: string
```

지금은 title만 쓴다. 게임 쪽 `StoryPack`(lib/features/catalog/models/story_pack.dart)과
이름을 맞춰, 나중에 `price`(int, 원 단위) / `coverImage`(images/{imageId} 참조) /
`authorName` / `format` 같은 필드를 추가할 여지를 남겨 둔다.

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

## 승인 대기함 조회 (collection group)

승인 대기함 탭은 모든 스토리팩을 통틀어 `pendingAction`이 설정된 노드를
`collectionGroup('nodes').where('pendingAction', whereIn: ['create','edit','delete'])`로
조회한다. Firestore 콘솔에서 이 컬렉션 그룹 쿼리용 복합 색인을 처음 한 번
만들어야 한다 — 쿼리를 처음 실행하면 콘솔 링크가 포함된 에러가 뜨고, 그 링크를
따라가면 바로 만들 수 있다.

## 보안 규칙 (아직 이 저장소에 firestore.rules로 관리되지 않음)

지금 접근 제어는 **클라이언트 쪽 이메일 화이트리스트**(`lib/admin/data/admin_allowlist.dart`)뿐이다
— 편집기 UI는 허용된 계정만 접근하게 막지만, Firestore 보안 규칙이 서버 쪽에서
같은 제한을 걸어 두지 않으면 로그인한 사용자라면 누구든 Firestore SDK로 직접
이 컬렉션들을 읽고 쓸 수 있다. 최소한 아래 정도의 규칙을 Firebase 콘솔(또는
`firestore.rules` 파일을 만들어 `firebase deploy --only firestore:rules`)로
적용해야 한다. 화이트리스트가 두 곳(Dart 상수 + 규칙)에 중복되는 게 지금 단계의
한계이고, 나중에 역할 기반 권한으로 옮겨갈 때 함께 정리한다.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isAdmin() {
      return request.auth != null && request.auth.token.email in [
        'wnwhd788@gmail.com'
      ];
    }

    match /storyPacks/{packId} {
      allow read, write: if isAdmin();
      match /nodes/{nodeId} {
        allow read, write: if isAdmin();
      }
    }

    match /images/{imageId} {
      allow read, write: if isAdmin();
    }

    match /writerNotices/{noticeId} {
      allow read, write: if isAdmin();
    }

    // 기존 게임 세이브 데이터(users/{uid}/save/current)는 그대로 유지 —
    // 여기서 건드리지 않는다. 실제 규칙 파일을 만들 때 병합해서 쓸 것.
  }
}
```

Storage 쪽도 `admin/story_images/**` 경로에 같은 화이트리스트 규칙이 필요하다.
