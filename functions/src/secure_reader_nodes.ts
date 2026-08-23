import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const db = getFirestore();

function effectivePrice(live: Record<string, unknown> | undefined): number {
  if (!live) return 0;
  const price = typeof live.price === "number" ? live.price : 0;
  const salePrice = typeof live.salePrice === "number" ? live.salePrice : null;
  const toDate = (value: unknown): Date | null => {
    if (value && typeof (value as {toDate?: unknown}).toDate === "function") {
      return (value as {toDate: () => Date}).toDate();
    }
    return null;
  };
  const start = toDate(live.discountStartAt);
  const end = toDate(live.discountEndAt);
  const now = new Date();
  const saleActive =
    salePrice !== null &&
    (!start || start <= now) &&
    (!end || end >= now);
  return saleActive ? salePrice! : price;
}

async function callerRole(uid: string): Promise<string> {
  const snap = await db.collection("users").doc(uid).get();
  return typeof snap.data()?.role === "string" ? snap.data()!.role : "reader";
}

async function ownsPack(uid: string, packId: string): Promise<boolean> {
  const save = await db.doc(`users/${uid}/save/current`).get();
  const owned = Array.isArray(save.data()?.ownedPackIds)
    ? save.data()!.ownedPackIds as unknown[]
    : [];
  return owned.includes(packId);
}

async function publishedCountForPack(packId: string): Promise<number> {
  const published = await db
    .collection("storyPacks")
    .doc(packId)
    .collection("nodes")
    .where("status", "==", "published")
    .get();
  return published.size;
}

/**
 * 독자에게 노드 본문을 전달하는 유일한 서버 게이트.
 *
 * Firestore의 published node 문서를 클라이언트가 직접 읽지 않아도 되게 한다.
 * 서버가 pack의 liveMetadata 가격, 구매 여부, 작가/admin 여부를 다시 확인한 뒤
 * 필요한 liveSnapshot만 반환한다.
 *
 * - 작가 본인/admin: published 노드 전체
 * - 무료 팩: published 노드 전체
 * - 유료 팩 구매자: published 노드 전체
 * - 유료 팩 비구매자: order 기준 previewNodeLimit(기본 3)개만
 *
 * top-level draft 필드는 절대 반환하지 않는다. 마지막 승인본인 liveSnapshot만
 * 반환하므로, 작가가 수정 중인 미승인 내용도 이 API를 통해서는 노출되지 않는다.
 */
export const fetchReaderStoryNodes = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  const data = request.data as {packId?: unknown};
  const packId = data.packId;
  if (typeof packId !== "string" || packId.length === 0) {
    throw new HttpsError("invalid-argument", "packId가 올바르지 않습니다.");
  }

  const packRef = db.collection("storyPacks").doc(packId);
  const packSnap = await packRef.get();
  if (!packSnap.exists) {
    throw new HttpsError("not-found", "존재하지 않는 스토리팩이에요.");
  }
  const pack = packSnap.data()!;
  if (pack.serializationStatus !== "approved" || pack.suspended === true) {
    const role = await callerRole(uid);
    const canManage = role === "admin" || pack.authorId === uid;
    if (!canManage) {
      throw new HttpsError("permission-denied", "현재 공개 중인 스토리팩이 아니에요.");
    }
  }

  const role = await callerRole(uid);
  const isManager = role === "admin" || pack.authorId === uid;
  const liveMetadata = pack.liveMetadata as Record<string, unknown> | undefined;
  const isFree = effectivePrice(liveMetadata) <= 0;
  const purchased = isManager || isFree ? true : await ownsPack(uid, packId);

  const snapshot = await packRef
    .collection("nodes")
    .where("status", "==", "published")
    .get();

  const published = snapshot.docs
    .map((doc) => {
      const live = doc.data().liveSnapshot as Record<string, unknown> | undefined;
      return live ? {id: doc.id, live} : null;
    })
    .filter((item): item is {id: string; live: Record<string, unknown>} => item !== null)
    .sort((a, b) => {
      const ao = typeof a.live.order === "number" ? a.live.order : 0;
      const bo = typeof b.live.order === "number" ? b.live.order : 0;
      return ao - bo;
    });

  const previewLimit =
    typeof liveMetadata?.previewNodeLimit === "number" && liveMetadata.previewNodeLimit >= 0
      ? Math.floor(liveMetadata.previewNodeLimit)
      : 3;
  const visible = purchased ? published : published.slice(0, previewLimit);

  return {
    nodes: visible.map(({id, live}) => ({id, ...live})),
    access: purchased ? "full" : "preview",
    publishedNodeCount: published.length,
  };
});

/**
 * 홈/카탈로그가 collectionGroup('nodes')로 모든 published 본문 문서를 읽지
 * 않도록 storyPacks.publishedNodeCount를 서버에서 유지한다. 노드 생성/승인/
 * 반려/삭제 어느 경우든 최종 published 개수를 다시 세므로 상태 전이가 꼬여도
 * 집계가 스스로 복구된다.
 */
export const maintainPublishedNodeCount = onDocumentWritten(
  "storyPacks/{packId}/nodes/{nodeId}",
  async (event) => {
    const packId = event.params.packId;
    const packRef = db.collection("storyPacks").doc(packId);
    const packSnap = await packRef.get();
    if (!packSnap.exists) return;

    await packRef.update({
      publishedNodeCount: await publishedCountForPack(packId),
      publishedNodeCountUpdatedAt: FieldValue.serverTimestamp(),
    });
  }
);

/**
 * 기존 팩은 maintainPublishedNodeCount 트리거가 생기기 전에 만들어졌으므로
 * 배포 직후 한 번 백필한다. admin만 수동 호출할 수 있고 이후에는 트리거가
 * 계속 값을 유지한다.
 */
export const backfillPublishedNodeCounts = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (await callerRole(uid) !== "admin") {
    throw new HttpsError("permission-denied", "관리자만 실행할 수 있어요.");
  }

  const packs = await db.collection("storyPacks").get();
  let updated = 0;
  for (const pack of packs.docs) {
    await pack.ref.update({
      publishedNodeCount: await publishedCountForPack(pack.id),
      publishedNodeCountUpdatedAt: FieldValue.serverTimestamp(),
    });
    updated += 1;
  }
  return {success: true, updated};
});
