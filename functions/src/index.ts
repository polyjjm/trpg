import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

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
