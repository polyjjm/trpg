import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {getAuth} from "firebase-admin/auth";
import {createHash, randomUUID} from "crypto";

initializeApp();
const db = getFirestore();

/**
 * 호출자가 admin인지 서버에서 직접 확인한다 — 클라이언트가 보낸 role
 * 주장을 절대 신뢰하지 않는다(firestore.rules의 isAdmin()과 같은 원칙을
 * Cloud Function 쪽에도 옮긴 것). refundCoinCharge처럼 admin 전용 함수마다
 * 이 확인을 거친다.
 */
async function isCallerAdmin(uid: string): Promise<boolean> {
  const snap = await db.collection("users").doc(uid).get();
  return snap.data()?.role === "admin";
}

/** isCallerAdmin과 같은 이유 — author/admin 둘 다 허용하는 함수(예:
 * refreshTypecastVoices)가 쓴다. */
async function isCallerAuthorOrAdmin(uid: string): Promise<boolean> {
  const snap = await db.collection("users").doc(uid).get();
  const role = snap.data()?.role;
  return role === "author" || role === "admin";
}

/** users/{uid}.displayName/email — 거래 문서에 그대로 박아 두기 위한 조회. */
async function fetchUserProfileSummary(
  uid: string
): Promise<{displayName: string; email: string}> {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.data();
  return {
    displayName: typeof data?.displayName === "string" ? data.displayName : "",
    email: typeof data?.email === "string" ? data.email : "",
  };
}

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

// Toss Payments 시크릿 키 — 절대 코드에 하드코딩하지 않는다. 배포 전에
// `firebase functions:secrets:set TOSS_SECRET_KEY`로 실제 값을 주입해야
// confirmCoinCharge가 동작한다(값을 안 채우면 함수가 배포는 되지만 호출
// 시점에 tossSecretKey.value()가 빈 문자열/에러를 내며 실패한다).
const tossSecretKey = defineSecret("TOSS_SECRET_KEY");

/**
 * 코인 충전 결제 승인 — 클라이언트(ChargePage)는 Toss 위젯이 돌려준
 * paymentKey/orderId와 자신이 골랐던 packageId만 넘긴다. amount는 받긴
 * 받지만 신뢰하지 않는다(로그/디버깅용) — 실제 검증은 항상 서버가 다시
 * 계산한 expectedPrice와, Toss가 실제로 확인해 준 totalAmount를 비교해서
 * 한다. 클라이언트가 "성공했다"고 주장하는 것만으로는 절대 코인이
 * 지급되지 않는다 — 반드시 이 함수가 Toss `/v1/payments/confirm`을 직접
 * 호출해 서버-서버 간에 확인한 뒤에만 지급한다.
 *
 * 멱등성: orderId를 그대로 거래 문서 id로 쓴다 — 같은 orderId로 이 함수가
 * 두 번 불려도(성공 화면 새로고침, 네트워크 재시도 등) 코인이 두 번
 * 지급되지 않는다. 이 검사와 잔액 갱신을 하나의 Firestore 트랜잭션
 * 안에서 함께 하므로, 동시에 같은 orderId로 들어온 요청도 안전하다.
 */
export const confirmCoinCharge = onCall(
  {secrets: [tossSecretKey]},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }

    const data = request.data as {
      paymentKey?: unknown;
      orderId?: unknown;
      amount?: unknown;
      packageId?: unknown;
    };
    const {paymentKey, orderId, amount, packageId} = data;
    if (
      typeof paymentKey !== "string" || paymentKey.length === 0 ||
      typeof orderId !== "string" || orderId.length === 0 ||
      typeof amount !== "number" || !Number.isFinite(amount) ||
      typeof packageId !== "string" || packageId.length === 0
    ) {
      throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
    }

    // 상품 가격은 클라이언트가 아니라 여기서 서버가 직접 조회한다 —
    // ChargePage가 보여주는 가격은 어디까지나 표시용이고, 실제로 결제해야
    // 할 금액의 유일한 원천은 이 문서다.
    const packageSnap = await db.collection("pointPackages").doc(packageId).get();
    if (!packageSnap.exists) {
      throw new HttpsError("not-found", "존재하지 않는 상품이에요.");
    }
    const pkg = packageSnap.data()!;
    const now = new Date();
    const discountStartAt = pkg.discountStartAt?.toDate?.() as Date | undefined;
    const discountEndAt = pkg.discountEndAt?.toDate?.() as Date | undefined;
    const salePriceKRW = typeof pkg.salePriceKRW === "number" ? pkg.salePriceKRW : null;
    const discountActive =
      salePriceKRW !== null &&
      (!discountStartAt || discountStartAt <= now) &&
      (!discountEndAt || discountEndAt >= now);
    const expectedPrice: number = discountActive
      ? salePriceKRW!
      : (typeof pkg.originalPriceKRW === "number" ? pkg.originalPriceKRW : 0);

    // Toss 결제 승인 API — 이 호출의 응답이 결제 성공 여부/실제 결제 금액의
    // 유일한 진짜 출처다. Firestore 트랜잭션 밖에서(네트워크 호출을
    // 트랜잭션 재시도에 얽히게 하지 않도록) 딱 한 번 호출한다.
    const basicAuth = Buffer.from(`${tossSecretKey.value()}:`).toString("base64");
    const tossResponse = await fetch("https://api.tosspayments.com/v1/payments/confirm", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({paymentKey, orderId, amount}),
    });
    const tossBody = await tossResponse.json() as Record<string, unknown>;

    if (!tossResponse.ok || tossBody.status !== "DONE") {
      console.error(
        `Toss 결제 승인 실패 (uid=${uid}, orderId=${orderId}, packageId=${packageId}):`,
        tossBody
      );
      throw new HttpsError(
        "aborted",
        typeof tossBody.message === "string" ? tossBody.message : "결제 승인에 실패했어요."
      );
    }

    if (tossBody.totalAmount !== expectedPrice) {
      console.error(
        `결제 금액 불일치 (uid=${uid}, orderId=${orderId}, packageId=${packageId}): ` +
          `Toss 확인 금액=${tossBody.totalAmount}, 상품 기대 금액=${expectedPrice}`
      );
      throw new HttpsError("aborted", "결제 금액이 상품 가격과 일치하지 않아요.");
    }

    const coinAmount = typeof pkg.coinAmount === "number" ? pkg.coinAmount : 0;
    const bonusCoins = typeof pkg.bonusCoins === "number" ? pkg.bonusCoins : 0;
    const totalCoins = coinAmount + bonusCoins;

    // Toss 카드 승인번호 — 결제 확인 응답의 card.approveNo. 카드 결제가
    // 아니거나(가상계좌 등) 응답에 없으면 null. 환불/정산 화면에서 카드사
    // 대사에 쓰라고 보관해 둔다 — 이 함수 자체는 이 값을 쓰지 않는다.
    const card = tossBody.card as Record<string, unknown> | undefined;
    const cardApproveNo = typeof card?.approveNo === "string" ? card.approveNo : null;

    // 거래 문서에 그대로 박아 둘 구매자 표시 이름/이메일 — admin 결제내역
    // 화면이 uid만으로 검색하지 않고 이름으로도 검색할 수 있어야 해서
    // (collectionGroup 쿼리는 users 문서를 조인해서 읽을 수 없다) 쓰는
    // 시점에 스냅샷으로 복사해 둔다. 나중에 유저가 이름을 바꿔도 이
    // 거래 문서의 값은 갱신되지 않는다(팩 문서의 authorName과 같은 트레이드오프).
    const profile = await fetchUserProfileSummary(uid);

    const walletRef = db.doc(`users/${uid}/wallet/current`);
    const txRef = db.doc(`users/${uid}/wallet/current/transactions/${orderId}`);

    const {newBalance, alreadyProcessed} = await db.runTransaction(async (t) => {
      // Firestore 트랜잭션은 모든 읽기가 모든 쓰기보다 먼저 와야 한다 —
      // 멱등성 체크(txRef)와 현재 잔액(walletRef)을 먼저 같이 읽는다.
      const [txSnap, walletSnap] = await Promise.all([t.get(txRef), t.get(walletRef)]);
      const currentBalance = (walletSnap.data()?.balance as number | undefined) ?? 0;

      if (txSnap.exists) {
        // 이미 이 orderId로 지급이 끝났다 — 재지급하지 않고 현재 잔액만
        // 돌려준다(성공 화면 새로고침 등으로 이 함수가 다시 불린 경우).
        return {newBalance: currentBalance, alreadyProcessed: true};
      }

      const updatedBalance = currentBalance + totalCoins;
      t.set(walletRef, {balance: updatedBalance}, {merge: true});
      t.create(txRef, {
        type: "charge",
        amount: totalCoins,
        packageId,
        relatedPaymentKey: paymentKey,
        // 환불(refundCoinCharge)이 "원래 얼마를 냈는지"를 서버에서 다시
        // 계산할 유일한 원천 — expectedPrice는 이미 Toss가 확인해 준
        // totalAmount와 같다는 걸 위에서 검증했다.
        amountKRW: expectedPrice,
        cardApproveNo,
        uid,
        displayName: profile.displayName,
        email: profile.email,
        refundedCoins: 0,
        refundStatus: "none",
        createdAt: FieldValue.serverTimestamp(),
      });
      return {newBalance: updatedBalance, alreadyProcessed: false};
    });

    return {success: true, newBalance, alreadyProcessed};
  }
);

/**
 * storyPacks/{packId}.liveMetadata의 price/salePrice/discountStartAt/
 * discountEndAt으로부터 지금 이 순간 실제로 적용되는 가격을 계산한다 —
 * firestore.rules의 effectivePrice()와 정확히 같은 계산이다(리더 쪽
 * StoryPack.effectivePrice/admin 쪽 AdminStoryPack.effectivePrice와도 같은
 * 모양). liveMetadata가 아직 없는 팩(연재 시작 승인 전)은 0(무료)으로 본다.
 */
function computeEffectivePrice(
  liveMetadata: Record<string, unknown> | undefined
): number {
  if (!liveMetadata) return 0;

  const price = typeof liveMetadata.price === "number" ? liveMetadata.price : 0;
  const salePrice =
    typeof liveMetadata.salePrice === "number" ? liveMetadata.salePrice : null;

  const toDate = (value: unknown): Date | undefined => {
    if (value && typeof (value as {toDate?: unknown}).toDate === "function") {
      return (value as {toDate: () => Date}).toDate();
    }
    return undefined;
  };
  const discountStartAt = toDate(liveMetadata.discountStartAt);
  const discountEndAt = toDate(liveMetadata.discountEndAt);

  const now = new Date();
  const discountActive =
    salePrice !== null &&
    (!discountStartAt || discountStartAt <= now) &&
    (!discountEndAt || discountEndAt >= now);

  return discountActive ? salePrice! : price;
}

