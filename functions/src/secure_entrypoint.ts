import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {DocumentReference, FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

import * as legacy from "./index";

// 이 파일은 배포 엔트리포인트다. 기존 index.ts의 비-TTS 함수는 그대로
// 재노출하고, 영구 Firebase download token URL을 만들던 TTS 함수 셋만
// 보안 래퍼로 교체한다. index.ts를 한 번에 크게 뜯지 않고도 이미 배포된
// 함수 이름을 유지하면서 점진적으로 마이그레이션하기 위한 경계다.

export const onReviewWritten = legacy.onReviewWritten;
export const onCommentLikeWritten = legacy.onCommentLikeWritten;
export const computeDailyRankingSnapshot = legacy.computeDailyRankingSnapshot;
export const computeDailyRevenueSnapshot = legacy.computeDailyRevenueSnapshot;
export const refreshTypecastVoiceCacheScheduled = legacy.refreshTypecastVoiceCacheScheduled;
export const kakaoSignIn = legacy.kakaoSignIn;
export const confirmCoinCharge = legacy.confirmCoinCharge;
export const purchasePack = legacy.purchasePack;
export const purchaseBundle = legacy.purchaseBundle;
export const refreshTypecastVoices = legacy.refreshTypecastVoices;
export const refundCoinCharge = legacy.refundCoinCharge;
export const setAuthorAccountDisabled = legacy.setAuthorAccountDisabled;

const db = getFirestore();
const typecastApiKey = defineSecret("TYPECAST_API_KEY");
const signedUrlTtlMs = 5 * 60 * 1000;
const migrationMarkerRef = db.doc("maintenance/privateTtsDownloadTokensV1");

type NodeTtsFields = {
  ttsAudioUrl?: unknown;
  ttsPreviewAudioUrl?: unknown;
};

/**
 * 새 캐시는 Storage 경로 자체를 저장한다. 예전 문서에는 Firebase의 장기
 * download-token URL이 남아 있으므로 둘 다 읽을 수 있게 경로로 정규화한다.
 * TTS 전용 prefix 밖의 URL/경로는 보안상 거부한다.
 */
function ttsStoragePath(reference: string): string | null {
  if (
    reference.startsWith("admin/story_tts/") ||
    reference.startsWith("admin/story_tts_preview/")
  ) {
    return reference;
  }

  try {
    const url = new URL(reference);
    if (url.hostname !== "firebasestorage.googleapis.com") return null;
    const marker = "/o/";
    const markerIndex = url.pathname.indexOf(marker);
    if (markerIndex < 0) return null;
    const path = decodeURIComponent(url.pathname.slice(markerIndex + marker.length));
    return (
      path.startsWith("admin/story_tts/") ||
      path.startsWith("admin/story_tts_preview/")
    ) ? path : null;
  } catch (_) {
    return null;
  }
}

/**
 * 예전 파일에 박혀 있던 firebaseStorageDownloadTokens를 실제 GCS custom
 * metadata에서 제거한다. URL 문자열만 Firestore에서 지우면 이미 유출된
 * token URL은 계속 살아 있으므로 메타데이터 자체를 폐기해야 한다.
 *
 * Cloud Storage JSON API는 custom metadata 값을 null로 PATCH하면 해당 키를
 * 삭제한다. @google-cloud/storage의 타입은 custom metadata 값을 string으로만
 * 좁혀 두고 있어 런타임 PATCH 표현을 unknown 캐스트로 전달한다.
 */
async function revokeFirebaseDownloadToken(storagePath: string): Promise<void> {
  const file = getStorage().bucket().file(storagePath);
  const [metadata] = await file.getMetadata();
  const customMetadata = metadata.metadata as Record<string, string> | undefined;
  if (!customMetadata?.firebaseStorageDownloadTokens) return;

  const deleteTokenPatch = {
    metadata: {firebaseStorageDownloadTokens: null},
  } as unknown as {metadata: Record<string, string>};
  await file.setMetadata(deleteTokenPatch);
}

/** 권한 검사가 끝난 호출자에게만 짧은 수명의 읽기 URL을 발급한다. */
async function shortLivedTtsUrl(storagePath: string): Promise<string> {
  await revokeFirebaseDownloadToken(storagePath);
  const [url] = await getStorage().bucket().file(storagePath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + signedUrlTtlMs,
  });
  return url;
}

