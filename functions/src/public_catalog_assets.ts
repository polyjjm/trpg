import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

const db = getFirestore();
const storage = getStorage();

function objectPathFromDownloadUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0) return null;
  try {
    const url = new URL(value);
    const marker = "/o/";
    const index = url.pathname.indexOf(marker);
    if (index < 0) return null;
    return decodeURIComponent(url.pathname.substring(index + marker.length));
  } catch (_) {
    return null;
  }
}

async function publishCover(packId: string, coverImageId: string | null): Promise<void> {
  const packRef = db.collection("storyPacks").doc(packId);
  const destinationPath = `public/story_covers/${packId}.jpg`;
  const bucket = storage.bucket();

  if (!coverImageId) {
    await bucket.file(destinationPath).delete({ignoreNotFound: true});
    await packRef.update({"liveMetadata.publicCoverPath": null});
    return;
  }

  const imageSnap = await db.collection("images").doc(coverImageId).get();
  const sourcePath = objectPathFromDownloadUrl(imageSnap.data()?.url);
  if (!sourcePath) {
    throw new Error(`cover image path not found: ${coverImageId}`);
  }

  await bucket.file(sourcePath).copy(bucket.file(destinationPath));
  await packRef.update({"liveMetadata.publicCoverPath": destinationPath});
}

/// 승인된 liveMetadata의 coverImageId가 바뀔 때만 공개 커버를 갱신한다.
/// 원본 admin/story_images는 계속 비공개로 두고, 독자는 public 복사본만 읽는다.
export const publishApprovedStoryCover = onDocumentWritten(
  "storyPacks/{packId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const beforeLive = before?.liveMetadata as Record<string, unknown> | undefined;
    const afterLive = after.liveMetadata as Record<string, unknown> | undefined;
    const beforeCover = typeof beforeLive?.coverImageId === "string" ? beforeLive.coverImageId : null;
    const afterCover = typeof afterLive?.coverImageId === "string" ? afterLive.coverImageId : null;

    if (beforeCover === afterCover) return;
    await publishCover(event.params.packId, afterCover);
  },
);

/// 이미 승인돼 있는 기존 팩들의 커버를 public/story_covers로 한 번에 옮기는
/// 관리자용 백필. 여러 번 실행해도 같은 목적지에 덮어써서 안전하다.
export const backfillPublicStoryCovers = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const user = await db.collection("users").doc(request.auth.uid).get();
  if (user.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "관리자만 실행할 수 있습니다.");
  }

  const packs = await db.collection("storyPacks")
    .where("serializationStatus", "==", "approved")
    .get();

  let copied = 0;
  let skipped = 0;
  for (const pack of packs.docs) {
    const live = pack.data().liveMetadata as Record<string, unknown> | undefined;
    const coverImageId = typeof live?.coverImageId === "string" ? live.coverImageId : null;
    if (!coverImageId) {
      skipped += 1;
      continue;
    }
    await publishCover(pack.id, coverImageId);
    copied += 1;
  }

  return {copied, skipped, total: packs.size};
});