/**
 * 코인으로 이야기 팩을 구매한다 — confirmCoinCharge와 정확히 같은 보안
 * 원칙이다: 가격은 클라이언트를 절대 신뢰하지 않고 storyPacks 문서를 서버가
 * 직접 다시 읽어서 계산하고(computeEffectivePrice), 잔액 확인/차감/소유권
 * 부여/거래 기록을 전부 하나의 Firestore 트랜잭션 안에서 원자적으로 한다.
 *
 * 소유권(ownedPackIds)은 GameState.toJson()이 통째로 users/{uid}/save/current
 * 문서에 덮어쓰는 배열과 같은 자리다 — 여기서 arrayUnion으로 서버가 먼저
 * 반영해 두고, 클라이언트(paywall.dart)는 이 함수가 성공을 돌려준 뒤에만
 * GameState.markPackOwned()로 로컬 상태를 맞춘다. 그래야 그 사이에 다른
 * 이유로 GameState가 한 번 더 저장되어도(전체 문서 덮어쓰기) 방금 서버가
 * 부여한 소유권이 지워지지 않는다.
 *
 * 멱등성: 거래 문서 id를 orderId 대신 `purchase_${packId}`로 고정한다 —
 * 한 유저가 같은 팩을 두 번 "처음 구매"할 일은 원래 없어야 하므로(소유는
 * 영구적이다), packId 자체가 자연스러운 멱등 키다. 이미 보유 중이거나
 * 무료 팩이면 과금 없이 소유만 보장하고 끝낸다.
 */
export const purchasePack = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }

  const data = request.data as {packId?: unknown};
  const packId = data.packId;
  if (typeof packId !== "string" || packId.length === 0) {
    throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
  }

  const packSnap = await db.collection("storyPacks").doc(packId).get();
  if (!packSnap.exists) {
    throw new HttpsError("not-found", "존재하지 않는 스토리팩이에요.");
  }
  const liveMetadata = packSnap.data()?.liveMetadata as
    | Record<string, unknown>
    | undefined;
  const effectivePrice = computeEffectivePrice(liveMetadata);
  // 거래 문서에 그대로 박아 둘 구매자 표시 이름/이메일 — confirmCoinCharge와
  // 같은 이유(admin 코인사용내역 화면의 이름 검색).
  const profile = await fetchUserProfileSummary(uid);

  const saveRef = db.doc(`users/${uid}/save/current`);
  const walletRef = db.doc(`users/${uid}/wallet/current`);
  const txRef = db.doc(
    `users/${uid}/wallet/current/transactions/purchase_${packId}`
  );

  const result = await db.runTransaction(async (t) => {
    // 모든 읽기를 먼저 — Firestore 트랜잭션 규칙(읽기는 전부 쓰기보다 먼저).
    const [saveSnap, walletSnap, txSnap] = await Promise.all([
      t.get(saveRef),
      t.get(walletRef),
      t.get(txRef),
    ]);

    const ownedPackIds =
      (saveSnap.data()?.ownedPackIds as string[] | undefined) ?? [];
    const alreadyOwned = ownedPackIds.includes(packId);
    const currentBalance =
      (walletSnap.data()?.balance as number | undefined) ?? 0;

    if (alreadyOwned) {
      // 이미 보유 중 — 과금 없이 그대로 성공 취급(재구매가 아니다).
      return {alreadyOwned: true, newBalance: currentBalance};
    }

    if (effectivePrice <= 0) {
      // 무료 팩 — 과금 없이 소유만 부여한다.
      t.set(saveRef, {ownedPackIds: FieldValue.arrayUnion(packId)}, {merge: true});
      return {alreadyOwned: false, newBalance: currentBalance};
    }

    if (txSnap.exists) {
      // 같은 packId로 이미 처리된 거래(동시 요청 레이스) — 재차감하지
      // 않는다. ownedPackIds도 그 거래 때 이미 반영됐어야 정상이지만,
      // 방어적으로 한 번 더 arrayUnion해 둔다(중복 삽입은 no-op).
      t.set(saveRef, {ownedPackIds: FieldValue.arrayUnion(packId)}, {merge: true});
      return {alreadyOwned: true, newBalance: currentBalance};
    }

    if (currentBalance < effectivePrice) {
      throw new HttpsError("failed-precondition", "코인이 부족해요.");
    }

    const updatedBalance = currentBalance - effectivePrice;
    t.set(walletRef, {balance: updatedBalance}, {merge: true});
    t.set(saveRef, {ownedPackIds: FieldValue.arrayUnion(packId)}, {merge: true});
    t.create(txRef, {
      type: "purchase",
      amount: -effectivePrice,
      packId,
      uid,
      displayName: profile.displayName,
      email: profile.email,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {alreadyOwned: false, newBalance: updatedBalance};
  });

  return {success: true, ...result};
});

/**
 * 코인으로 번들(packBundles/{bundleId} — 스토리팩 여러 개를 묶어 할인
 * 판매)을 구매한다. purchasePack/confirmCoinCharge와 같은 보안 원칙 —
 * 클라이언트는 bundleId만 넘기고, 가격/보유 여부/잔액은 전부 서버가 직접
 * 다시 읽어서 계산한다.
 *
 * **부분 보유 프로레이팅**: 이미 보유한 팩이 섞여 있어도 구매를 막지
 * 않는다 — 번들의 유효가(effectivePrice)에 "아직 안 가진 팩 수 / 전체 팩
 * 수" 비율을 곱한 만큼만 청구한다(반올림). 이미 전부 보유 중이면(더 팔
 * 게 없음) failed-precondition으로 거부한다.
 *
 * **멱등성 설계가 purchasePack과 다르다**: purchasePack은 `purchase_${packId}`
 * 같은 고정 거래 문서 id로 재호출을 막는다 — 팩 하나는 "보유/미보유"
 * 이진 상태라 그 키가 항상 같은 의미를 갖기 때문이다. 번들은 다르다 —
 * 관리자가 나중에 packIds를 늘리면, 이미 번들을 산 유저도 새로 추가된
 * 팩만큼은 다시 "미보유"가 되어 정당하게 한 번 더 결제할 수 있어야 한다.
 * 고정 거래 문서 id를 쓰면 그 재구매가 거래 문서 충돌로 막히거나(같은
 * id로 t.create가 실패) 방어적 재사용 로직 탓에 무료로 새 지급되는 등
 * 어느 쪽이든 틀린 동작이 나온다. 그래서 거래 문서는 매번 자동 생성
 * id로 만들고, 이중 청구 방지는 오직 트랜잭션 내부에서 매번 살아있는
 * ownedPackIds/wallet 값을 다시 읽어 unowned 개수를 재계산하는 것으로
 * 보장한다 — Firestore 트랜잭션은 직렬화 가능하므로(동시/재시도 호출은
 * 앞선 트랜잭션의 커밋 결과를 다시 읽고서야 재시도된다), 이 재계산만으로
 * 이중 청구가 원천적으로 불가능하다(재시도 시 unowned가 이미 0이면
 * "이미 보유" 에러로 자연스럽게 막힌다).
 *
 * `active` 필드는 여기서 검사하지 않는다 — confirmCoinCharge도
 * pointPackages.active를 구매 승인 시점에 재검사하지 않는 것과 같은
 * 기존 전례를 그대로 따른 것이다(진열 노출만 클라이언트가 active로
 * 거른다). 정말로 비활성 번들의 구매까지 서버에서 막아야 한다면 이후
 * 별도로 추가해야 한다.
 */
export const purchaseBundle = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }

  const data = request.data as {bundleId?: unknown};
  const bundleId = data.bundleId;
  if (typeof bundleId !== "string" || bundleId.length === 0) {
    throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
  }

  const bundleSnap = await db.collection("packBundles").doc(bundleId).get();
  if (!bundleSnap.exists) {
    throw new HttpsError("not-found", "존재하지 않는 번들이에요.");
  }
  const bundleData = bundleSnap.data()!;
  const packIds = Array.isArray(bundleData.packIds)
    ? (bundleData.packIds as unknown[]).filter((id): id is string => typeof id === "string")
    : [];
  if (packIds.length === 0) {
    throw new HttpsError("failed-precondition", "구성이 올바르지 않은 번들이에요.");
  }
  const bundleEffectivePrice = computeEffectivePrice(bundleData);
  // 거래 문서에 그대로 박아 둘 구매자 표시 이름/이메일 — confirmCoinCharge와
  // 같은 이유(admin 코인사용내역 화면의 이름 검색).
  const profile = await fetchUserProfileSummary(uid);

  const saveRef = db.doc(`users/${uid}/save/current`);
  const walletRef = db.doc(`users/${uid}/wallet/current`);
  const txRef = db.collection(`users/${uid}/wallet/current/transactions`).doc();

  const result = await db.runTransaction(async (t) => {
    // 모든 읽기를 먼저 — Firestore 트랜잭션 규칙(읽기는 전부 쓰기보다 먼저).
    const [saveSnap, walletSnap] = await Promise.all([
      t.get(saveRef),
      t.get(walletRef),
    ]);

    const ownedPackIds =
      (saveSnap.data()?.ownedPackIds as string[] | undefined) ?? [];
    const currentBalance =
      (walletSnap.data()?.balance as number | undefined) ?? 0;

    const unownedPackIds = packIds.filter((id) => !ownedPackIds.includes(id));
    if (unownedPackIds.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "이미 이 번들의 모든 팩을 보유하고 있어요."
      );
    }

    const amountToCharge = Math.round(
      (bundleEffectivePrice * unownedPackIds.length) / packIds.length
    );

    if (amountToCharge <= 0) {
      // 무료 번들(또는 반올림 결과 0코인) — 과금 없이 미보유분만 부여한다.
      t.set(
        saveRef,
        {ownedPackIds: FieldValue.arrayUnion(...unownedPackIds)},
        {merge: true}
      );
      return {newBalance: currentBalance, newlyOwnedPackIds: unownedPackIds};
    }

    if (currentBalance < amountToCharge) {
      throw new HttpsError("failed-precondition", "코인이 부족해요.");
    }

    const updatedBalance = currentBalance - amountToCharge;
    t.set(walletRef, {balance: updatedBalance}, {merge: true});
    t.set(
      saveRef,
      {ownedPackIds: FieldValue.arrayUnion(...unownedPackIds)},
      {merge: true}
    );
    t.create(txRef, {
      type: "purchase",
      amount: -amountToCharge,
      bundleId,
      packIds: unownedPackIds,
      uid,
      displayName: profile.displayName,
      email: profile.email,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {newBalance: updatedBalance, newlyOwnedPackIds: unownedPackIds};
  });

  return {success: true, ...result};
});

