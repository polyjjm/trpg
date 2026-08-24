// =============================================================================
// ⚠️ 배포 엔트리포인트 — 새 엔트리포인트를 만들 때 반드시 읽을 것
// =============================================================================
//
// functions/package.json의 "main"이 가리키는 파일이다. `firebase deploy
// --only functions`는 **오직 이 파일에서 도달 가능한 export만** 배포하고,
// 여기서 사라진 이름의 함수는 다음 배포 때 **삭제된다**(purchasePack /
// confirmCoinCharge / kakaoSignIn 같은 결제·인증 함수 포함).
//
// [규칙 1] 새 엔트리포인트는 반드시 `./secure_entrypoint`(또는 그것을 이미
//          포함한 다른 엔트리포인트) 위에 쌓는다. **절대 `./index`에서 직접
//          `export *` 하지 말 것.**
//
//          `export * from "./index"`로 시작하면 컴파일도 되고 배포도 되고
//          함수 이름도 전부 그대로라서 아무 경고 없이 통과한다. 그런데
//          secure_entrypoint가 감싸 둔 TTS 함수 셋(synthesizeNodeTts /
//          previewNodeTts / onNodeApprovedGenerateTts)이 legacy 원본으로
//          조용히 되돌아간다 — 즉 5분짜리 signed URL 대신 영구
//          Firebase download-token URL을 다시 내보내기 시작한다. 보안
//          회귀인데 증상이 전혀 없어서 알아채기가 거의 불가능하다.
//
// [규칙 2] index.ts에 새 함수를 추가하면 secure_entrypoint.ts에도 재노출
//          한 줄을 같이 추가한다. secure_entrypoint.ts는 `export *`가 아니라
//          이름을 하나씩 나열하는 방식이라(그래야 TTS 셋만 골라 교체할 수
//          있다), 빠뜨리면 그 함수는 그냥 배포되지 않는다.
//
// [규칙 3] 엔트리포인트를 새로 만들거나 바꿀 때는 배포 전에 아래로 실제
//          도달 가능한 목록을 확인한다 — 정적 grep보다 이쪽이 확실하다:
//
//            npm run build && node -e "console.log(Object.keys(require('./lib/<새엔트리>.js')).sort().join('\n'))"
//
//          현재 이 파일 기준으로 18개가 나와야 한다(index.ts의 15개 전부 +
//          migrateLegacyTtsTokensNow/Scheduled + resolveStoryMedia).
//
// 관련: 아직 머지되지 않은 PR #6(secure_reader_entrypoint.ts)과
// PR #7(draft_live_entrypoint.ts)이 각각 `export * from "./index"`로 시작하는
// 엔트리포인트를 정의하고 package.json의 "main"을 그쪽으로 옮긴다 — 둘 중
// 무엇을 먼저 머지하든 위 [규칙 1]에 맞게 `./secure_entrypoint_v2` 기반으로
// 고쳐야 한다.
// =============================================================================

// 층 1+2 — index.ts의 15개 함수, 그중 TTS 3개는 secure_entrypoint의 보안
// 래퍼로 교체된 상태. (+ migrateLegacyTtsTokens{Now,Scheduled})
export * from "./secure_entrypoint";

// 층 3 (#4) — 독자용 미디어 게이트.
export {resolveStoryMedia} from "./secure_story_media";

// 층 4 (#6) — 독자용 본문 게이트 + publishedNodeCount 서버 집계.
// PR #6이 따로 만들었던 secure_reader_entrypoint.ts는 지웠다 — 그 파일은
// `export * from "./index"`로 시작해서 위 [규칙 1]을 정면으로 위반했다.
export {
  fetchReaderStoryNodes,
  maintainPublishedNodeCount,
  backfillPublishedNodeCounts,
} from "./secure_reader_nodes";

// 층 5 (#7) — draft/live 분리 백필. PR #7의 draft_live_entrypoint.ts도 같은
// 이유로 지웠다(그 파일 역시 `export * from "./index"`로 시작했다).
export {backfillNodeDraftDocuments} from "./draft_live_migration";

// 층 6 — 공개 카탈로그 자산. 승인된 표지만 private 원본에서 public 복사본으로
// 옮기고, 기존 승인 팩을 위한 관리자 백필도 함께 노출한다.
export {
  publishApprovedStoryCover,
  backfillPublicStoryCovers,
} from "./public_catalog_assets";