/**
 * 노드에 남은 예전 장기 token URL을 Storage 경로로 바꾸고, 해당 token도
 * 폐기한다. trigger/콜러블/일회성 마이그레이션이 모두 이 함수를 공유한다.
 */
async function normalizeNodeTtsRefs(
  nodeRef: DocumentReference,
  data: NodeTtsFields
): Promise<number> {
  const updates: Record<string, string> = {};
  let normalized = 0;

  for (const field of ["ttsAudioUrl", "ttsPreviewAudioUrl"] as const) {
    const raw = data[field];
    if (typeof raw !== "string" || raw.length === 0) continue;
    const storagePath = ttsStoragePath(raw);
    if (!storagePath) {
      console.warn(`${nodeRef.path}.${field}: 알 수 없는 TTS 참조라 마이그레이션을 건너뜀.`);
      continue;
    }

    await revokeFirebaseDownloadToken(storagePath);
    if (raw !== storagePath) {
      updates[field] = storagePath;
      normalized += 1;
    }
  }

  if (Object.keys(updates).length > 0) {
    await nodeRef.update(updates);
  }
  return normalized;
}

async function isAdmin(uid: string): Promise<boolean> {
  const snap = await db.collection("users").doc(uid).get();
  return snap.data()?.role === "admin";
}

async function canManagePack(uid: string, packId: string): Promise<boolean> {
  const [packSnap, userSnap] = await Promise.all([
    db.collection("storyPacks").doc(packId).get(),
    db.collection("users").doc(uid).get(),
  ]);
  return packSnap.data()?.authorId === uid || userSnap.data()?.role === "admin";
}

/**
 * 기존 synthesizeNodeTts의 서버 구매/무료/미리보기 인가와 Typecast 캐싱
 * 로직은 그대로 재사용한다. 단, legacy가 돌려준 영구 download-token URL은
 * 절대 클라이언트에 전달하지 않는다. 실제 파일의 token을 폐기하고 Firestore
 * 캐시를 Storage 경로로 정규화한 뒤, 5분짜리 signed URL만 반환한다.
 */
export const synthesizeNodeTts = onCall(
  {secrets: [typecastApiKey]},
  async (request) => {
    const result = await legacy.synthesizeNodeTts.run(request);
    const data = result as {audioUrl?: unknown; cached?: unknown};
    if (typeof data.audioUrl !== "string") {
      throw new HttpsError("internal", "내레이션 파일 참조를 확인하지 못했어요.");
    }

    const storagePath = ttsStoragePath(data.audioUrl);
    if (!storagePath) {
      throw new HttpsError("internal", "내레이션 파일 경로가 올바르지 않아요.");
    }

    const requestData = request.data as {packId?: unknown; nodeId?: unknown};
    if (typeof requestData.packId === "string" && typeof requestData.nodeId === "string") {
      const nodeRef = db
        .collection("storyPacks")
        .doc(requestData.packId)
        .collection("nodes")
        .doc(requestData.nodeId);
      const snap = await nodeRef.get();
      if (snap.exists) await normalizeNodeTtsRefs(nodeRef, snap.data()!);
    } else {
      await revokeFirebaseDownloadToken(storagePath);
    }

    return {
      audioUrl: await shortLivedTtsUrl(storagePath),
      cached: data.cached === true,
    };
  }
);

/**
 * 미리듣기도 같은 방식으로 장기 URL을 제거한다. 추가로 기존 구현에 빠져 있던
 * "이 작가가 이 팩의 소유자인가" 검사를 여기서 강제한다 — 다른 author가
 * 임의의 packId/nodeId를 넣어 남의 노드에 preview 캐시를 쓰지 못한다.
 */