/**
 * "YYYY-MM-DD"(KST) 날짜 키가 가리키는 하루의 [start, end) 경계를 UTC
 * Date로 돌려준다 — Firestore Timestamp(createdAt)는 UTC 기준 순간이므로,
 * KST 하루 범위로 필터링하려면 항상 이 변환을 거쳐야 한다. KST는 UTC+9라
 * KST 00:00은 UTC 전날 15:00이다.
 */
function kstDayBoundsUtc(dateKey: string): {start: Date; end: Date} {
  const [y, m, d] = dateKey.split("-").map(Number);
  const start = new Date(Date.UTC(y, m - 1, d, 0, 0, 0) - 9 * 60 * 60 * 1000);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return {start, end};
}

/**
 * 관리자 전용 — 충전(코인 결제) 건을 부분/전체 환불한다. "아직 안 쓴
 * 코인만 환불 가능"이라는 정책이라, 정확히 얼마를 환불할 수 있는지는
 * 항상 서버가 다시 계산한다(클라이언트는 uid/chargeTxId/reason만 넘긴다):
 *
 *   refundableCoins = min(원래 지급 코인 - 이미 환불된 코인, 현재 지갑 잔액)
 *   refundKRW = round(원래 결제 금액(KRW) * refundableCoins / 원래 지급 코인)
 *
 * Toss 카드 결제 취소(부분 취소 포함)는 결제 하나(paymentKey)당 누적
 * cancelAmount가 원래 결제 금액을 넘을 수 없다는 걸 Toss 서버가 자체적으로
 * 강제한다 — 그래서 이 함수의 계산이 혹시 오래된 상태를 기준으로 살짝
 * 어긋나 있어도(동시에 두 admin이 같은 건을 환불 시도하는 등의 드문 경우),
 * Toss API가 그 요청을 거부해 이중 환불의 최종 방어선이 되어 준다.
 *
 * Toss 호출은 항상 먼저, Firestore 트랜잭션 밖에서 딱 한 번만 한다
 * (confirmCoinCharge와 같은 이유 — 네트워크 호출을 트랜잭션 재시도에
 * 얽히게 하지 않는다). Toss가 실패를 응답하면 Firestore에는 아무것도
 * 쓰지 않는다.
 */
