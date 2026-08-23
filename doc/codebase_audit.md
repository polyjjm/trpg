# 코드베이스 감사 (2026-08-23)

죽은 파일 정리(Part 1) 작업 중 코드를 훑으면서 발견한 것들. **이 문서를 쓰면서
아무것도 고치지 않았다** — 다음에 손댈 순서를 정하기 위한 목록이다.

각 항목은 심각도 순으로 정렬돼 있다(파일 위치 순서가 아니다).

> **2026-08-24 갱신** — Critical 3건(#1/#2/#3)에 대한 서버 측 수정이
> 들어갔다. 각 항목 제목에 `[해결됨]` / `[부분 해결]` 표시를 달고, 무엇이
> 닫혔고 무엇이 남았는지 항목 안에 덧붙였다. **기록 보존을 위해 원래 내용은
> 지우지 않았다.** 새로 발견된 항목은 맨 아래 "2026-08-24 추가 발견"에 있다.

> **firestore.rules 관련 주의**: CLAUDE.md에 적힌 대로, 저장소의
> `firestore.rules`는 **실제 배포된 규칙과 이미 어긋나 있다**(콘솔에서 손으로
> 관리 중). 아래 규칙 관련 지적은 전부 *저장소 파일 기준*이다 — 손대기 전에
> Firebase 콘솔에서 현재 배포본을 먼저 확인할 것. 다만 파일과 배포본 중
> 어느 쪽이든 이 문제가 남아 있으면 그대로 유효한 지적이다.

---

## 2a. 버그 / 리스크

### 🔴 Critical

#### 1. 유료 팩 소유권(`ownedPackIds`)을 클라이언트가 직접 쓸 수 있다 — ✅ **[해결됨 2026-08-24]**

> **해결**: `firestore.rules`의 `users/{userId}/save/{saveDocId}`를
> `allow read, write` 하나에서 read/create/update/delete 네 갈래로 쪼개고,
> update는 `affectedKeys().hasAny(['ownedPackIds'])`가 거짓일 때만,
> create는 `ownedPackIds`가 빈 배열로 도착할 때만 허용한다. delete는 금지.
> 나머지 게임 상태 저장은 그대로 동작한다(전체 `.set()`이라도 값이 같으면
> diff에 안 잡힌다). `purchasePack`/`purchaseBundle`은 Admin SDK로 쓰므로
> 영향 없음 — 코드에서 확인함.
> 부작용: 로컬 상태가 서버보다 뒤처진 채 저장을 시도하면 이제 거부된다
> (예전엔 조용히 구매를 되돌렸다). `CloudSyncController`가 저장 실패를
> `debugPrint`로만 삼키므로 사용자에게 표시가 없다 — 아래 신규 항목 #16.


- **위치**: `firestore.rules:82-84`, `lib/core/state/game_state.dart:93`
  (`ownsPack`), `functions/src/index.ts:391` (`purchasePack`)
- **문제**:

  ```
  match /users/{userId}/save/{saveDocId} {
    allow read, write: if isSignedIn() && myUid() == userId;
  }
  ```

  `ownedPackIds`는 `GameState.toJson()`이 이 문서에 통째로 저장한다. 규칙이
  본인 쓰기를 무제한 허용하므로, 아무 로그인 계정이나 Firebase SDK로
  `users/{내uid}/save/current`에 `ownedPackIds: [...전부...]`를 한 번 쓰면
  **모든 유료 팩을 공짜로 소유**한다. `purchasePack` Cloud Function이 코인
  차감·거래기록을 서버에서 검증하는 게 전부 무의미해진다.
- **더 나쁜 점**: `firestore.rules:37-41`의 `readerOwnsPack()`이 **바로 그
  문서를 읽어서** 리뷰/댓글 작성 자격(`canReviewPack`)을 판정한다. 규칙 자신이
  사용자가 조작할 수 있는 값을 신뢰하고 있다.
- **대조**: 바로 아래 `users/{userId}/wallet/{walletDocId}`
  (`firestore.rules:106-113`)는 정확히 이 문제를 알고 있다 — `balance`는
  write 규칙을 아예 안 줘서 Cloud Function 전용으로 막아 뒀다. 같은 처리를
  `ownedPackIds`에만 안 한 것이다.
- **손볼 방향**: `save/current`에서 `ownedPackIds`를 분리해 CF 전용 문서/필드로
  옮기거나, save 문서 update 규칙에 "`ownedPackIds`는 이전 값과 같아야 한다"
  조건을 건다(`diff().affectedKeys()` 패턴, `firestore.rules:354`에 이미 있는
  방식).

#### 2. 모든 노드 본문이 로그인만 하면 읽힌다 — 페이월이 클라이언트 전용 — 🟡 **[부분 해결 2026-08-24]**

> **닫힌 것**: 한 번도 발행된 적 없는 **순수 초안**(`status == 'draft'`)이
> 독자에게 새던 경로. 직접 접근(`/storyPacks/{packId}/nodes/{nodeId}`)과
> collection-group(`{path=**}/nodes`) **양쪽** 모두 이제 작가 본인/admin이
> 아니면 `status == 'published'` 문서만 읽는다. 리더의 두 쿼리가 이미
> `status`를 제약하고 있어 그대로 통과하고, admin의 `pendingAction` 쿼리는
> `isAdmin()` 갈래로 유지된다(author까지 열지 않았다 — 남의 팩 초안을
> collectionGroup으로 훑을 수 있게 되므로).
>
> **여전히 열려 있는 것 (두 가지, 구조적)**:
> 1. **유료 팩의 발행 본문.** 홈 탭의
>    `StoryPackRepository._fetchPublishedNodeCounts()`가 모든 팩의 발행 노드를
>    collectionGroup으로 긁어 개수를 센다(`publishedNodeCount`가 `storyPacks`
>    문서에 비정규화돼 있지 않아서). 그래서 `{path=**}/nodes`는 구매 여부와
>    무관하게 열려 있어야 하고, `{path=**}`는 `packId`를 캡처할 수 없어
>    `isPackFree`/`readerOwnsPack`을 애초에 걸 수 없다.
>    **닫는 법**(클라이언트 변경 필요, 별도 작업):
>    (1) 노드 쓰기 트리거 CF로 `storyPacks.publishedNodeCount` 유지 + 기존 팩
>    백필 → (2) `_fetchPublishedNodeCounts()` 제거하고 그 필드를 읽게 변경 →
>    (3) `{path=**}/nodes`를 `isAdmin()`으로 좁힘 → (4) 미리보기는 승인 시점에
>    `previewEligible` 플래그를 찍고 리더가 2단계로(미리보기분 → 구매 후 전체)
>    나눠 읽게 함.
> 2. **이미 발행된 노드를 수정 중인 미승인 초안.** `saveNode()`가 문서 전체를
>    `.set()`하므로 초안이 같은 문서 top-level에 들어가는데 `status`는
>    `published`로 남는다. Firestore 규칙은 문서 단위 전부-아니면-전무라 필드
>    단위 투영이 불가능하다 — draft/live를 별도 문서로 쪼개야 진짜로 닫힌다.
>
> **`visitedNodeCount` 초기화로 무제한 미리보기**: 규칙에서는 손대지 않았다.
> `resetPackProgress()`가 "처음부터" 기능에서 정당하게 이 값을 0으로 만들기
> 때문에 단조 증가 제약(옵션 b)은 그 기능을 깨뜨린다. 대신 **서버가 판정을
> 내리는 곳**(TTS, #3)에서는 이 값을 아예 안 쓰도록 했다.


- **위치**: `firestore.rules:374` (`match /nodes/{nodeId}`),
  `firestore.rules:528-530` (collection group), `lib/reader/shared/paywall.dart`,
  `lib/reader/interactive/interactive_reader.dart:198`
- **문제**: 노드 읽기 규칙이 `allow read: if isSignedIn();` 하나뿐이다.
  미리보기 한도(`StoryPack.previewNodeLimit`)와 소유 확인(`GameState.ownsPack`)은
  **Flutter 위젯 안에서만** 걸린다. 로그인한 아무나 `storyPacks/{any}/nodes`를
  통째로 읽어서 유료 작품 전문을 가져갈 수 있다.
- **추가로 새는 것**: 이 규칙은 `liveSnapshot`뿐 아니라 **top-level draft
  필드까지** 전부 노출한다 — 즉 작가가 아직 승인받지 않은 초안도 아무나
  읽는다. 승인 워크플로우 전체가 읽기 측면에서는 무의미하다.
- **참고**: 규칙 파일에 이미 `readerOwnsPack()`/`effectivePrice()`/`isPackFree()`
  헬퍼가 있고 리뷰/댓글에는 적용돼 있다. 노드 읽기에만 안 걸려 있다.
  (다만 #1을 먼저 고치지 않으면 이 헬퍼를 붙여도 우회된다.)

#### 3. `synthesizeNodeTts`에 소유권 검사가 없다 — ✅ **[해결됨 2026-08-24]**

> **해결**: `canListenToNodeTts()` 헬퍼를 추가하고 Typecast 호출 **앞**에
> 게이트를 걸었다(캐시 미스 때 비용이 실제로 발생하므로 자격 없는 호출이
> 거기까지 내려오면 안 된다). 판정: 작가 본인/admin → 무료 팩 → 구매자
> (`save/current.ownedPackIds`) → 작가가 정한 `order` 기준 하위 N개 미리보기.
> 실패 시 `permission-denied`.
>
> 분기형 인터랙티브 스토리에는 단일 진행 순서가 없으므로 "앞 N개"를 **작가가
> 정한 `order`**로 정의했다 — 이미 모든 노드에 있고 admin 사이드바 드래그
> 정렬로 작가가 직접 정하는 값이라, 결과적으로 "어느 노드가 무료인가"를
> 작가가 결정하게 된다. `liveSnapshot.order`를 보고(top-level은 미승인 초안의
> 순서일 수 있다), 새 색인을 요구하지 않으려고 `status == 'published'`만
> 걸러 온 뒤 메모리에서 정렬한다.
>
> **`readingProgress.visitedNodeCount`는 판정에 쓰지 않는다** — 사용자가 직접
> 쓸 수 있는 값이라 초기화하면 무제한이 되기 때문이다.


- **위치**: `functions/src/index.ts:1271-1387`
- **문제**: `request.auth?.uid` 존재만 확인하고 끝이다. `packId`/`nodeId`를
  임의로 넘길 수 있어서, **구매하지 않은 유료 팩의 내레이션 오디오 URL**을
  누구나 받아갈 수 있다(#2의 오디오 채널 판). 캐시 미스일 때는 유료
  Typecast API를 실제로 호출하고 결과를 Storage에 올리므로 **비용까지**
  발생한다.
- **대조**: 같은 파일의 `previewNodeTts`(1401)와 `refreshTypecastVoices`(1736)는
  `isAuthorOrAdmin` 게이트가 있고, `refundCoinCharge`(633)/
  `setAuthorAccountDisabled`(1789)는 admin 게이트가 있다. 이 함수만 비어 있다.
  (독자가 직접 부르는 함수라 role 게이트는 맞지 않지만, **소유/미리보기 한도
  검사**는 있어야 한다.)

---

### 🟠 High

#### 4. 모바일에서 로그아웃이 불가능하다 — 스텁으로 남아 있음

- **위치**: `lib/features/catalog/pages/settings_tab.dart:52-56`
- **문제**:

  ```dart
  _SettingsRow(icon: Icons.logout_rounded, label: '로그아웃',
               onTap: () => _showComingSoon(context)),
  ```

  "아직 준비 중인 기능이에요" 스낵바만 뜬다. 반면 데스크톱
  (`catalog_desktop_nav_bar.dart:400`)은 `case 'signout': onSignOut();`로 실제
  로그아웃이 동작한다. **설정 탭은 모바일에만 남아 있는 탭**이므로
  (`catalog_desktop_nav_bar.dart:21-25` 주석 참고), 모바일 사용자는 앱 안에서
  계정을 바꿀 방법이 없다.
- **분류**: 이 프로젝트가 이미 두 번 겪은 "한 경로에는 있고 대응되는 다른
  경로에는 없는" 패턴 그대로다. `onSignOut` 콜백이 이미 존재하므로 고치는
  건 몇 줄이다.

#### 5. `users` 자기 갱신 규칙이 점(.) 표기를 써서 레거시 계정의 작가 신청을 막는다

- **위치**: `firestore.rules:147-153`
- **문제**:

  ```
  allow update: if isSignedIn() && myUid() == userId
    && request.resource.data.role == resource.data.role
    && request.resource.data.displayName == resource.data.displayName
    && request.resource.data.email == resource.data.email
    && resource.data.authorApplicationStatus in ['none', 'rejected']
    && ...
  ```

  `resource.data.displayName`/`email`/`authorApplicationStatus`에 점 표기로
  접근한다. 이 필드들이 **없는** 문서(이 필드가 생기기 전에 만들어진 계정,
  이메일을 안 주는 공급자로 로그인한 계정, 콘솔에서 손으로 만든 문서)에서는
  "속성을 찾을 수 없음"으로 요청 전체가 `permission-denied`가 된다 →
  **그 계정은 작가 신청을 영원히 할 수 없다**.
- **왜 확실한가**: 바로 20줄 아래 `authorApplications` 규칙
  (`firestore.rules:168-171`)에 *정확히 이 문제*를 설명하는 주석이 있고 거기선
  `get(key, null)`을 쓴다. `users` 규칙만 안 고쳐진 것이다.
- **참고**: 클라이언트 모델(`lib/core/user/user_profile.dart:44-53`)은 이
  필드들을 전부 nullable-safe하게 읽는다 — 즉 **읽기는 레거시 문서를 견디는데
  쓰기 규칙만 못 견딘다**.

#### 6. `ExternalLinks`가 아직 placeholder URL인 채로 실제 메뉴에 연결돼 있다

- **위치**: `lib/core/constants/external_links.dart:12-16`

  ```dart
  static const String authorToolUrl = 'https://TODO-author-tool-url.example/';
  static const String readerAppUrl  = 'https://TODO-reader-app-url.example/';
  ```

- **문제**: `authorToolUrl`은 데스크톱 아바타 드롭다운의 "작가 도구로"
  (`catalog_desktop_nav_bar.dart:397`)가 실제로 여는 주소다 — author/admin
  계정에게 **보이는 메뉴**이고, 누르면 존재하지 않는 도메인이 새 창으로 열린다.
  admin 쪽 "독자로 보기"도 `readerAppUrl`로 같은 상태.
- 배포 URL이 정해지기 전까지는 최소한 메뉴를 숨기거나 "준비 중" 처리를 하는
  편이 낫다.

#### 7. StreamBuilder 에러 분기가 전방위로 빠져 있다

- **문제**: 이 프로젝트는 "스트림 에러는 화면에 보여야 한다"는 명시적 관례가
  있는데(에러를 삼키면 빈 화면이 뜨고 디버깅이 지옥이 된다), 상당수
  `StreamBuilder`가 `snapshot.data ?? const []`만 쓰고 `snapshot.hasError`를
  아예 안 본다. `permission-denied`가 나도 **정상적인 빈 목록과 구분이 안 된다**.
- **`hasError` 처리가 0인 파일** (`StreamBuilder` 개수):

  | 파일 | StreamBuilder | hasError |
  |---|---|---|
  | `lib/admin/pages/admin_dashboard_page.dart` | 12 | 0 |
  | `lib/admin/pages/story_tab_view.dart` | 7 | 0 |
  | `lib/features/catalog/pages/catalog_shell_page.dart` | 3 | 0 |
  | `lib/admin/pages/coin_usage_tab.dart` | 2 | 0 |
  | `lib/admin/pages/author_tool_page.dart` | 2 | 0 |
  | `lib/features/catalog/widgets/pack_comments_section.dart` | 2 | 0 |
  | `lib/features/catalog/widgets/bundle_purchase_flow.dart` | 2 | 0 |
  | `lib/features/catalog/widgets/catalog_desktop_nav_bar.dart` | 2 | 0 |
  | `lib/admin/pages/image_library_tab.dart` | 1 | 0 |
  | `lib/admin/pages/sfx_library_tab.dart` | 1 | 0 |
  | `lib/admin/pages/notices_tab.dart` | 1 | 0 |
  | `lib/admin/pages/payment_history_tab.dart` | 1 | 0 |
  | `lib/admin/pages/pack_approvals/pack_pending_detail_pane.dart` | 1 | 0 |
  | `lib/features/catalog/pages/story_pack_detail_page.dart` | 1 | 0 |

  부분적으로만 처리하는 파일(`pack_settings_page.dart` 7개 중 1개,
  `pack_approvals_tab.dart` 4개 중 2개, `charge_page.dart` 3개 중 1개,
  `home_banner_management_section.dart`/`home_event_management_section.dart`/
  `pack_bundle_management_section.dart` 각 3개 중 1개, `approvals_tab.dart`
  3개 중 1개)도 같은 문제. 잘 돼 있는 건 `home_tab.dart`(5/5),
  `author_applications_tab.dart`(2/2) 정도다.
- **가장 위험한 한 곳** — `lib/admin/pages/story_tab_view.dart:1050`
  (`_nodeSummariesStream`): 이 스트림이 에러를 내면 사이드바가 노드 0개로
  보일 뿐 아니라, 같은 스냅샷을 원천으로 쓰는 `suggestSequentialNodeIds`가
  **"저장된 노드가 하나도 없다"**고 판단해서 "+" 버튼이 `node_1`을 제안한다 →
  이미 존재하는 노드 id와 충돌하는 문서를 만들 수 있다. 이 파일 1053-1059줄에
  "이 목록만 봐야 한다, 실제로 겪은 버그"라는 주석이 이미 붙어 있는데, 에러
  케이스가 정확히 그 전제를 깨뜨린다.

---

### 🟡 Medium

#### 8. 작가 신청 승인/반려의 예외가 어디에도 안 잡힌다

- **위치**: `lib/admin/pages/author_applications_tab.dart:88-108`, `178-179`;
  `lib/admin/pages/overview/author_application_preview.dart:45-83`
- **문제**: `_handleApprove`/`_handleReject`는 `async` 함수인데
  `onApprove: () => _handleApprove(application)` 형태로 `VoidCallback`에
  담긴다 — 반환된 Future가 버려진다. 두 파일 다 `catch`가 없다(preview 쪽은
  `finally`만 있다). `approveApplication`이 던지면 **버튼을 눌러도 아무 일도
  안 일어나고 아무 메시지도 안 뜬다**(콘솔에만 unhandled async error).
- **대조**: 같은 admin 화면의 `author_management_section.dart:104-108`은
  `catch (e)` + 스낵바로 제대로 처리한다.

#### 9. 일괄 강제 내리기가 `activityLog`에 `packSuspended`를 안 남긴다

- **위치**: `lib/admin/pages/author_management_section.dart:79-98` vs
  `lib/admin/pages/all_story_packs_section.dart:71-86`
- **문제**: 팩 하나씩 내릴 때(`all_story_packs_section`)는 팩마다
  `ActivityKind.packSuspended`를 남긴다. 그런데 작가 자격 회수 시
  `suspendPacksForAuthor`로 **N개를 한꺼번에** 내릴 때는
  `ActivityKind.authorRevoked` 한 줄만 남고 `packSuspended`는 하나도 안 남는다.
- **결과**: `pack_approvals_tab.dart:85-86`의 "강제 내리기 이력" 필터에서
  일괄로 내려간 작품들은 **한 번도 내려간 적 없는 것처럼** 보인다.
- **분류**: `activityLog`가 개요 위젯에서는 써지는데 대응 탭에서는 안 써지던
  과거 버그와 같은 패턴.

#### 10. 리뷰/댓글에 모더레이션 경로가 아예 없다

- **위치**: `firestore.rules:457-503`
- **문제**: `reviews`에는 **`allow delete` 규칙이 아예 없다**(본인 것조차).
  `comments`는 본인의 소프트 삭제(`isDeleted: true`)만 허용하고, admin용
  삭제/숨김 규칙이 없다. 규칙에도 없고 admin UI에도 없다(2b-2 참고).
  욕설/스포일러/스팸이 올라오면 **콘솔에서 손으로 지우는 것 외에 방법이 없다**.

#### 11. 배치 작업이 실패 개수만 세고 원인을 버린다

- **위치**: `lib/admin/pages/story_tab_view.dart:623, 827, 866, 905`,
  `lib/admin/pages/approvals_tab.dart:173`
- **문제**: 전부 `catch (_) { failed += 1; }` / `catch (_) { failed.add(id); }`
  형태. "N건 실패"만 뜨고 왜 실패했는지(권한? 네트워크? 잘못된 상태?)는
  사용자도 로그도 알 수 없다. 최소한 `debugPrint` 정도는 남겨야 한다.
  (`ActivityLogRepository.log`의 `debugPrint`처럼 — 그건 삼키는 게 맞고 로그도
  남기는 좋은 예다.)

---

### 🟢 Low

#### 12. `my_library_tab.dart`의 `crossAxisCount`가 계산만 되고 안 쓰인다

- **위치**: `lib/features/catalog/pages/my_library_tab.dart:152`
  (`flutter analyze` warning: `unused_local_variable`)
- **내용**: `LayoutBuilder`로 `constraints.maxWidth >= storyGridWideBreakpoint ? 6 : 4`
  를 구해 놓고 아무 데도 안 넘긴다. 그리드 배치는
  `storyCoverGridDelegate()`가 `maxCrossAxisExtent: 150`으로 알아서 하므로
  **화면은 정상 동작한다** — 홈 탭과 그리드를 공유하도록 리팩터한 흔적이
  남은 것. `LayoutBuilder` 래핑째로 지우면 된다.

#### 13. `scene_frame.dart`의 죽은 null 검사

- **위치**: `lib/reader/shared/scene_frame.dart:788`
  (`flutter analyze` warning: `unnecessary_null_comparison`)
- **내용**: `_buildCinematicScene(String url)`의 파라미터가 non-nullable인데
  `url != null && url.isNotEmpty`로 검사한다. 배경 URL을 nullable로 다루던
  시절의 잔재. 동작에는 영향 없다.

#### 14. `firestore.rules` / `storage.rules`가 배포본과 어긋나 있다 (기존에 알려진 문제)

- 저장소의 `firestore.rules`는 마이그레이션 이전 필드 목록을 아직 보여주고
  있고, `storage.rules` 파일은 아예 없다. 위 규칙 관련 지적(#1/#2/#5/#10)을
  실제로 고치기 전에 **콘솔 배포본을 기준선으로 삼고 파일을 거기 맞춰
  되돌리는 작업이 먼저** 필요하다 — 안 그러면 파일에서 고친 게 배포된 다른
  규칙을 덮어써서 새 사고를 만든다.

#### 15. `activityLog` 규칙 블록의 들여쓰기가 오해를 부른다

- **위치**: `firestore.rules:580-586`
- `writerNotices` 블록 안에 중첩된 것처럼 들여쓰기돼 있지만 실제로는
  최상위 match다. 동작은 정상, 읽는 사람만 헷갈린다.

---

---

### 2026-08-24 추가 발견

Part 1(페이월 구멍 수정) + Part 2(문서화 패스) 작업 중 새로 나온 것들.
**전부 고치지 않고 남겼다** — 문서화 패스에 동작 변경을 섞지 않기 위해서다.

#### 16. 🔴 Storage 다운로드 토큰 URL이 보안 규칙을 우회한다 — 유료 콘텐츠 유출

- **위치**: `functions/src/index.ts`의 `uploadAndGetDownloadUrl()`,
  `lib/admin/data/admin_image_repository.dart`(및 sfx/bgm의 같은 패턴)
- **문제**: 두 업로드 경로 모두 **다운로드 토큰 URL**을 만들어 Firestore
  문서에 저장한다 — CF는 `firebaseStorageDownloadTokens` 메타데이터를 직접
  심고, Flutter admin은 `ref.getDownloadURL()`을 쓴다. 이런 URL은
  **Storage 보안 규칙을 통째로 우회한다**: 토큰을 아는 사람은 로그인조차
  없이 파일을 받을 수 있다.
- **왜 심각한가**: 표지 이미지가 공개인 건 정상이다. 그런데 **유료 팩의 노드
  배경 이미지와 TTS 내레이션 오디오도 같은 방식으로 공개**다. 게다가 그 URL은
  노드 문서 안에 들어 있으므로, 위 #2에 남아 있는 collection-group 구멍으로
  노드를 읽을 수 있는 사람은 URL을 수집해 인증 없이 파일을 받을 수 있다 —
  #2와 같은 급의 유료 콘텐츠 유출 경로가 하나 더 있다는 뜻이다.
- **덤으로**: `uploadAndGetDownloadUrl()`의 주석은 "Storage 보안 규칙
  (`request.auth != null`)만으로 읽기가 통제된다"고 적고 있는데 **사실과
  다르다**. 이 잘못된 주석이 문제를 오래 안 보이게 했을 가능성이 높다.
- **손볼 방향**: 토큰 URL 대신 수명이 짧은 signed URL을 요청 시점에 발급하는
  Cloud Function 경유로 바꾼다(그리고 그 함수에 #3과 같은 소유권 게이트를 건다).

#### 17. 🟠 `storage.rules` 파일이 저장소에 아예 없다

- **위치**: 저장소 루트(없음), `firebase.json`(`storage` 항목 없음)
- **문제**: Storage 규칙을 저장소에서 배포할 수도, diff를 볼 수도, 리뷰할 수도
  없다 — 콘솔에서만 손으로 관리된다. `firestore.rules`가 이미 배포본과
  어긋난 전례가 있는 프로젝트에서 같은 사고가 더 조용히 날 수 있는 구조다.
  (#16 때문에 지금은 Storage 규칙 자체의 실효성도 낮다.)

#### 18. 🟠 `images` / `sfxLibrary` 카테고리 변경 권한이 규칙에 없다

- **위치**: `firestore.rules`의 `images`/`sfxLibrary` match vs
  `AdminImageRepository.updateCategory()` / `AdminSfxRepository.updateCategory()`
- **문제**: 두 저장소 모두 `.update({'category': ...})`를 호출하는데, 규칙에는
  `create, delete`만 있고 `update`가 없다. 둘 중 하나다 — (a) 배포본에는
  `update`가 있고 이 파일만 뒤처졌거나, (b) 두 라이브러리의 "카테고리 변경"이
  프로덕션에서 permission-denied로 실패하고 있다. **콘솔 확인 필요.**

#### 19. 🟡 `rejectNode`가 이미 발행된 노드를 살아 있는 이야기에서 떨어뜨린다

- **위치**: `lib/admin/data/admin_story_repository.dart`의 `rejectNode()`
- **문제**: 수정 요청이 반려되면 `status: 'draft'`로 되돌린다 — 이미 연재
  중이던 노드도 마찬가지다(`liveSnapshot`은 보존한다). 그런데 리더의
  `fetchPublishedNodes()`는 `status == 'published'`만 읽으므로, **그 노드는
  독자에게 보이던 이야기에서 사라진다**. 작가의 수정을 반려했을 뿐인데
  기존에 승인된 화가 통째로 빠지는 건 의도된 동작으로 보기 어렵다.
- **주의**: 이번 Part 1의 새 읽기 규칙과는 무관하다 — 규칙 이전부터 그랬다.

#### 20. 🟡 `previewNodeLimit`이 어디에도 저장되지 않는다

- **위치**: `lib/features/catalog/models/story_pack.dart`(기본값 `3`),
  `story_pack_detail_page.dart:434`, 두 리더의 페이월 조건
- **문제**: 팩 상세는 "구매 전 N개 노드까지 무료로 미리볼 수 있어요"라고
  안내하고 리더가 이 값으로 페이월을 거는데, 이 값은 Firestore 어디에도
  저장되지 않고 admin에서 편집할 수도 없다 — Dart 기본값 `3`이 사실상 유일한
  값이다. 작가/팩마다 다르게 정할 수 있어야 하는 값이라면 `liveMetadata`에
  넣고 편집 UI를 붙여야 한다.
- **참고**: `canListenToNodeTts()`는 이미 `liveMetadata.previewNodeLimit`을
  먼저 읽고 없으면 3으로 떨어지게 해 뒀다 — 나중에 필드가 생겨도 그대로 동작한다.

#### 21. 🟡 세이브 저장 실패가 사용자에게 안 보인다 (#1의 부작용으로 노출됨)

- **위치**: `lib/core/state/cloud_sync_controller.dart`의 `_onGameStateChanged`
- **문제**: `catchError`로 `debugPrint`만 하고 끝난다. #1을 고치면서
  "로컬이 서버보다 뒤처졌을 때 저장이 거부되는" 경로가 새로 생겼는데, 그때
  사용자는 아무 것도 못 본다(예전엔 조용히 구매가 되돌아갔으므로 거부가 더
  안전하긴 하다). 스트림 에러를 삼키지 않는다는 이 프로젝트의 관례(#7)와
  같은 문제다.

#### 22. 🟢 안 쓰이는 복합 색인 하나

- **위치**: `firestore.indexes.json`의 `comments` (isDeleted, createdAt↓)
- **문제**: 댓글 쿼리 두 개(`fetchPage`/`fetchReplies`)는 둘 다
  `parentCommentId`까지 함께 걸러 3필드 색인을 쓴다. 그리고
  `(isDeleted, createdAt)`은 `(isDeleted, parentCommentId, createdAt)`의
  접두(prefix)가 아니라 그쪽으로 대체되지도 않는다 — 정말로 아무도 안 쓴다.
  답글을 구분하지 않던 예전 쿼리의 잔재로 보인다. **삭제 후보**(지우지 않음) —
  콘솔의 색인 사용 통계로 한 번 확인한 뒤 지울 것.

---

### 확인했고 문제 없던 것 (참고)

기왕 본 김에, 의심스러워 보이지만 실제로는 제대로 돼 있는 것들:

- **중간에 추가된 필드의 nullable 처리** — `storyPacks.createdAt`,
  `users.createdAt`, `suspended`/`suspendedReason`/`suspendedAt`/`suspendedBy`,
  `users.accountDisabled`는 **클라이언트 모델에서 전부 nullable-safe**하게
  읽는다(`admin_story_pack.dart:147,178-181`, `user_profile.dart:44-53`,
  `author_account_service.dart:44`). 레거시 문서를 읽다 깨지지 않는다.
  (문제는 #5처럼 *규칙 쪽*에 남아 있다.)
- **카카오 로그인 팝업의 postMessage 오리진 검사** —
  `lib/core/auth/kakao_login_popup.dart:74`에 `event.origin` 확인이 제대로
  있다(Toss 쪽과 동일). 그 아래 `catch (_) { return; }`는 남의 오리진에서 온
  잘못된 JSON을 무시하는 정상 처리다.
- **계정 정지/해제의 activityLog** — 클라이언트가 아니라
  `setAuthorAccountDisabled` Cloud Function이 서버에서 남긴다. 두 호출 지점
  (`author_management_section.dart:132`, `user_management_page.dart:142`)에
  주석으로 명시돼 있다. 누락 아님.
- **개요의 승인 대기 미리보기** — `pending_queue_preview.dart`에 승인/반려
  버튼이 없는 건 의도된 설계다(파일 상단 주석). 로그 누락이 아니다.
- **Cloud Functions의 role 검사** — `refundCoinCharge`,
  `setAuthorAccountDisabled`(admin), `previewNodeTts`,
  `refreshTypecastVoices`(author/admin)는 전부 서버에서 `users/{uid}.role`을
  다시 읽어 확인한다. 빠진 건 #3 하나뿐이다.
- **unused import** — `lib/` 전체에 하나도 없다(`flutter analyze` 기준).
- **admin 격리** — `lib/main.dart`/`lib/features/**`에서 `lib/admin/`을
  import하는 곳은 여전히 0건이다.

---

## 2b. 없거나 반쯤 만들다 만 화면 / 기능

코드에 남은 흔적(스텁 핸들러, "준비 중" 스낵바, UI 없는 enum 값, admin
화면이 없는 Firestore 컬렉션) 기준으로만 적었다.

### 1. 신고(report) 처리 — enum만 있고 화면 전체가 없음 · 크게

- **흔적**: `admin_dashboard_page.dart`의 `_AdminSection.reports`(50번 줄)가
  실제 화면 대신 `ComingSoonPlaceholder('신고 처리는 아직 준비중이에요')`
  (350-351줄)로 연결된다. 사이드바 항목은 이미 노출된다.
- **없는 것**: 독자 앱 어디에도 신고 버튼이 없고, `reports` 컬렉션도 없고,
  규칙도 없다. 즉 **신고를 접수할 수단 자체가 없다** — admin 화면만 자리를
  잡아 뒀다.
- **작업량**: 큼 (리더/댓글 UI + 컬렉션 + 규칙 + admin 큐 + 처리 상태 관리).

### 2. 리뷰/댓글 모더레이션 — admin 화면 없음 · 중간

- **흔적**: `storyPacks/{packId}/reviews`와 `/comments`는 리더 쪽에
  작성·표시 UI가 완성돼 있는데(`pack_reviews_section.dart`,
  `pack_comments_section.dart`), `lib/admin/` 전체에 두 컬렉션을 다루는
  코드가 **한 줄도 없다**. 규칙에도 admin 삭제 경로가 없다(2a-10).
- **작업량**: 중간 (admin 탭 하나 + 규칙에 admin delete 추가). 1번(신고)과
  같이 설계하는 게 자연스럽다.

### 3. 모바일 로그아웃 · 아주 작음

- 2a-4 참고. `onSignOut` 콜백이 이미 있으므로 배선만 하면 된다.

### 4. 알림(notifications) · 큼

- **흔적**: `settings_tab.dart:44`(모바일)와
  `catalog_desktop_nav_bar.dart:398`(데스크톱) 양쪽에 "알림" 항목이 있고
  둘 다 `_showComingSoon`이다. `catalog_desktop_nav_bar.dart:353-355` 주석에
  "알림/계정은 아직 실제 기능이 없다 — 요청 사양, 이 작업 범위 밖"이라고
  명시돼 있다.
- **없는 것**: 알림 컬렉션, FCM 설정, 읽음 처리. 공지사항 탭의 미읽음 뱃지
  (`hasUnreadNotice`)만 별개로 존재한다.
- **작업량**: 큼.

### 5. 계정 설정 / 회원 탈퇴 · 중간

- **흔적**: "계정" 항목도 양쪽 다 `_showComingSoon` 스텁.
- **없는 것**: 프로필(닉네임/사진) 수정, **회원 탈퇴**. `users` 문서에
  `displayName`/`email`이 있고 admin 쪽엔 회원 관리 화면까지 있는데, 정작
  사용자가 자기 계정을 건드릴 방법이 없다.
- **참고**: 모바일 출시가 목표라면 회원 탈퇴는 스토어 심사에서 사실상 필수다.
- **작업량**: 중간(탈퇴는 Cloud Function 필요 — Auth 계정 + Firestore 문서 +
  Storage 정리).

### 6. 배포 URL 미확정 · 아주 작음 (배포 후)

- 2a-6 참고. `ExternalLinks`의 두 상수.

### 7. 인앱 결제(IAP) · 중간

- **흔적**: `MonetizationService.purchaseRevivalItem()`은
  `AdMobMonetizationService`에서도 여전히 `return false`
  (`admob_monetization_service.dart:105-108`, `TODO` 주석 있음). 리워드
  광고만 실제로 붙어 있다.
- **덧붙여**: `AdIds._androidRewarded`가 아직 **구글 테스트 ID를 그대로
  가리킨다**(`ad_ids.dart:47-48`, `TODO`). 배너/전면은 실제 ID가 발급됐는데
  리워드만 안 됐고, **iOS는 세 종류 전부 테스트 ID**다 — 릴리즈 빌드로
  나가면 리워드 광고 수익이 0이다.
- **작업량**: 중간(SDK 선택은 아직 미정 상태로 CLAUDE.md에 남아 있다).

### 8. 옛 TRPG 게임 클러스터 — 완성돼 있는데 진입로가 없다 · 판단 필요

- **흔적**: `lib/features/battle/`, `lib/features/encounter/`,
  `lib/features/merchant/`, `lib/features/revival/`, `lib/features/panel/`,
  `lib/widgets/app_drawer.dart`, `lib/widgets/footer_nav_bar.dart`,
  `lib/widgets/hearts_indicator.dart` — 전부 구현이 끝나 있지만 **앱 어디에서도
  라우팅되지 않는다**. 자세한 내용은 아래 부록 참고.
- **작업량**: 되살리려면 큼 / 걷어내려면 중간. 어느 쪽이든 **제품 결정이
  먼저**다.

### 9. 테스트 커버리지 0 · 중간

- `test/widget_test.dart`는 여전히 Flutter 기본 카운터 템플릿이다
  (`find.text('0')`, `MyApp`에 존재하지 않는 카운터를 찾는다). 지금
  `flutter test`를 돌리면 실패한다. 그 외 테스트 파일은 없다.
- 2a에 적은 규칙 관련 항목들은 특히 Firestore rules 유닛 테스트
  (`@firebase/rules-unit-testing`)로 잡는 게 가장 확실하다.

### 10. `main_scene_frame_preview.dart` — 스스로 만료를 선언해 둔 개발용 진입점

- 파일 주석(19줄)에 "리더가 실제 Firestore 노드로 SceneFrame을 구동하게 되면
  이 파일은 지워도 된다"고 적혀 있고, 그 조건은 이미 충족됐다(리더 둘 다
  실데이터로 동작). **지금도 정상 빌드된다** — 요청대로 남겨 뒀지만, 유지할지
  지울지는 결정이 필요하다.

---

## 부록 — Part 1 정리 결과 요약

### 삭제함 (4개)

| 파일 | 근거 |
|---|---|
| `lib/features/catalog/widgets/library_header.dart` | 참조 0건. `catalog_desktop_nav_bar.dart:349` 주석이 이미 "죽은 코드"라고 명시. 진단용 노랑 `ColoredBox`가 박힌 채 방치돼 있었다. 조사 기록은 `doc/library_header_black_screen_investigation.md`로 보존 |
| `lib/reader/shared/models/node_translation.dart` | 참조 0건 — Cloud Function, `FIRESTORE_SCHEMA.md`, 규칙 어디에도 `translations` 서브컬렉션이 없다. 계획 흔적조차 없음 |
| `lib/core/auth/local_auth_service.dart` | `GoogleAuthService` + `KakaoAuthService`가 완전히 대체. `auth_service.dart`의 dartdoc 참조도 같이 정리 |
| `lib/core/monetization/no_op_monetization_service.dart` | `AdMobMonetizationService`가 대체(`main.dart:20`, `revival_page.dart:27`에서 사용). `monetization_service.dart`/`admob_monetization_service.dart`의 dartdoc 참조도 같이 정리 |

### 남김 — battle / encounter / merchant / revival

**요청하신 "스토리 엔진이 아직 이 개념을 참조하는지" 확인 결과: 참조한다.**

- `lib/core/state/game_state.dart:3`이 `features/battle/models/battle_result.dart`를
  **직접 import**한다. 디렉터리를 지우면 `GameState`가 컴파일되지 않는다.
- `GameState`에 `inventory` / `level` / `exp` / `hearts` / `hasUsedAdRevival` /
  `applyBattleResult(BattleResult)`가 살아 있고, 이 중 대부분이
  `toJson()`/`loadFromJson()`을 통해 **실제 사용자 문서
  `users/{uid}/save/current`에 저장되고 있다**(schema v6).
- 동시에 이 개념들은 **완전한 섬**이다: `applyBattleResult`는 호출자가 0건이고,
  `hearts`/`inventory`/`level`을 읽고 쓰는 코드는 전부 battle/encounter/
  merchant/revival 페이지 안에만 있으며, 그 페이지들은 어디에서도 push되지
  않는다. `lib/features/panel/`과 `lib/widgets/app_drawer.dart`·
  `footer_nav_bar.dart`·`hearts_indicator.dart`도 `EncounterPage`를 통해서만
  도달 가능하다 — 요청하신 목록보다 실제 섬이 더 크다.
- 따라서 "UI만 지우고 모델 개념을 남기는" 최악의 상태를 피하려면, 이건
  **UI + GameState 필드 + 세이브 스키마 마이그레이션을 한 덩어리로 처리하는
  별도 작업**이어야 한다. 이번 정리 범위 밖으로 판단해 전부 남겨 뒀다(2b-8).

### 남김 — `lib/main_scene_frame_preview.dart`

요청대로 유지. `flutter build web -t lib/main_scene_frame_preview.dart` 정상
성공 확인함(2b-10).

### 그 외 스윕 결과

- **unused import**: `lib/` 전체 0건.
- **주석 처리된 죽은 코드 블록**: `library_header.dart`에 있던 것이 유일했고
  파일과 함께 사라졌다.
- **이미 구현된 기능을 가리키는 낡은 TODO**: 없음. 남은 TODO 10건은 전부
  아직 유효하다(AdMob 실제 광고 단위, 배포 URL, IAP SDK, 미제작 이미지 애셋).
- **`doc/` 아래 파일**: 요청대로 아무것도 지우지 않았다. 지금 있는 목업
  HTML들이 명백히 폐기됐다고 볼 근거는 못 찾았다.

### 검증

- `flutter analyze` — **error 0 / warning 2**(둘 다 이번 작업 이전부터 있던
  것, 2a-12·2a-13). 전체 이슈 338 → 328로 감소, 새로 생긴 항목 없음.
- `flutter build web -t lib/main.dart` — 성공
- `flutter build web -t lib/main_admin.dart` — 성공
- `flutter build web -t lib/main_scene_frame_preview.dart` — 성공
- admin 격리(`grep -rn "^import.*admin/" lib | grep -v ^lib/admin`) — 0건 유지
