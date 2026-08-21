import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

/**
 * storyPacks/{packId} 문서의 avgRating/reviewCount를 유지한다. Flutter 쪽
 * StoryPackReviewRepository는 리뷰 문서(storyPacks/{packId}/reviews/{uid})
 * 자체만 쓰고, 이 두 집계 필드는 절대 클라이언트가 직접 쓰지 않는다 — 매
 * 페이지 로드마다 reviews 서브컬렉션 전체를 훑어 평균을 내는 대신, 리뷰가
 * 쓰일 때만(생성/수정/삭제) 서버에서 한 번 재계산해 두는 쪽이 읽기 비용이
 * 훨씬 싸다.
 *
 * onDocumentWritten 하나가 onCreate/onUpdate/onDelete를 전부 커버한다 —
 * Admin SDK로 실행되므로 firestore.rules(클라이언트는 storyPacks 문서의
 * avgRating/reviewCount를 쓸 방법이 애초에 없다)를 우회해서 쓴다.
 */
export const onReviewWritten = onDocumentWritten(
  "storyPacks/{packId}/reviews/{uid}",
  async (event) => {
    const packId = event.params.packId;
    const packRef = db.collection("storyPacks").doc(packId);

    const reviewsSnapshot = await packRef.collection("reviews").get();
    const reviewCount = reviewsSnapshot.size;

    let avgRating: number | null = null;
    if (reviewCount > 0) {
      const total = reviewsSnapshot.docs.reduce((sum, doc) => {
        const rating = doc.data().rating;
        return sum + (typeof rating === "number" ? rating : 0);
      }, 0);
      avgRating = total / reviewCount;
    }

    // storyPacks 문서 자체가 이 트리거 실행 사이에 삭제됐을 수 있다(팩
    // 삭제) — update()는 문서가 없으면 예외를 던지므로, 그 경우는 조용히
    // 넘어간다(재집계할 대상 자체가 없으니 실패가 아니다).
    try {
      await packRef.update({avgRating, reviewCount});
    } catch (error) {
      console.warn(
        `storyPacks/${packId} 집계 갱신 건너뜀(문서 없음일 가능성): ${error}`
      );
    }
  }
);

/**
 * storyPacks/{packId}/comments/{commentId} 문서의 likeCount를 유지한다 —
 * onReviewWritten과 완전히 같은 패턴(좋아요 문서가 쓰일 때마다 likes
 * 서브컬렉션 전체를 다시 세서 댓글 문서에 되쓴다). Flutter 쪽
 * StoryPackCommentRepository.watchLikeCount()가 이 필드를 그대로 구독하고,
 * 클라이언트는 likes/{uid} 문서 자체(존재 여부)만 만들거나 지운다 —
 * likeCount는 절대 직접 쓰지 않는다(firestore.rules의 comments update
 * 규칙도 이 필드를 클라이언트가 못 바꾸게 고정해 둔다).
 */
export const onCommentLikeWritten = onDocumentWritten(
  "storyPacks/{packId}/comments/{commentId}/likes/{uid}",
  async (event) => {
    const {packId, commentId} = event.params;
    const commentRef = db
      .collection("storyPacks")
      .doc(packId)
      .collection("comments")
      .doc(commentId);

    const likesSnapshot = await commentRef.collection("likes").get();
    const likeCount = likesSnapshot.size;

    // 댓글 문서 자체가 이 트리거 실행 사이에 삭제됐을 수는 없다(소프트
    // 삭제만 지원 — 댓글 문서는 항상 존재한다) — 그래도 onReviewWritten과
    // 같은 방어를 맞춰 둔다.
    try {
      await commentRef.update({likeCount});
    } catch (error) {
      console.warn(
        `storyPacks/${packId}/comments/${commentId} likeCount 갱신 건너뜀: ${error}`
      );
    }
  }
);

/**
 * KST(Asia/Seoul, UTC+9) 기준 "YYYY-MM-DD" 문자열. rankingSnapshots 문서 id로
 * 쓴다 — 이 프로젝트 유저가 대부분 한국 사용자라 하루 경계를 KST로 맞춘다.
 * new Date()에 9시간을 더해 UTC 필드로 읽는 방식(Intl 없이도 Cloud
 * Functions Node 런타임에서 안정적으로 동작한다).
 */
function kstDateKey(date: Date): string {
  const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, "0");
  const d = String(kst.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * 매일 KST 00:10에 storyPacks를 viewCount 내림차순으로 훑어 상위 20개를
 * rankingSnapshots/{오늘(KST) 날짜}에 스냅샷으로 남긴다. 리더 홈 화면의
 * "실시간 랭킹" 섹션이 이 문서를 읽는다(오늘 문서로 순위를, 어제 문서와
 * packIds 배열의 인덱스를 비교해 순위 변동 화살표/NEW 배지를 클라이언트에서
 * 직접 계산한다 — 스키마를 packIds 배열 하나로 단순하게 유지하기 위해서다).
 * 이 함수 자신도 어제 스냅샷을 읽어 변동을 로그로 남긴다(운영 확인용) —
 * Admin SDK로 실행되므로 firestore.rules(클라이언트는 rankingSnapshots에
 * 쓸 방법이 애초에 없다)를 우회해서 쓴다.
 */
export const computeDailyRankingSnapshot = onSchedule(
  {schedule: "10 0 * * *", timeZone: "Asia/Seoul"},
  async () => {
    const now = new Date();
    const todayKey = kstDateKey(now);
    const yesterdayKey = kstDateKey(new Date(now.getTime() - 24 * 60 * 60 * 1000));

    const topSnapshot = await db
      .collection("storyPacks")
      .orderBy("viewCount", "desc")
      .limit(20)
      .get();
    const packIds = topSnapshot.docs.map((doc) => doc.id);

    const yesterdayDoc = await db
      .collection("rankingSnapshots")
      .doc(yesterdayKey)
      .get();
    const yesterdayPackIds =
      (yesterdayDoc.data()?.packIds as string[] | undefined) ?? [];

    packIds.forEach((packId, index) => {
      const rank = index + 1;
      const prevIndex = yesterdayPackIds.indexOf(packId);
      const prevRank = prevIndex === -1 ? null : prevIndex + 1;
      console.log(
        `랭킹 ${todayKey} #${rank} ${packId} (전일 ${prevRank ?? "없음(신규)"})`
      );
    });

    await db.collection("rankingSnapshots").doc(todayKey).set({
      packIds,
      generatedAt: FieldValue.serverTimestamp(),
    });
  }
);