export const refundCoinCharge = onCall(
  {secrets: [tossSecretKey]},
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    // 클라이언트가 보낸 "나는 admin이다" 주장은 신뢰하지 않는다 — 항상
    // 서버가 users/{uid}.role을 직접 다시 읽어 확인한다.
    if (!(await isCallerAdmin(callerUid))) {
      throw new HttpsError("permission-denied", "관리자만 사용할 수 있어요.");
    }

    const data = request.data as {
      uid?: unknown;
      chargeTxId?: unknown;
      reason?: unknown;
    };
    const {uid, chargeTxId, reason} = data;
    if (
      typeof uid !== "string" || uid.length === 0 ||
      typeof chargeTxId !== "string" || chargeTxId.length === 0 ||
      typeof reason !== "string" || reason.trim().length === 0
    ) {
      throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
    }

    const chargeRef = db.doc(`users/${uid}/wallet/current/transactions/${chargeTxId}`);
    const walletRef = db.doc(`users/${uid}/wallet/current`);

    const chargeSnap = await chargeRef.get();
    if (!chargeSnap.exists || chargeSnap.data()?.type !== "charge") {
      throw new HttpsError("not-found", "존재하지 않는 충전 거래예요.");
    }
    const charge = chargeSnap.data()!;
    const originalChargeCoins = typeof charge.amount === "number" ? charge.amount : 0;
    const alreadyRefundedCoins =
      typeof charge.refundedCoins === "number" ? charge.refundedCoins : 0;
    const originalKRW = typeof charge.amountKRW === "number" ? charge.amountKRW : null;
    const paymentKey = typeof charge.relatedPaymentKey === "string" ? charge.relatedPaymentKey : null;

    if (originalChargeCoins <= 0 || originalKRW === null || paymentKey === null) {
      // amountKRW/relatedPaymentKey는 이 기능을 추가하면서부터 새로
      // 남기기 시작한 필드다 — 그 이전에 만들어진 충전 거래는 이 정보가
      // 없어 서버에서 금액을 재계산할 방법이 없으므로 환불을 거부한다.
      throw new HttpsError(
        "failed-precondition",
        "이 거래는 환불에 필요한 정보가 없어 처리할 수 없어요(예전 방식으로 기록된 충전일 수 있어요)."
      );
    }

    const walletSnap = await walletRef.get();
    const currentBalance = (walletSnap.data()?.balance as number | undefined) ?? 0;

    const refundableCoins = Math.min(
      originalChargeCoins - alreadyRefundedCoins,
      currentBalance
    );
    if (refundableCoins <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "이미 다 사용해서 환불 가능한 코인이 없어요."
      );
    }

    const refundKRW = Math.round(
      (originalKRW * refundableCoins) / originalChargeCoins
    );

    // Toss 결제 취소 API — 부분 취소(cancelAmount)를 지정한다. 이 호출의
    // 응답이 "실제로 얼마가 취소됐는지"의 유일한 진짜 출처다.
    const basicAuth = Buffer.from(`${tossSecretKey.value()}:`).toString("base64");
    const tossResponse = await fetch(
      `https://api.tosspayments.com/v1/payments/${paymentKey}/cancel`,
      {
        method: "POST",
        headers: {
          "Authorization": `Basic ${basicAuth}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          cancelReason: reason,
          cancelAmount: refundKRW,
        }),
      }
    );
    const tossBody = await tossResponse.json() as Record<string, unknown>;

    if (!tossResponse.ok) {
      console.error(
        `Toss 환불 실패 (admin=${callerUid}, uid=${uid}, chargeTxId=${chargeTxId}):`,
        tossBody
      );
      // 클라이언트가 실제 Toss 에러를 보고 판단할 수 있도록 메시지를
      // 그대로 넘긴다 — Firestore에는 아무것도 쓰지 않았다.
      throw new HttpsError(
        "aborted",
        typeof tossBody.message === "string" ? tossBody.message : "환불 처리에 실패했어요."
      );
    }

    const cancels = Array.isArray(tossBody.cancels) ? tossBody.cancels : [];
    const lastCancel = cancels[cancels.length - 1] as Record<string, unknown> | undefined;
    const tossCancelTransactionKey =
      typeof lastCancel?.transactionKey === "string" ? lastCancel.transactionKey : null;

    const refundTxRef = db.collection(`users/${uid}/wallet/current/transactions`).doc();

    const result = await db.runTransaction(async (t) => {
      // 모든 읽기를 먼저 — 동시에 같은 건을 다시 환불하려는 요청이 있었는지
      // 최신 상태로 다시 확인한다(Toss 쪽 최종 방어선은 위 주석 참고).
      const [freshChargeSnap, freshWalletSnap] = await Promise.all([
        t.get(chargeRef),
        t.get(walletRef),
      ]);
      const freshAlreadyRefunded =
        (freshChargeSnap.data()?.refundedCoins as number | undefined) ?? 0;
      const freshBalance = (freshWalletSnap.data()?.balance as number | undefined) ?? 0;

      const newRefundedCoins = freshAlreadyRefunded + refundableCoins;
      // 그사이 코인을 더 써서 잔액이 refundableCoins보다 적어졌을 수도
      // 있다 — Toss는 이미 refundKRW만큼 실제로 환불했으므로, 지갑은
      // 0 밑으로 내려가지 않게 바닥만 막고 그대로 차감한다.
      const newBalance = Math.max(0, freshBalance - refundableCoins);
      const newStatus = newRefundedCoins >= originalChargeCoins ? "full" : "partial";

      t.set(walletRef, {balance: newBalance}, {merge: true});
      t.update(chargeRef, {
        refundedCoins: newRefundedCoins,
        refundStatus: newStatus,
      });
      t.create(refundTxRef, {
        type: "refund",
        originalChargeTxId: chargeTxId,
        refundedCoins: refundableCoins,
        refundedKRW: refundKRW,
        tossCancelTransactionKey,
        reason,
        processedBy: callerUid,
        amount: -refundableCoins,
        uid,
        displayName: typeof charge.displayName === "string" ? charge.displayName : "",
        email: typeof charge.email === "string" ? charge.email : "",
        createdAt: FieldValue.serverTimestamp(),
      });

      return {newBalance, refundStatus: newStatus};
    });

    return {
      success: true,
      refundedCoins: refundableCoins,
      refundedKRW: refundKRW,
      newBalance: result.newBalance,
      refundStatus: result.refundStatus,
    };
  }
);

/**
 * 매일 KST 00:20에(랭킹 스냅샷 00:10 직후, 리소스 경합을 피하려고 10분
 * 띄웠다 — 임의로 고른 시각이라 운영상 문제가 있으면 바꿔도 된다) 직전
 * 하루(KST) 동안의 결제/사용/환불을 집계해 revenueSnapshots/{그 날짜}에
 * 남긴다 — admin "정산내역" 탭이 매번 전체 거래를 다시 훑지 않고 이
 * 요약만 읽는다. computeDailyRankingSnapshot과 같은 예약 실행 패턴.
 *
 * collectionGroup('transactions')를 createdAt 범위로만 걸러 그날 생긴
 * 모든 유저의 거래를 한 번에 훑는다 — type별로 나눠 따로 집계한다.
 */
export const computeDailyRevenueSnapshot = onSchedule(
  {schedule: "20 0 * * *", timeZone: "Asia/Seoul"},
  async () => {
    const now = new Date();
    const targetKey = kstDateKey(new Date(now.getTime() - 24 * 60 * 60 * 1000));
    const {start, end} = kstDayBoundsUtc(targetKey);

    const snapshot = await db
      .collectionGroup("transactions")
      .where("createdAt", ">=", start)
      .where("createdAt", "<", end)
      .get();

    let revenueKRW = 0;
    let chargeCount = 0;
    let coinsGranted = 0;
    let coinsSpent = 0;
    let refundedKRW = 0;
    let refundedCoins = 0;

    for (const doc of snapshot.docs) {
      const tx = doc.data();
      switch (tx.type) {
        case "charge":
          chargeCount += 1;
          revenueKRW += typeof tx.amountKRW === "number" ? tx.amountKRW : 0;
          coinsGranted += typeof tx.amount === "number" ? tx.amount : 0;
          break;
        case "purchase":
          coinsSpent += Math.abs(typeof tx.amount === "number" ? tx.amount : 0);
          break;
        case "refund":
          refundedKRW += typeof tx.refundedKRW === "number" ? tx.refundedKRW : 0;
          refundedCoins += typeof tx.refundedCoins === "number" ? tx.refundedCoins : 0;
          break;
        default:
          break;
      }
    }

    await db.collection("revenueSnapshots").doc(targetKey).set({
      revenueKRW,
      chargeCount,
      coinsGranted,
      coinsSpent,
      refundedKRW,
      refundedCoins,
      generatedAt: FieldValue.serverTimestamp(),
    });
  }
);

// ─────────────────────────────────────────────────────────────────────────
// TTS 내레이션 (Typecast) — 노드별로 한 번 생성해서 Storage에 캐시해 두고,
// 그 이후 방문자는 전부 캐시만 재생한다(매 리딩 세션마다 Typecast API를
// 다시 부르지 않는다). BGM/SFX가 "작가가 미리 올린 파일"을 재생하는 것과
// 달리, TTS는 "본문 텍스트로부터 서버가 대신 만들어 주는 파일"이라 이
// 생성/캐싱 자체가 이 기능의 핵심이다.
//
// ✅ **문서 대조 완료**(https://typecast.ai/docs/api-reference/text-to-speech/
// text-to-speech, https://typecast.ai/docs/api-reference/voices/list-voices) —
// 아래 Typecast 호출부(callTypecastTts/fetchTypecastVoiceList)의 엔드포인트
// URL·인증 헤더 이름·요청/응답 필드명을 실제 공식 문서와 대조해 다음을
// 바로잡았다: 보이스 목록 엔드포인트는 /v1/voices가 아니라 /v2/voices다.
// emotion_preset을 쓰려면 prompt.emotion_type을 "preset"으로(Smart Emotion은
// "smart"로) 명시해야 한다 — discriminator 필드라 생략하면 스펙에 정의된
// 동작이 없다. whisper/toneup/tonedown 프리셋은 ssfm-v21에 없고 ssfm-v30
// 에서만 지원돼서 model도 ssfm-v30으로 바꿨다(lib/admin/models/node_effects.dart의
// TtsEmotionPreset과 반드시 같이 맞춰야 한다 — 아래 각주 참고). 그 외(캐싱/
// 해시/Storage 업로드/Firestore 갱신/보안 검증) 구조는 이 프로젝트의 기존
// 함수(confirmCoinCharge 등)와 같은 검증된 패턴이다.
// ─────────────────────────────────────────────────────────────────────────

// Typecast(TTS) API 키 — 절대 코드에 하드코딩하지 않는다. 배포 전에
// `firebase functions:secrets:set TYPECAST_API_KEY`로 실제 값을 주입해야
// synthesizeNodeTts/refreshTypecastVoices(Scheduled)가 동작한다.
const typecastApiKey = defineSecret("TYPECAST_API_KEY");

const TYPECAST_API_BASE = "https://api.typecast.ai";

/** 블록(문단) 하나가 실제로 어떤 보이스/감정/피치/템포로 낭독될지 확정된
 * 값 — 해석 순서는 블록 오버라이드 → 노드의 effects.tts → 팩의
 * defaultTtsVoiceId/중립값이다(요청 사양: "Resolution order per block").
 * 텍스트가 없는 블록(이미지 등)이나 어느 단계에서도 보이스를 못 찾은
 * 블록은 이 타입으로 만들어지지 않는다(resolveBlockTts가 null을 돌려준다). */
type ResolvedBlockTts = {
  text: string;
  voiceId: string;
  emotion: string | null;
  emotionIntensity: number;
  pitch: number;
  tempo: number;
};

/** 블록 하나 + 노드 effects.tts + 팩 기본 보이스를 합쳐 이 블록이 실제로
 * 낭독될 설정을 확정한다. 세 단계 모두 "필드 단위"로 개별 폴백한다(예:
 * 블록이 voiceId만 재정의하고 감정은 재정의하지 않았으면, 감정은 노드
 * 설정을 그대로 물려받는다) — "블록에 뭐라도 설정하면 전부 블록 값을
 * 쓴다"가 아니다. 텍스트가 비어 있거나(이미지 블록 등) 세 단계 어디서도
 * voiceId를 못 찾으면 null(이 블록은 낭독 대상에서 빠진다). */
function resolveBlockTts(
  block: Record<string, unknown>,
  nodeEffectsTts: Record<string, unknown> | null | undefined,
  packDefaultVoiceId: string | null
): ResolvedBlockTts | null {
  const text = typeof block.text === "string" ? block.text.trim() : "";
  if (!text) return null;

  const blockVoiceId = typeof block.ttsVoiceId === "string" ? block.ttsVoiceId : null;
  const nodeVoiceId = typeof nodeEffectsTts?.voiceId === "string" ? nodeEffectsTts.voiceId : null;
  const voiceId = blockVoiceId ?? nodeVoiceId ?? packDefaultVoiceId;
  if (!voiceId) return null;

  const blockEmotion = typeof block.ttsEmotion === "string" ? block.ttsEmotion : null;
  const nodeEmotion = typeof nodeEffectsTts?.emotion === "string" ? nodeEffectsTts.emotion : null;
  const emotion = blockEmotion ?? nodeEmotion;

  const blockIntensity =
    typeof block.ttsEmotionIntensity === "number" ? block.ttsEmotionIntensity : null;
  const nodeIntensity =
    typeof nodeEffectsTts?.emotionIntensity === "number" ? nodeEffectsTts.emotionIntensity : null;
  const emotionIntensity = blockIntensity ?? nodeIntensity ?? 1.0;

  const blockPitch = typeof block.ttsPitch === "number" ? block.ttsPitch : null;
  const nodePitch = typeof nodeEffectsTts?.pitch === "number" ? nodeEffectsTts.pitch : null;
  const pitch = blockPitch ?? nodePitch ?? 0;

  const blockTempo = typeof block.ttsTempo === "number" ? block.ttsTempo : null;
  const nodeTempo = typeof nodeEffectsTts?.tempo === "number" ? nodeEffectsTts.tempo : null;
  const tempo = blockTempo ?? nodeTempo ?? 1.0;

  return {text, voiceId, emotion, emotionIntensity, pitch, tempo};
}

/** 노드의 blocks 배열 전체를 순서대로 resolveBlockTts에 통과시킨다.
 * [nonEmptyTextBlockCount](텍스트가 있는 블록 수)보다 [resolved]가 짧으면
 * 일부 블록이 voiceId를 못 찾고 조용히 빠진 것이다 — 호출부가 이 차이를
 * 보고 에러를 낼지 판단한다(침묵하고 일부 문장만 낭독하면 저자가 눈치채기
 * 어렵다). */
function resolveAllBlocksTts(
  blocks: unknown,
  nodeEffectsTts: Record<string, unknown> | null | undefined,
  packDefaultVoiceId: string | null
): {resolved: ResolvedBlockTts[]; nonEmptyTextBlockCount: number} {
  if (!Array.isArray(blocks)) return {resolved: [], nonEmptyTextBlockCount: 0};
  let nonEmptyTextBlockCount = 0;
  const resolved: ResolvedBlockTts[] = [];
  for (const b of blocks) {
    const block = b as Record<string, unknown>;
    if (typeof block.text === "string" && block.text.trim().length > 0) {
      nonEmptyTextBlockCount += 1;
    }
    const r = resolveBlockTts(block, nodeEffectsTts, packDefaultVoiceId);
    if (r) resolved.push(r);
  }
  return {resolved, nonEmptyTextBlockCount};
}

/** 연속된 블록 중 보이스/감정/강도/피치/템포가 완전히 같은 것들을 하나의
 * Typecast 호출(세그먼트)로 묶는다 — 다중 보이스 노드라도 화자가 안 바뀌는
 * 구간은 API 호출 한 번으로 합쳐서 요청 수를 줄인다(요청 사양). 설정이
 * 하나라도 다르면 새 세그먼트로 끊는다. */
type TtsSegment = {
  text: string;
  voiceId: string;
  emotion: string | null;
  emotionIntensity: number;
  pitch: number;
  tempo: number;
};

function sameTtsSettings(a: ResolvedBlockTts, b: ResolvedBlockTts): boolean {
  return (
    a.voiceId === b.voiceId &&
    a.emotion === b.emotion &&
    a.emotionIntensity === b.emotionIntensity &&
    a.pitch === b.pitch &&
    a.tempo === b.tempo
  );
}

function groupIntoSegments(blocks: ResolvedBlockTts[]): TtsSegment[] {
  const segments: TtsSegment[] = [];
  for (const block of blocks) {
    const last = segments[segments.length - 1];
    if (last && sameTtsSettings(last, block)) {
      last.text = `${last.text}. ${block.text}`;
    } else {
      segments.push({...block});
    }
  }
  return segments;
}

/** 캐시 유효성 판단 기준 — 블록별로 실제 적용될 텍스트+보이스/감정/피치/
 * 템포 전체(세그먼트로 묶기 전, 블록 단위 그대로)를 통째로 해시한다 — 이
 * 중 어느 블록의 설정 하나라도 바뀌면 다른 해시가 나와서 캐시를 못 쓰고
 * 다시 생성한다(요청 사양: "cache-hash must now be computed over the full
 * resolved per-block settings"). */
function hashTtsInput(blocks: ResolvedBlockTts[]): string {
  return createHash("sha256").update(JSON.stringify(blocks)).digest("hex");
}

/**
 * Admin SDK에는 클라이언트 SDK의 getDownloadURL() 같은 헬퍼가 없다 — 직접
 * firebaseStorageDownloadTokens 메타데이터를 심고, 클라이언트가 만드는 것과
 * 똑같은 형식의 다운로드 URL을 조립한다. 그래야 별도 서명 URL(만료 있음)이나
 * 공개 파일(누구나 읽음, Storage 규칙을 아예 안 탐)을 쓰지 않고, 기존
 * images/sfxLibrary/bgmLibrary와 똑같이 Storage 보안 규칙
 * (`request.auth != null`)만으로 읽기가 통제된다.
 */
async function uploadAndGetDownloadUrl(
  path: string,
  bytes: Buffer,
  contentType: string
): Promise<string> {
  const bucket = getStorage().bucket();
  const file = bucket.file(path);
  const token = randomUUID();

  await file.save(bytes, {
    metadata: {
      contentType,
      metadata: {firebaseStorageDownloadTokens: token},
    },
  });

  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
    `${encodeURIComponent(path)}?alt=media&token=${token}`
  );
}

/**
 * Typecast TTS 생성 API를 non-streaming으로 호출해 오디오 바이트를 통째로
 * 받는다(사전 생성/캐싱 용도라 스트리밍이 필요 없다 — 요청 사양). 실패하면
 * 예외를 던진다(호출부가 HttpsError로 감싼다).
 */
async function callTypecastTts(params: {
  apiKey: string;
  text: string;
  voiceId: string;
  emotion: string | null;
  emotionIntensity: number;
  pitch: number;
  tempo: number;
  audioFormat: "mp3" | "wav";
}): Promise<Buffer> {
  // prompt는 discriminator 필드(emotion_type)로 갈리는 두 모양 중 하나다 —
  // "preset"(emotion_preset/emotion_intensity 사용)이거나 "smart"(Typecast가
  // 본문만 보고 감정을 자동 추론, 그 외 필드 없음). 이 필드를 아예 생략했을
  // 때의 동작은 문서에 정의돼 있지 않아서, Smart Emotion도 명시적으로
  // emotion_type: "smart"를 보낸다.
  const prompt = params.emotion ?
    {
      emotion_type: "preset",
      emotion_preset: params.emotion,
      emotion_intensity: params.emotionIntensity,
    } :
    {emotion_type: "smart"};

  if (!params.apiKey) {
    console.error("Typecast API 키가 비어 있어요 — TYPECAST_API_KEY 시크릿을 확인하세요.");
  }
  console.log(
    `Typecast TTS 요청: voiceId=${params.voiceId}, textLength=${params.text.length}, ` +
      `prompt=${JSON.stringify(prompt)}, pitch=${params.pitch}, tempo=${params.tempo}`
  );

  const response = await fetch(`${TYPECAST_API_BASE}/v1/text-to-speech`, {
    method: "POST",
    headers: {
      "X-API-KEY": params.apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text: params.text,
      voice_id: params.voiceId,
      // whisper/toneup/tonedown 프리셋은 ssfm-v21에 없고 ssfm-v30에서만
      // 지원된다(TtsEmotionPreset과 반드시 같이 맞출 것 — 위 파일 상단 각주
      // 참고).
      model: "ssfm-v30",
      prompt,
      output: {
        audio_pitch: params.pitch,
        audio_tempo: params.tempo,
        audio_format: params.audioFormat,
      },
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`Typecast TTS 응답: status=${response.status}, body=${errorBody.slice(0, 500)}`);
    throw new Error(`Typecast TTS 호출 실패 (${response.status}): ${errorBody}`);
  }

  const audioBuffer = Buffer.from(await response.arrayBuffer());
  console.log(
    `Typecast TTS 응답: status=${response.status}, format=${params.audioFormat}, ` +
      `contentType=${response.headers.get("content-type")}, bytes=${audioBuffer.length}`
  );
  return audioBuffer;
}

/**
 * WAV(RIFF/PCM) 파일의 fmt/data 청크를 파싱한다 — Typecast의 wav 출력은
 * 항상 16-bit PCM mono 44100Hz로 문서화돼 있지만(세그먼트마다 보이스/감정이
 * 달라도 이 포맷 자체는 고정), 방어적으로 fmt 청크 값을 그대로 읽어서 쓴다.
 */
function parseWavPcm(buffer: Buffer): {
  sampleRate: number;
  numChannels: number;
  bitsPerSample: number;
  data: Buffer;
} {
  if (
    buffer.length < 12 ||
    buffer.toString("ascii", 0, 4) !== "RIFF" ||
    buffer.toString("ascii", 8, 12) !== "WAVE"
  ) {
    throw new Error("Typecast wav 응답이 올바른 RIFF/WAVE 파일이 아니에요.");
  }

  let offset = 12;
  let fmt: {sampleRate: number; numChannels: number; bitsPerSample: number} | null = null;
  let data: Buffer | null = null;
  while (offset + 8 <= buffer.length) {
    const chunkId = buffer.toString("ascii", offset, offset + 4);
    const chunkSize = buffer.readUInt32LE(offset + 4);
    const chunkStart = offset + 8;
    if (chunkId === "fmt ") {
      fmt = {
        numChannels: buffer.readUInt16LE(chunkStart + 2),
        sampleRate: buffer.readUInt32LE(chunkStart + 4),
        bitsPerSample: buffer.readUInt16LE(chunkStart + 14),
      };
    } else if (chunkId === "data") {
      data = buffer.subarray(chunkStart, chunkStart + chunkSize);
    }
    // 청크는 짝수 바이트로 정렬된다(홀수 크기면 패딩 1바이트가 붙는다).
    offset = chunkStart + chunkSize + (chunkSize % 2);
  }

  if (!fmt || !data) {
    throw new Error("Typecast wav 응답에서 fmt/data 청크를 못 찾았어요.");
  }
  return {...fmt, data};
}

/** parseWavPcm이 읽은 포맷 정보로 새 WAV 헤더(44바이트, 확장 필드 없는
 * 표준 PCM 헤더)를 만든다. */
function buildWavHeader(
  dataLength: number,
  sampleRate: number,
  numChannels: number,
  bitsPerSample: number
): Buffer {
  const byteRate = (sampleRate * numChannels * bitsPerSample) / 8;
  const blockAlign = (numChannels * bitsPerSample) / 8;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(36 + dataLength, 4);
  header.write("WAVE", 8, "ascii");
  header.write("fmt ", 12, "ascii");
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(numChannels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write("data", 36, "ascii");
  header.writeUInt32LE(dataLength, 40);
  return header;
}

/**
 * 여러 wav 세그먼트를 순서대로 이어 붙여 하나의 wav 파일로 만든다 — 각
 * 세그먼트의 PCM 데이터만 뽑아 이어 붙이고 새 헤더 하나로 감싼다(개별
 * 세그먼트 헤더는 버린다). 세그먼트가 하나뿐이면 그대로 돌려준다.
 */
function concatenateWavSegments(segments: Buffer[]): Buffer {
  if (segments.length === 1) return segments[0];
  const parsed = segments.map(parseWavPcm);
  const {sampleRate, numChannels, bitsPerSample} = parsed[0];
  const data = Buffer.concat(parsed.map((p) => p.data));
  const header = buildWavHeader(data.length, sampleRate, numChannels, bitsPerSample);
  return Buffer.concat([header, data]);
}

/**
 * 세그먼트 목록을 실제 오디오 파일 하나로 만든다. 세그먼트가 하나뿐이면
 * (다중 보이스를 안 쓰는 절대다수의 노드) 기존 그대로 mp3 하나만 요청한다
 * — 파일이 작고 이미 검증된 경로다. 세그먼트가 둘 이상이면(블록별 보이스
 * 오버라이드로 화자가 바뀌는 노드) wav로 받아 이어 붙인다 — mp3는 프레임을
 * 그냥 이어 붙이면 디코더에 따라 끊김/잡음이 날 수 있어(ID3/Xing 헤더 등)
 * 신뢰할 수 없고, ffmpeg 같은 네이티브 의존성 없이 안전하게 이어 붙일 수
 * 있는 포맷이 PCM wav뿐이다.
 */
async function synthesizeNodeAudio(params: {
  apiKey: string;
  segments: TtsSegment[];
}): Promise<{bytes: Buffer; extension: "mp3" | "wav"; contentType: string}> {
  if (params.segments.length === 0) {
    throw new Error("낭독할 세그먼트가 없어요.");
  }

  if (params.segments.length === 1) {
    const seg = params.segments[0];
    const bytes = await callTypecastTts({apiKey: params.apiKey, ...seg, audioFormat: "mp3"});
    return {bytes, extension: "mp3", contentType: "audio/mpeg"};
  }

  console.log(
    `synthesizeNodeAudio: 다중 보이스 세그먼트 ${params.segments.length}개, wav로 이어 붙임.`
  );
  const wavBuffers = await Promise.all(
    params.segments.map((seg) =>
      callTypecastTts({apiKey: params.apiKey, ...seg, audioFormat: "wav"})
    )
  );
  const bytes = concatenateWavSegments(wavBuffers);
  return {bytes, extension: "wav", contentType: "audio/wav"};
}

/**
 * 캐시 필드(officialUrl/officialHash 또는 previewUrl/previewHash — 호출부가
 * 어느 쌍을 넘기든 상관없다)를 보고 재사용 가능한지 먼저 확인한 뒤, 아니면
 * 새로 생성해 업로드한다 — synthesizeNodeTts(리더 폴백)/previewNodeTts(작가
 * 미리듣기)/onNodeApprovedGenerateTts(승인 시점 생성) 셋 다 이 함수 하나를
 * 공유한다.
 */
async function synthesizeOrReuseTts(params: {
  apiKey: string;
  storagePathBase: string;
  resolvedBlocks: ResolvedBlockTts[];
  cachedUrl: string | null;
  cachedHash: string | null;
}): Promise<{audioUrl: string; cached: boolean; hash: string}> {
  const hash = hashTtsInput(params.resolvedBlocks);
  if (params.cachedUrl && params.cachedHash === hash) {
    return {audioUrl: params.cachedUrl, cached: true, hash};
  }

  const segments = groupIntoSegments(params.resolvedBlocks);
  const {bytes, extension, contentType} = await synthesizeNodeAudio({
    apiKey: params.apiKey,
    segments,
  });
  const audioUrl = await uploadAndGetDownloadUrl(
    `${params.storagePathBase}.${extension}`,
    bytes,
    contentType
  );
  return {audioUrl, cached: false, hash};
}

/**
 * 노드 하나의 내레이션 오디오를 준비해서 URL을 돌려준다 — 캐시가 이미
 * 유효하면(ttsAudioGeneratedForBodyHash가 지금 계산한 해시와 같음) Typecast를
 * 아예 호출하지 않고 기존 ttsAudioUrl만 돌려준다. 리더 화면이 TTS 재생
 * 버튼을 누를 때마다 이 함수를 그대로 부른다 — "이미 생성됐는지"를
 * 클라이언트가 미리 판단하지 않는다(그 판단 자체가 이 함수의 일이다).
 *
 * 항상 **liveSnapshot**(마지막으로 승인된 콘텐츠)만 읽는다 — 아직 승인 안
 * 된 draft 본문으로 내레이션을 만들면 독자가 실제로 보는 글과 다른 오디오가
 * 나온다(요청 사양: "TTS should always match what readers actually see").
 */
export const synthesizeNodeTts = onCall(
  {secrets: [typecastApiKey]},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }

    const data = request.data as {packId?: unknown; nodeId?: unknown};
    const {packId, nodeId} = data;
    if (
      typeof packId !== "string" || packId.length === 0 ||
      typeof nodeId !== "string" || nodeId.length === 0
    ) {
      throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
    }

    console.log(`synthesizeNodeTts 호출: packId=${packId}, nodeId=${nodeId}, uid=${uid}`);

    const nodeRef = db
      .collection("storyPacks")
      .doc(packId)
      .collection("nodes")
      .doc(nodeId);
    const [packSnap, nodeSnap] = await Promise.all([
      db.collection("storyPacks").doc(packId).get(),
      nodeRef.get(),
    ]);
    if (!nodeSnap.exists) {
      console.warn(`synthesizeNodeTts: 존재하지 않는 노드 (packId=${packId}, nodeId=${nodeId}).`);
      throw new HttpsError("not-found", "존재하지 않는 노드예요.");
    }

    const nodeData = nodeSnap.data()!;
    const liveSnapshot = nodeData.liveSnapshot as Record<string, unknown> | undefined;
    if (!liveSnapshot) {
      // 발행(승인)된 적 없는 노드 — 리더가 애초에 볼 수 없는 노드라 TTS를
      // 만들 이유가 없다.
      console.warn(
        `synthesizeNodeTts: liveSnapshot이 없는 노드 (packId=${packId}, nodeId=${nodeId}).`
      );
      throw new HttpsError(
        "failed-precondition",
        "아직 발행되지 않은 노드는 내레이션을 만들 수 없어요."
      );
    }

    const packDefaultVoiceId =
      typeof packSnap.data()?.liveMetadata?.defaultTtsVoiceId === "string" ?
        packSnap.data()!.liveMetadata.defaultTtsVoiceId :
        null;
    const nodeEffects = liveSnapshot.effects as Record<string, unknown> | undefined;
    const nodeEffectsTts = nodeEffects?.tts as Record<string, unknown> | null | undefined;

    const {resolved, nonEmptyTextBlockCount} = resolveAllBlocksTts(
      liveSnapshot.blocks,
      nodeEffectsTts,
      packDefaultVoiceId
    );
    if (nonEmptyTextBlockCount === 0) {
      console.warn(`synthesizeNodeTts: 본문이 비어 있음 (packId=${packId}, nodeId=${nodeId}).`);
      throw new HttpsError("failed-precondition", "본문이 비어 있어요.");
    }
    if (resolved.length === 0) {
      console.warn(
        `synthesizeNodeTts: 보이스 미설정 (packId=${packId}, nodeId=${nodeId}, ` +
          `packDefaultVoiceId=${packDefaultVoiceId}).`
      );
      throw new HttpsError(
        "failed-precondition",
        "이 스토리팩에 기본 내레이터 보이스가 설정돼 있지 않아요."
      );
    }
    if (resolved.length < nonEmptyTextBlockCount) {
      console.warn(
        `synthesizeNodeTts: 일부 문단만 보이스 해석됨 (packId=${packId}, nodeId=${nodeId}, ` +
          `resolved=${resolved.length}/${nonEmptyTextBlockCount}).`
      );
      throw new HttpsError(
        "failed-precondition",
        "일부 문단에 사용할 보이스를 찾지 못했어요 — 노드 기본 보이스나 팩 기본 보이스를 설정해주세요."
      );
    }

    const cachedUrl = typeof nodeData.ttsAudioUrl === "string" ? nodeData.ttsAudioUrl : null;
    const cachedHash =
      typeof nodeData.ttsAudioGeneratedForBodyHash === "string" ?
        nodeData.ttsAudioGeneratedForBodyHash :
        null;

    let result;
    try {
      result = await synthesizeOrReuseTts({
        apiKey: typecastApiKey.value(),
        storagePathBase: `admin/story_tts/${packId}/${nodeId}`,
        resolvedBlocks: resolved,
        cachedUrl,
        cachedHash,
      });
    } catch (error) {
      console.error(`Typecast TTS 생성 실패 (packId=${packId}, nodeId=${nodeId}):`, error);
      throw new HttpsError("aborted", "내레이션 생성에 실패했어요.");
    }

    if (result.cached) {
      console.log(`synthesizeNodeTts: 캐시 히트 (packId=${packId}, nodeId=${nodeId}).`);
    } else {
      console.log(`synthesizeNodeTts: 캐시 미스, 새로 생성함 (packId=${packId}, nodeId=${nodeId}).`);
      await nodeRef.update({
        ttsAudioUrl: result.audioUrl,
        ttsAudioGeneratedForBodyHash: result.hash,
      });
    }

    return {audioUrl: result.audioUrl, cached: result.cached};
  }
);

/**
 * 노드 편집기의 "미리듣기" 버튼이 부른다(요청 사양 Part 1-1) —
 * synthesizeNodeTts와 달리 Firestore의 liveSnapshot을 읽지 않는다. 작가가
 * 지금 타이핑 중인 초안은 임시저장 전까지 Firestore에 없기 때문에
 * (NodeEditSessionCache, 메모리에만 있음) 클라이언트가 현재 편집 중인
 * blocks/effects.tts를 요청 본문에 직접 실어 보낸다. 결과는
 * ttsAudioUrl(독자용 공식 캐시)이 아니라 ttsPreviewAudioUrl/
 * ttsPreviewAudioGeneratedForBodyHash에 저장한다 — "잠정적" 캐시라는 뜻이다.
 * 나중에 이 초안이 그대로 승인되면(해시가 같으면) onNodeApprovedGenerateTts
 * 트리거가 Typecast를 다시 부르지 않고 이 파일을 그대로 ttsAudioUrl로
 * 승격한다.
 */
export const previewNodeTts = onCall(
  {secrets: [typecastApiKey]},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    if (!(await isCallerAuthorOrAdmin(uid))) {
      throw new HttpsError("permission-denied", "작가 또는 관리자만 사용할 수 있어요.");
    }

    const data = request.data as {
      packId?: unknown;
      nodeId?: unknown;
      blocks?: unknown;
      effectsTts?: unknown;
      defaultTtsVoiceId?: unknown;
    };
    const {packId, nodeId, blocks} = data;
    if (
      typeof packId !== "string" || packId.length === 0 ||
      typeof nodeId !== "string" || nodeId.length === 0 ||
      !Array.isArray(blocks)
    ) {
      throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
    }
    const effectsTts = (data.effectsTts ?? null) as Record<string, unknown> | null;
    const packDefaultVoiceId =
      typeof data.defaultTtsVoiceId === "string" ? data.defaultTtsVoiceId : null;

    console.log(`previewNodeTts 호출: packId=${packId}, nodeId=${nodeId}, uid=${uid}`);

    const {resolved, nonEmptyTextBlockCount} = resolveAllBlocksTts(
      blocks,
      effectsTts,
      packDefaultVoiceId
    );
    if (nonEmptyTextBlockCount === 0) {
      throw new HttpsError("failed-precondition", "본문이 비어 있어요.");
    }
    if (resolved.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "이 스토리팩에 기본 내레이터 보이스가 설정돼 있지 않아요."
      );
    }
    if (resolved.length < nonEmptyTextBlockCount) {
      throw new HttpsError(
        "failed-precondition",
        "일부 문단에 사용할 보이스를 찾지 못했어요 — 노드 기본 보이스나 팩 기본 보이스를 설정해주세요."
      );
    }

    const nodeRef = db.collection("storyPacks").doc(packId).collection("nodes").doc(nodeId);
    const nodeSnap = await nodeRef.get();
    if (!nodeSnap.exists) {
      throw new HttpsError("not-found", "존재하지 않는 노드예요.");
    }
    const nodeData = nodeSnap.data()!;
    const cachedUrl =
      typeof nodeData.ttsPreviewAudioUrl === "string" ? nodeData.ttsPreviewAudioUrl : null;
    const cachedHash =
      typeof nodeData.ttsPreviewAudioGeneratedForBodyHash === "string" ?
        nodeData.ttsPreviewAudioGeneratedForBodyHash :
        null;

    let result;
    try {
      result = await synthesizeOrReuseTts({
        apiKey: typecastApiKey.value(),
        // 독자용 파일(admin/story_tts/{packId}/{nodeId}.*)과 겹치지 않게
        // preview 하위 경로를 따로 둔다 — 승인 시점에 재사용할 때는 URL을
        // 그대로 ttsAudioUrl에 복사할 뿐, 파일을 옮기지 않는다.
        storagePathBase: `admin/story_tts_preview/${packId}/${nodeId}`,
        resolvedBlocks: resolved,
        cachedUrl,
        cachedHash,
      });
    } catch (error) {
      console.error(
        `Typecast TTS 미리듣기 생성 실패 (packId=${packId}, nodeId=${nodeId}):`,
        error
      );
      throw new HttpsError("aborted", "미리듣기 생성에 실패했어요.");
    }

    if (!result.cached) {
      await nodeRef.update({
        ttsPreviewAudioUrl: result.audioUrl,
        ttsPreviewAudioGeneratedForBodyHash: result.hash,
      });
    }

    return {audioUrl: result.audioUrl, cached: result.cached};
  }
);

/**
 * 노드가 승인돼 liveSnapshot이 갱신될 때마다(approveNode,
 * lib/admin/data/admin_story_repository.dart — 클라이언트가 직접 Firestore를
 * 쓰는 승인 흐름이라 Cloud Function 훅이 아니라 문서 변경 트리거로 잡는다)
 * 그 시점에 바로 TTS를 만들어 둔다(요청 사양 Part 1-2) — 첫 독자가 방문할
 * 때 생성을 기다리지 않게 하려는 목적. synthesizeNodeTts는 여전히 남아있다
 * — 이 트리거가 실패하거나(예: Typecast 일시 장애) 이 기능이 추가되기 전에
 * 이미 승인된 옛 노드를 위한 폴백 경로다(요청 사양: "keep generation-on-
 * demand as a fallback only").
 *
 * before/after의 status/liveSnapshot이 둘 다 같으면(= 이 트리거 자신이 방금
 * ttsAudioUrl만 갱신한 두 번째 이벤트, 또는 무관한 필드만 바뀐 쓰기) 그냥
 * 건너뛴다 — 안 그러면 매번 자기 자신의 쓰기가 다시 트리거를 불러 무한
 * 루프가 된다.
 */
export const onNodeApprovedGenerateTts = onDocumentWritten(
  {document: "storyPacks/{packId}/nodes/{nodeId}", secrets: [typecastApiKey]},
  async (event) => {
    const after = event.data?.after;
    if (!after || !after.exists) return; // 삭제된 노드 — 만들 이유 없음.
    const afterData = after.data()!;
    if (afterData.status !== "published") return;

    const before = event.data?.before;
    const beforeData = before?.exists ? before.data()! : null;
    const statusUnchanged = beforeData?.status === afterData.status;
    const liveSnapshotUnchanged =
      JSON.stringify(beforeData?.liveSnapshot ?? null) ===
      JSON.stringify(afterData.liveSnapshot ?? null);
    if (statusUnchanged && liveSnapshotUnchanged) return;

    const {packId, nodeId} = event.params;
    const liveSnapshot = afterData.liveSnapshot as Record<string, unknown> | undefined;
    if (!liveSnapshot) return;

    console.log(`onNodeApprovedGenerateTts: 승인 감지 (packId=${packId}, nodeId=${nodeId}).`);

    const packSnap = await db.collection("storyPacks").doc(packId).get();
    const packDefaultVoiceId =
      typeof packSnap.data()?.liveMetadata?.defaultTtsVoiceId === "string" ?
        packSnap.data()!.liveMetadata.defaultTtsVoiceId :
        null;
    const nodeEffects = liveSnapshot.effects as Record<string, unknown> | undefined;
    const nodeEffectsTts = nodeEffects?.tts as Record<string, unknown> | null | undefined;

    const {resolved, nonEmptyTextBlockCount} = resolveAllBlocksTts(
      liveSnapshot.blocks,
      nodeEffectsTts,
      packDefaultVoiceId
    );
    if (nonEmptyTextBlockCount === 0 || resolved.length < nonEmptyTextBlockCount) {
      // 본문이 비었거나 일부/전체 블록이 보이스를 못 찾았으면 조용히
      // 건너뛴다 — TTS는 부가 기능이라 이것 때문에 승인 자체를 막지 않는다.
      // 리더가 방문하면 synthesizeNodeTts가 같은 조건으로 다시 시도하다
      // 같은 이유로 실패하겠지만, 그건 저자가 노드 편집기에서 직접 확인할
      // 문제다.
      console.warn(
        `onNodeApprovedGenerateTts: 본문/보이스 조건 미충족으로 건너뜀 ` +
          `(packId=${packId}, nodeId=${nodeId}).`
      );
      return;
    }

    const nodeRef = db.collection("storyPacks").doc(packId).collection("nodes").doc(nodeId);
    const hash = hashTtsInput(resolved);

    const officialHash =
      typeof afterData.ttsAudioGeneratedForBodyHash === "string" ?
        afterData.ttsAudioGeneratedForBodyHash :
        null;
    if (officialHash === hash && typeof afterData.ttsAudioUrl === "string") {
      console.log(
        `onNodeApprovedGenerateTts: 이미 최신 캐시 존재 (packId=${packId}, nodeId=${nodeId}).`
      );
      return;
    }

    const previewHash =
      typeof afterData.ttsPreviewAudioGeneratedForBodyHash === "string" ?
        afterData.ttsPreviewAudioGeneratedForBodyHash :
        null;
    const previewUrl =
      typeof afterData.ttsPreviewAudioUrl === "string" ? afterData.ttsPreviewAudioUrl : null;
    if (previewHash === hash && previewUrl) {
      console.log(
        `onNodeApprovedGenerateTts: 미리듣기 캐시 재사용 (packId=${packId}, nodeId=${nodeId}).`
      );
      await nodeRef.update({ttsAudioUrl: previewUrl, ttsAudioGeneratedForBodyHash: hash});
      return;
    }

    try {
      const segments = groupIntoSegments(resolved);
      const {bytes, extension, contentType} = await synthesizeNodeAudio({
        apiKey: typecastApiKey.value(),
        segments,
      });
      const audioUrl = await uploadAndGetDownloadUrl(
        `admin/story_tts/${packId}/${nodeId}.${extension}`,
        bytes,
        contentType
      );
      await nodeRef.update({ttsAudioUrl: audioUrl, ttsAudioGeneratedForBodyHash: hash});
      console.log(`onNodeApprovedGenerateTts: 새로 생성함 (packId=${packId}, nodeId=${nodeId}).`);
    } catch (error) {
      // 실패해도 승인 자체는 이미 끝난 뒤라 되돌리지 않는다 —
      // synthesizeNodeTts 폴백이 리더의 첫 방문 때 다시 시도한다.
      console.error(
        `onNodeApprovedGenerateTts: TTS 생성 실패, synthesizeNodeTts 폴백에 맡김 ` +
          `(packId=${packId}, nodeId=${nodeId}):`,
        error
      );
    }
  }
);

/** Typecast의 보이스 목록 API를 호출해 {id, name} 배열로 정규화한다.
 *
 * ⚠️ 디버그 로그: 이 함수는 "보이스 목록이 비어 있어요"가 실제로 (a) API
 * 호출 자체가 실패하는지, (b) 200은 오는데 응답 모양이 예상과 달라
 * 정규화 단계에서 전부 걸러지는지, (c) Typecast 계정에 진짜로 등록된
 * 보이스가 0개인지 구분이 안 됐던 문제 때문에 각 단계마다 로그를 남긴다.
 * API 키 값 자체는 절대 로그에 남기지 않는다(길이만 확인).
 */
async function fetchTypecastVoiceList(
  apiKey: string
): Promise<Array<{id: string; name: string}>> {
  if (!apiKey) {
    console.error("Typecast API 키가 비어 있어요 — TYPECAST_API_KEY 시크릿을 확인하세요.");
  } else {
    console.log(`Typecast API 키 확인됨 (길이 ${apiKey.length}자, 값은 로그에 남기지 않음).`);
  }

  // 보이스 목록은 /v1/voices가 아니라 /v2/voices다(문서 대조로 확인) —
  // TTS 생성 엔드포인트(/v1/text-to-speech)와 버전이 다르다는 점에 주의.
  const url = `${TYPECAST_API_BASE}/v2/voices`;
  console.log(`Typecast 보이스 목록 요청: GET ${url}`);
  const response = await fetch(url, {
    headers: {"X-API-KEY": apiKey},
  });

  const rawBody = await response.text();
  console.log(
    `Typecast 보이스 목록 응답: status=${response.status}, ` +
      `bodyPreview=${rawBody.slice(0, 500)}`
  );

  if (!response.ok) {
    throw new Error(`Typecast 보이스 목록 조회 실패 (${response.status}): ${rawBody}`);
  }

  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch (error) {
    console.error("Typecast 보이스 목록 응답이 JSON이 아니에요:", error);
    return [];
  }

  const list = Array.isArray(body) ?
    body :
    ((body as {voices?: unknown} | null)?.voices ?? null);
  if (!Array.isArray(list)) {
    console.warn(
      "Typecast 보이스 목록 응답이 배열도 {voices: [...]}도 아니에요 — " +
        `실제 응답 최상위 키: ${
          body && typeof body === "object" ? Object.keys(body).join(", ") : typeof body
        }`
    );
    return [];
  }
  console.log(`Typecast가 보이스 ${list.length}개를 응답으로 돌려줬어요(정규화 전).`);

  const normalized = list
    .map((v) => {
      const voice = v as Record<string, unknown>;
      const id =
        typeof voice.voice_id === "string" ?
          voice.voice_id :
          typeof voice.id === "string" ?
            voice.id :
            null;
      const name =
        typeof voice.voice_name === "string" ?
          voice.voice_name :
          typeof voice.name === "string" ?
            voice.name :
            null;
      if (!id || !name) return null;
      return {id, name};
    })
    .filter((v): v is {id: string; name: string} => v !== null);

  if (normalized.length !== list.length) {
    console.warn(
      `Typecast 보이스 ${list.length}개 중 ${
        list.length - normalized.length
      }개가 voice_id/voice_name(또는 id/name) 필드를 못 찾아 걸러졌어요 — ` +
        `첫 항목 예시: ${JSON.stringify(list[0])}`
    );
  }

  return normalized;
}

/** ttsVoiceCache/typecast 문서를 새로 받아온 목록으로 덮어쓴다 —
 * refreshTypecastVoiceCacheScheduled/refreshTypecastVoices 둘 다 공유하는
 * 실제 로직. */
async function refreshTypecastVoiceCache(apiKey: string): Promise<void> {
  const voices = await fetchTypecastVoiceList(apiKey);
  console.log(`ttsVoiceCache/typecast에 보이스 ${voices.length}개를 저장해요.`);
  await db.collection("ttsVoiceCache").doc("typecast").set({
    voices,
    fetchedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * 매일 KST 03:00에 Typecast 보이스 목록을 다시 받아 ttsVoiceCache/typecast에
 * 캐시해 둔다 — admin/작가 화면이 보이스를 고를 때마다 Typecast API를 부르지
 * 않고 이 캐시 문서만 구독하면 되게 하려는 목적(요청 사양: "cache this list
 * server-side periodically"). 임의로 고른 새벽 시각 — 운영상 문제가 있으면
 * 바꿔도 된다.
 */
export const refreshTypecastVoiceCacheScheduled = onSchedule(
  {schedule: "0 3 * * *", timeZone: "Asia/Seoul", secrets: [typecastApiKey]},
  async () => {
    await refreshTypecastVoiceCache(typecastApiKey.value());
  }
);

/**
 * 위 예약 실행과 같은 로직을 수동으로 즉시 트리거한다 — 최초 배포 직후(예약
 * 실행을 하루 기다리지 않고) 캐시를 채우거나, 목록이 바뀌었는데 새벽까지
 * 못 기다릴 때 admin/작가 화면의 "새로고침" 버튼이 부른다. author/admin
 * 누구나 부를 수 있다 — 오디오 생성이 아니라 비용이 낮은 메타데이터 조회일
 * 뿐이라 admin 전용으로 좁힐 필요가 없다고 판단했다.
 */
export const refreshTypecastVoices = onCall(
  {secrets: [typecastApiKey]},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    if (!(await isCallerAuthorOrAdmin(uid))) {
      throw new HttpsError("permission-denied", "작가 또는 관리자만 사용할 수 있어요.");
    }

    try {
      await refreshTypecastVoiceCache(typecastApiKey.value());
    } catch (error) {
      console.error("Typecast 보이스 목록 새로고침 실패:", error);
      throw new HttpsError("aborted", "보이스 목록을 불러오지 못했어요.");
    }
    return {success: true};
  }
);

/**
 * 계정의 Firebase Auth 로그인 자체를 막거나(disabled: true) 다시
 * 허용한다(disabled: false) — "계정 정지"는 완전한 계정 삭제 대신
 * 이 되돌릴 수 있는 조치를 쓴다(요청 사양: 지갑/거래/팩 등 데이터는 전혀
 * 안 건드리고, 로그인만 막는다). 클라이언트 SDK는 다른 유저의 Auth 계정을
 * 건드릴 수 없어서(Admin SDK 전용 API) 반드시 이 Cloud Function을 거쳐야
 * 한다 — refundCoinCharge와 같은 이유로 admin 여부도 클라이언트 주장을
 * 믿지 않고 서버가 users/{uid}.role을 직접 다시 읽어 확인한다.
 *
 * 함수 이름/`ActivityKind`("authorAccountDisabled" 등)는 작가 계정 정지
 * 기능으로 처음 만들어진 이름 그대로다 — role과 무관하게 어떤 계정에도
 * 그대로 쓴다(회원 관리 화면의 "회원" 탭이 독자/관리자 계정에도 이 함수를
 * 부른다). 이름을 바꾸면 배포된 함수 이름이 바뀌어 재배포가 필요하고,
 * `ActivityKind`의 wire value는 이미 실제 activityLog 문서에 그 문자열
 * 그대로 저장돼 있어서(과거 기록을 깨뜨리지 않으려면 마이그레이션이
 * 필요하다) — 바꿀 실익보다 손이 더 들어서 이름은 그대로 두고 동작만
 * 일반화했다. `suspendPacks`는 role과 무관하게 그 uid가 authorId인
 * storyPacks가 있으면 내리고 없으면 그냥 아무 일도 안 한다 — 독자
 * 계정은 애초에 팩이 없으니 자연히 no-op이다.
 *
 * users/{uid}.accountDisabled에 같은 값을 거울로 남긴다 — Flutter 클라이언트는
 * Auth Admin API를 직접 조회할 수 없어서, 화면에 "정지됨" 배지를 보여주려면
 * 이 거울 필드를 읽는 수밖에 없다(lib/core/user/user_profile.dart의
 * UserProfile.accountDisabled 문서 참고).
 *
 * disabled == true && suspendPacks == true일 때만 그 작가의 storyPacks를
 * 전부 suspended: true로 일괄 내린다(스토리팩 승인 화면의 강제 내리기와
 * 완전히 같은 필드를 쓴다). 반대로 재활성화(disabled: false)할 때는 절대
 * 자동으로 팩을 복원하지 않는다 — admin이 계정은 다시 열어주면서도 특정
 * 팩은 계속 내려 두고 싶을 수 있어서, 팩 복원은 항상 스토리팩 승인
 * 화면에서 admin이 직접 누르는 별도의 명시적 조치로만 이뤄진다.
 */
export const setAuthorAccountDisabled = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }
  if (!(await isCallerAdmin(callerUid))) {
    throw new HttpsError("permission-denied", "관리자만 사용할 수 있어요.");
  }

  const data = request.data as {
    uid?: unknown;
    disabled?: unknown;
    suspendPacks?: unknown;
    reason?: unknown;
  };
  const {uid, disabled, suspendPacks, reason} = data;
  if (typeof uid !== "string" || uid.length === 0 || typeof disabled !== "boolean") {
    throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "존재하지 않는 계정이에요.");
  }
  const displayName = (userSnap.data()?.displayName as string | undefined) || "(이름 없음)";

  // Auth 쪽 로그인 차단이 먼저, 그다음 Firestore 거울 필드 — 순서가
  // 바뀌어 Auth 호출이 실패하면 거울 필드만 갱신된 채 실제로는 로그인이
  // 막히지 않은 상태로 남는 게 더 나쁘다(화면은 "정지됨"이라고 보여주는데
  // 실제로는 로그인이 된다).
  await getAuth().updateUser(uid, {disabled});
  await userRef.set({accountDisabled: disabled}, {merge: true});

  let suspendedPackCount = 0;
  if (disabled && suspendPacks === true) {
    const suspendReason = typeof reason === "string" && reason.trim().length > 0
      ? reason.trim()
      : "계정 정지로 인한 일괄 비공개";
    const packsSnap = await db.collection("storyPacks")
      .where("authorId", "==", uid)
      .get();
    if (!packsSnap.empty) {
      const batch = db.batch();
      for (const doc of packsSnap.docs) {
        batch.update(doc.ref, {
          suspended: true,
          suspendedReason: suspendReason,
          suspendedAt: FieldValue.serverTimestamp(),
          suspendedBy: callerUid,
        });
      }
      await batch.commit();
      suspendedPackCount = packsSnap.size;
    }
  }

  await db.collection("activityLog").add({
    kind: disabled ? "authorAccountDisabled" : "authorAccountReenabled",
    message: disabled
      ? `${displayName} 계정 정지${suspendedPackCount > 0 ? ` (작품 ${suspendedPackCount}개 비공개)` : ""}`
      : `${displayName} 계정 정지 해제`,
    actorUid: callerUid,
    createdAt: FieldValue.serverTimestamp(),
    authorName: displayName,
  });

  return {success: true, suspendedPackCount};
});

/** 카카오 개발자 콘솔 > 앱 > 카카오 로그인 > 보안 탭의 REST API 키/클라이언트
 * 시크릿 — `firebase functions:secrets:set KAKAO_REST_API_KEY`/
 * `KAKAO_CLIENT_SECRET`으로 값을 채워야 kakaoSignIn이 동작한다(값을 안
 * 채우면 함수가 배포는 되지만 호출 시점에 .value()가 빈 문자열/에러를 내며
 * 실패한다 — tossSecretKey와 같은 패턴). 카카오 JavaScript 키(공개 키, 클라
 * 이언트에 그대로 박아 둬도 되는 값)와는 완전히 다른 키다 — 이 둘은 절대
 * 클라이언트 코드에 두면 안 된다.
 */
const kakaoRestApiKey = defineSecret("KAKAO_REST_API_KEY");
const kakaoClientSecret = defineSecret("KAKAO_CLIENT_SECRET");

/**
 * 카카오 로그인 — Firebase Authentication에는 카카오 공급자가 없어서, 카카오
 * 자체 OAuth 인가 코드 흐름 + 이 Cloud Function으로 대신한다
 * (lib/core/auth/kakao_auth_service.dart 문서 참고):
 *
 * 1. 클라이언트가 카카오 OAuth 팝업에서 받은 인가 코드(`code`)를 넘긴다 —
 *    이 코드 자체는 아직 아무것도 증명하지 않는다.
 * 2. 이 함수가 카카오 토큰 엔드포인트(`kauth.kakao.com/oauth/token`)에
 *    REST API 키 + 클라이언트 시크릿으로 그 코드를 액세스 토큰과 교환한다
 *    — 이 교환이 성공한다는 것 자체가 "이 요청이 진짜 우리 앱을 거쳐 카카오
 *    로그인 팝업에서 나왔다"는 증거다(코드는 발급 시점의 redirect_uri와
 *    묶여 있고, 시크릿 없이는 아무나 교환할 수 없다).
 * 3. 그 액세스 토큰으로 카카오 사용자 API(`kapi.kakao.com/v2/user/me`)를
 *    직접 불러 카카오 유저 id/프로필을 확인한다 — 클라이언트가 유저 id를
 *    직접 보냈다면 그건 절대 못 믿는다(누구나 임의의 id를 보낼 수 있다),
 *    하지만 이렇게 액세스 토큰으로 카카오에 직접 물어본 응답은 믿을 수
 *    있다.
 * 4. `uid = 'kakao_' + 카카오유저id`로 고정한다 — 접두어를 붙여서 Google
 *    로그인이 발급하는 Firebase uid(Firebase Auth가 자동 생성하는 임의
 *    문자열)와 절대 겹치지 않게 한다.
 * 5. 그 uid로 Firebase Auth 유저가 없으면 새로 만들고(있으면 그대로 두고
 *    — 재로그인마다 닉네임/프로필사진을 다시 덮어쓰지 않는다), Firebase
 *    커스텀 토큰을 발급해 돌려준다. 클라이언트는 그 토큰으로
 *    `signInWithCustomToken`을 불러 로그인을 마친다.
 *
 * 공개 로그인 엔드포인트라 admin 권한 확인이 없다 — Firebase 자체의 Google
 * 로그인과 같은 신뢰 수준이다(요청 사양).
 */
export const kakaoSignIn = onCall(
  {secrets: [kakaoRestApiKey, kakaoClientSecret]},
  async (request) => {
    const data = request.data as {code?: unknown; redirectUri?: unknown};
    const {code, redirectUri} = data;
    if (
      typeof code !== "string" || code.length === 0 ||
      typeof redirectUri !== "string" || redirectUri.length === 0
    ) {
      throw new HttpsError("invalid-argument", "요청 값이 올바르지 않습니다.");
    }

    // 1) 인가 코드 -> 액세스 토큰. client_secret이 앱 설정에서 꺼져 있으면
    // 카카오가 그냥 이 값을 무시하므로, 켜져 있든 꺼져 있든 항상 보내도
    // 안전하다(카카오 문서: 시크릿이 꺼져 있으면 파라미터 자체가 무시됨).
    const tokenResponse = await fetch("https://kauth.kakao.com/oauth/token", {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: new URLSearchParams({
        grant_type: "authorization_code",
        client_id: kakaoRestApiKey.value(),
        client_secret: kakaoClientSecret.value(),
        redirect_uri: redirectUri,
        code,
      }).toString(),
    });
    const tokenBody = await tokenResponse.json() as Record<string, unknown>;
    if (!tokenResponse.ok || typeof tokenBody.access_token !== "string") {
      console.error("카카오 토큰 교환 실패:", tokenBody);
      throw new HttpsError("aborted", "카카오 로그인에 실패했어요.");
    }
    const kakaoAccessToken = tokenBody.access_token;

    // 2) 액세스 토큰 -> 카카오 사용자 정보(검증 겸 프로필 조회).
    const meResponse = await fetch("https://kapi.kakao.com/v2/user/me", {
      headers: {Authorization: `Bearer ${kakaoAccessToken}`},
    });
    const meBody = await meResponse.json() as Record<string, unknown>;
    if (!meResponse.ok || typeof meBody.id !== "number") {
      console.error("카카오 사용자 조회 실패:", meBody);
      throw new HttpsError("aborted", "카카오 사용자 정보를 가져오지 못했어요.");
    }

    const kakaoAccount = meBody.kakao_account as Record<string, unknown> | undefined;
    const kakaoProfile = kakaoAccount?.profile as Record<string, unknown> | undefined;
    const nickname = typeof kakaoProfile?.nickname === "string" ? kakaoProfile.nickname : undefined;
    const profileImageUrl = typeof kakaoProfile?.profile_image_url === "string" ?
      kakaoProfile.profile_image_url :
      undefined;
    // 이메일 동의 항목은 기본으로 요청하지 않는다(요청 사양) — 있으면
    // 쓰고, 없으면 undefined로 둔다(users/{uid}.email이 ''로 읽히는 다른
    // 경로들과 같은 nullable-safe 취급).
    const email = typeof kakaoAccount?.email === "string" ? kakaoAccount.email : undefined;

    const uid = `kakao_${meBody.id}`;

    let userExists = true;
    try {
      await getAuth().getUser(uid);
    } catch (error) {
      if ((error as {code?: string}).code === "auth/user-not-found") {
        userExists = false;
      } else {
        throw error;
      }
    }

    if (!userExists) {
      const createPayload: {
        uid: string;
        displayName?: string;
        photoURL?: string;
        email?: string;
      } = {uid};
      if (nickname) createPayload.displayName = nickname;
      if (profileImageUrl) createPayload.photoURL = profileImageUrl;
      if (email) createPayload.email = email;
      await getAuth().createUser(createPayload);
    }

    const customToken = await getAuth().createCustomToken(uid);
    return {customToken};
  }
);
