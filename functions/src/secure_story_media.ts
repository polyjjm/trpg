import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

const db = getFirestore();
const signedUrlTtlMs = 5 * 60 * 1000;
const previewNodeLimitDefault = 3;

type MediaKind = "image" | "sfx" | "bgm";
type MediaRequest = {
  packId?: unknown;
  imageIds?: unknown;
  sfxIds?: unknown;
  bgmIds?: unknown;
};

type LiveNode = {
  id: string;
  order: number;
  backgroundImage: string | null;
  sfxId: string | null;
  bgmId: string | null;
};

function stringIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((v): v is string => typeof v === "string" && v.length > 0))];
}

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
  const saleActive = salePrice !== null && (!start || start <= now) && (!end || end >= now);
  return saleActive ? salePrice! : price;
}

async function callerRole(uid: string): Promise<string> {
  const snap = await db.collection("users").doc(uid).get();
  return typeof snap.data()?.role === "string" ? snap.data()!.role : "reader";
}

async function callerOwnsPack(uid: string, packId: string): Promise<boolean> {
  const save = await db.doc(`users/${uid}/save/current`).get();
  const owned = Array.isArray(save.data()?.ownedPackIds) ? save.data()!.ownedPackIds as unknown[] : [];
  return owned.includes(packId);
}

function parseLiveNode(id: string, data: Record<string, unknown>): LiveNode | null {
  const live = data.liveSnapshot as Record<string, unknown> | undefined;
  if (!live) return null;
  const effects = live.effects as Record<string, unknown> | undefined;
  const sfx = effects?.sfx as Record<string, unknown> | undefined;
  const bgm = effects?.bgm as Record<string, unknown> | undefined;
  return {
    id,
    order: typeof live.order === "number" ? live.order : Number.MAX_SAFE_INTEGER,
    backgroundImage: typeof live.backgroundImage === "string" ? live.backgroundImage : null,
    sfxId: sfx?.enabled === true && typeof sfx.sfxId === "string" ? sfx.sfxId : null,
    bgmId: typeof bgm?.bgmId === "string" ? bgm.bgmId : null,
  };
}

function allowedIds(nodes: LiveNode[], packLive: Record<string, unknown> | undefined) {
  const imageIds = new Set<string>();
  const sfxIds = new Set<string>();
  const bgmIds = new Set<string>();
  for (const node of nodes) {
    if (node.backgroundImage) imageIds.add(node.backgroundImage);
    if (node.sfxId) sfxIds.add(node.sfxId);
    if (node.bgmId) bgmIds.add(node.bgmId);
  }
  const defaultImage = packLive?.defaultBackgroundImage;
  const defaultBgm = packLive?.defaultBgmId;
  if (typeof defaultImage === "string" && defaultImage.length > 0) imageIds.add(defaultImage);
  if (typeof defaultBgm === "string" && defaultBgm.length > 0) bgmIds.add(defaultBgm);
  return {imageIds, sfxIds, bgmIds};
}

function storagePathFromReference(reference: string): string | null {
  if (reference.startsWith("admin/story_")) return reference;
  try {
    const url = new URL(reference);
    if (url.hostname !== "firebasestorage.googleapis.com") return null;
    const marker = "/o/";
    const index = url.pathname.indexOf(marker);
    if (index < 0) return null;
    return decodeURIComponent(url.pathname.slice(index + marker.length));
  } catch (_) {
    return null;
  }
}

async function sourcePath(kind: MediaKind, id: string): Promise<string | null> {
  const collection = kind === "image" ? "images" : kind === "sfx" ? "sfxLibrary" : "bgmLibrary";
  const snap = await db.collection(collection).doc(id).get();
  if (!snap.exists) return null;
  const field = kind === "image" ? "url" : "storageUrl";
  const ref = snap.data()?.[field];
  if (typeof ref !== "string" || ref.length === 0) return null;
  return storagePathFromReference(ref);
}

