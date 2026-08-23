import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const db = getFirestore();

async function isAdmin(uid: string): Promise<boolean> {
  const user = await db.collection("users").doc(uid).get();
  return user.data()?.role === "admin";
}

/**
 * 기존 storyPacks/{packId}/nodes/{nodeId} 문서를 동일 id의 draftNodes로 복사한다.
 * 기존 nodes 문서는 리더/TTS 호환을 위해 그대로 둔다. 이후 author editor는
 * draftNodes만 수정하고 승인 시에만 nodes의 liveSnapshot을 갱신한다.
 *
 * 멱등: draftNodes 문서가 이미 있으면 건너뛴다. 재실행해도 작가의 새 초안을
 * 기존 live 문서로 덮어쓰지 않는다.
 */
export const backfillNodeDraftDocuments = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!(await isAdmin(uid))) {
    throw new HttpsError("permission-denied", "관리자만 실행할 수 있어요.");
  }

  const packs = await db.collection("storyPacks").get();
  let copied = 0;
  let skipped = 0;

  for (const pack of packs.docs) {
    const nodes = await pack.ref.collection("nodes").get();
    for (const node of nodes.docs) {
      const draftRef = pack.ref.collection("draftNodes").doc(node.id);
      const existing = await draftRef.get();
      if (existing.exists) {
        skipped += 1;
        continue;
      }

      await draftRef.set({
        ...node.data(),
        migratedFromLegacyNodeAt: FieldValue.serverTimestamp(),
      });
      copied += 1;
    }
  }

  await db.doc("maintenance/nodeDraftSplitV1").set({
    completed: true,
    copied,
    skipped,
    completedAt: FieldValue.serverTimestamp(),
    completedBy: uid,
  });

  return {success: true, copied, skipped};
});
