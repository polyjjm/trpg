import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

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