export const previewNodeTts = onCall(
  {secrets: [typecastApiKey]},
  async (request) => {
    const uid = request.auth?.uid;
    const requestData = request.data as {packId?: unknown; nodeId?: unknown};
    if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    if (
      typeof requestData.packId !== "string" || requestData.packId.length === 0 ||
      typeof requestData.nodeId !== "string" || requestData.nodeId.length === 0
    ) {
      throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
    }
    if (!(await canManagePack(uid, requestData.packId))) {
      throw new HttpsError("permission-denied", "자기 작품만 미리들을 수 있어요.");
    }

    const result = await legacy.previewNodeTts.run(request);
    const data = result as {audioUrl?: unknown; cached?: unknown};
    if (typeof data.audioUrl !== "string") {
      throw new HttpsError("internal", "미리듣기 파일 참조를 확인하지 못했어요.");
    }
    const storagePath = ttsStoragePath(data.audioUrl);
    if (!storagePath) {
      throw new HttpsError("internal", "미리듣기 파일 경로가 올바르지 않아요.");
    }

    const nodeRef = db
      .collection("storyPacks")
      .doc(requestData.packId)
      .collection("nodes")
      .doc(requestData.nodeId);
    const snap = await nodeRef.get();
    if (snap.exists) await normalizeNodeTtsRefs(nodeRef, snap.data()!);

    return {
      audioUrl: await shortLivedTtsUrl(storagePath),
      cached: data.cached === true,
    };
  }
);

/**
 * 승인 시 사전 생성도 legacy의 검증된 생성 로직을 실행한 직후 캐시를 private
 * 경로 형태로 정규화한다. 이 후속 update가 다시 trigger를 깨우더라도 legacy
 * 쪽은 liveSnapshot/status가 안 바뀐 이벤트를 즉시 무시하고, 이 함수도 이미
 * path 형태인 값을 다시 쓰지 않으므로 루프가 끝난다.
 */
export const onNodeApprovedGenerateTts = onDocumentWritten(
  {document: "storyPacks/{packId}/nodes/{nodeId}", secrets: [typecastApiKey]},
  async (event) => {
    await legacy.onNodeApprovedGenerateTts.run(event);

    const {packId, nodeId} = event.params;
    const nodeRef = db.collection("storyPacks").doc(packId).collection("nodes").doc(nodeId);
    const snap = await nodeRef.get();
    if (snap.exists) await normalizeNodeTtsRefs(nodeRef, snap.data()!);
  }
);

/** 기존 노드 전체의 영구 download token을 한 번에 폐기하는 실제 작업. */
async function migrateLegacyTtsTokens(): Promise<{nodes: number; refs: number}> {
  const marker = await migrationMarkerRef.get();
  if (marker.data()?.completed === true) {
    return {
      nodes: typeof marker.data()?.nodeCount === "number" ? marker.data()!.nodeCount : 0,
      refs: typeof marker.data()?.normalizedRefCount === "number" ?
        marker.data()!.normalizedRefCount : 0,
    };
  }

  const snapshot = await db.collectionGroup("nodes").get();
  let normalizedRefCount = 0;
  for (const doc of snapshot.docs) {
    normalizedRefCount += await normalizeNodeTtsRefs(doc.ref, doc.data());
  }

  await migrationMarkerRef.set({
    completed: true,
    nodeCount: snapshot.size,
    normalizedRefCount,
    completedAt: FieldValue.serverTimestamp(),
  });

  return {nodes: snapshot.size, refs: normalizedRefCount};
}

/** admin이 배포 직후 즉시 한 번 실행할 수 있는 수동 마이그레이션. */
export const migrateLegacyTtsTokensNow = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!(await isAdmin(uid))) {
    throw new HttpsError("permission-denied", "관리자만 실행할 수 있어요.");
  }
  return {success: true, ...(await migrateLegacyTtsTokens())};
});

/**
 * 수동 실행을 놓쳐도 기존 장기 token이 계속 남지 않도록 하루 한 번 백업으로
 * 확인한다. 첫 성공 후에는 marker 문서 한 번 읽고 즉시 끝난다.
 */
export const migrateLegacyTtsTokensScheduled = onSchedule(
  {schedule: "30 3 * * *", timeZone: "Asia/Seoul"},
  async () => {
    const result = await migrateLegacyTtsTokens();
    console.log(
      `TTS download-token migration: nodes=${result.nodes}, normalizedRefs=${result.refs}`
    );
  }
);
