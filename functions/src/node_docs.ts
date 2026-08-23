import {DocumentData, DocumentReference, getFirestore} from "firebase-admin/firestore";

/**
 * ⚠️ 다른 모듈들과 달리 여기서는 `const db = getFirestore()`를 **모듈 최상위에
 * 두면 안 된다.** 이 모듈은 `index.ts`가 import하는데, import는 index.ts 본문의
 * `initializeApp()`보다 **먼저** 평가된다. 최상위에서 getFirestore()를 부르면
 * "The default Firebase app does not exist"로 모든 함수가 콜드 스타트에서
 * 죽는다(실제로 겪었다 — 배포 전 export 검증에서 잡혔다).
 *
 * secure_story_media.ts / secure_reader_nodes.ts / draft_live_migration.ts는
 * 최상위에서 불러도 괜찮은데, 그건 그 모듈들이 secure_entrypoint(→ index)를
 * 거친 **뒤에** 로드되기 때문이다. 이 모듈만 index보다 앞선다.
 */
function db() {
  return getFirestore();
}

/**
 * 노드 draft/live 분리(PR #7) 이후의 문서 위치를 한 곳에서 정리한다.
 *
 * - `storyPacks/{packId}/draftNodes/{nodeId}` — 작가가 편집 중인 상태.
 *   TTS **미리듣기** 캐시도 여기 산다(미리듣기는 편집기 기능이다).
 * - `storyPacks/{packId}/nodes/{nodeId}` — 독자/TTS가 보는 승인본.
 *   독자용 내레이션 캐시(`ttsAudioUrl`)는 계속 여기 산다.
 */

export function draftNodeRef(
  packId: string,
  nodeId: string
): DocumentReference<DocumentData> {
  return db()
    .collection("storyPacks")
    .doc(packId)
    .collection("draftNodes")
    .doc(nodeId);
}

export function liveNodeRef(
  packId: string,
  nodeId: string
): DocumentReference<DocumentData> {
  return db().collection("storyPacks").doc(packId).collection("nodes").doc(nodeId);
}

/**
 * 편집기 상태 문서를 찾는다 — **draftNodes 우선, 없으면 legacy nodes 폴백**.
 *
 * 폴백이 필요한 이유는 두 가지다:
 *  1. `backfillNodeDraftDocuments`를 아직 안 돌린 환경(배포 직후, 개발 환경).
 *  2. 마이그레이션 이전에 만들어져 draft 문서가 없는 노드.
 *
 * 클라이언트 쪽 `AdminStoryRepository.fetchNode()`가 쓰는 것과 정확히 같은
 * 폴백 규칙이라, 서버와 편집기가 같은 문서를 본다.
 *
 * 어느 쪽에도 없으면 null — 호출부가 not-found로 바꾼다.
 */
export async function resolveEditorNodeDoc(
  packId: string,
  nodeId: string
): Promise<{ref: DocumentReference<DocumentData>; data: DocumentData} | null> {
  const draft = draftNodeRef(packId, nodeId);
  const draftSnap = await draft.get();
  if (draftSnap.exists) {
    return {ref: draft, data: draftSnap.data()!};
  }

  const live = liveNodeRef(packId, nodeId);
  const liveSnap = await live.get();
  if (liveSnap.exists) {
    return {ref: live, data: liveSnap.data()!};
  }

  return null;
}