async function ensurePrivateCopy(packId: string, kind: MediaKind, id: string): Promise<string | null> {
  const source = await sourcePath(kind, id);
  if (!source) return null;

  const bucket = getStorage().bucket();
  const sourceFile = bucket.file(source);
  const privatePath = `private/story_media/${packId}/${kind}/${id}`;
  const destination = bucket.file(privatePath);
  const [exists] = await destination.exists();
  if (!exists) {
    const [sourceMetadata] = await sourceFile.getMetadata();
    await sourceFile.copy(destination);
    // copy()가 Firebase download token custom metadata까지 복제할 수 있으므로
    // private 복사본에서는 명시적으로 제거한다. 공개/작가용 원본은 건드리지 않는다.
    const metadata = {
      contentType: sourceMetadata.contentType,
      cacheControl: "private, max-age=300",
      metadata: {firebaseStorageDownloadTokens: null},
    } as unknown as {contentType?: string; cacheControl?: string; metadata: Record<string, string>};
    await destination.setMetadata(metadata);
  }
  return privatePath;
}

async function signedPrivateUrl(packId: string, kind: MediaKind, id: string): Promise<string | null> {
  const path = await ensurePrivateCopy(packId, kind, id);
  if (!path) return null;
  const [url] = await getStorage().bucket().file(path).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + signedUrlTtlMs,
  });
  return url;
}

async function resolveMap(
  packId: string,
  kind: MediaKind,
  requested: string[],
  allowed: Set<string>
): Promise<Record<string, string>> {
  const result: Record<string, string> = {};
  for (const id of requested) {
    if (!allowed.has(id)) continue;
    const url = await signedPrivateUrl(packId, kind, id);
    if (url) result[id] = url;
  }
  return result;
}

/**
 * 독자용 스토리 미디어 게이트.
 *
 * 클라이언트가 image/sfx/bgm id를 임의로 보내도 그대로 서명하지 않는다.
 * 서버가 published liveSnapshot을 다시 읽어 실제 작품에서 참조된 id인지 확인하고,
 * 유료 팩 비구매자는 preview 범위의 노드가 참조한 미디어만 받을 수 있다.
 * 원본 라이브러리의 Firebase download-token URL은 절대 반환하지 않고,
 * pack별 private 복사본에 대해 5분짜리 V4 signed URL만 발급한다.
 */
export const resolveStoryMedia = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  const data = request.data as MediaRequest;
  if (typeof data.packId !== "string" || data.packId.length === 0) {
    throw new HttpsError("invalid-argument", "packId가 올바르지 않습니다.");
  }
  const packId = data.packId;
  const imageIds = stringIds(data.imageIds);
  const sfxIds = stringIds(data.sfxIds);
  const bgmIds = stringIds(data.bgmIds);
  if (imageIds.length > 100 || sfxIds.length > 100 || bgmIds.length > 100) {
    throw new HttpsError("invalid-argument", "한 번에 요청한 미디어가 너무 많아요.");
  }

  const [packSnap, nodesSnap, role, owns] = await Promise.all([
    db.collection("storyPacks").doc(packId).get(),
    db.collection("storyPacks").doc(packId).collection("nodes").where("status", "==", "published").get(),
    callerRole(uid),
    callerOwnsPack(uid, packId),
  ]);
  if (!packSnap.exists) throw new HttpsError("not-found", "존재하지 않는 스토리팩이에요.");

  const pack = packSnap.data()!;
  const packLive = pack.liveMetadata as Record<string, unknown> | undefined;
  const allNodes = nodesSnap.docs
    .map((doc) => parseLiveNode(doc.id, doc.data()))
    .filter((node): node is LiveNode => node !== null)
    .sort((a, b) => a.order - b.order);

  const fullAccess = role === "admin" || pack.authorId === uid || effectivePrice(packLive) <= 0 || owns;
  const previewLimit = typeof packLive?.previewNodeLimit === "number"
    ? Math.max(0, Math.floor(packLive.previewNodeLimit))
    : previewNodeLimitDefault;
  const visibleNodes = fullAccess ? allNodes : allNodes.slice(0, previewLimit);
  const allowed = allowedIds(visibleNodes, packLive);

  const [images, sfx, bgm] = await Promise.all([
    resolveMap(packId, "image", imageIds, allowed.imageIds),
    resolveMap(packId, "sfx", sfxIds, allowed.sfxIds),
    resolveMap(packId, "bgm", bgmIds, allowed.bgmIds),
  ]);

  return {images, sfx, bgm, fullAccess};
});
