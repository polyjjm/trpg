import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/story_pack_review.dart';

/// 페이지 하나 분량의 리뷰 + "다음 페이지가 더 있는지" + 다음 페이지를 이어
/// 부르기 위한 커서(마지막 문서 스냅샷). [ReviewsSection] 위젯이 "더 보기"를
/// 누를 때마다 이 [lastDoc]를 그대로 [StoryPackReviewRepository.fetchPage]에
/// 되돌려준다.
class ReviewPage {
  final List<StoryPackReview> reviews;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const ReviewPage({
    required this.reviews,
    required this.lastDoc,
    required this.hasMore,
  });
}

/// storyPacks/{packId}/reviews 컬렉션 — 문서 id가 작성자 uid라서 "재작성"이
/// 곧 같은 문서 업데이트다. 평점 집계(avgRating/reviewCount, storyPacks 문서에
/// 비정규화)는 클라이언트가 계산하지 않는다 — 리뷰 쓰기를 트리거로 하는
/// Cloud Function(functions/src/index.ts의 onReviewWritten)이 서버에서
/// 담당한다. 이 저장소는 순수하게 리뷰 문서 자체의 읽기/쓰기만 한다.
class StoryPackReviewRepository {
  StoryPackReviewRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _reviews(String packId) =>
      _firestore.collection('storyPacks').doc(packId).collection('reviews');

  /// 최신순 한 페이지. [startAfter]를 이전 페이지의 [ReviewPage.lastDoc]로
  /// 넘기면 이어서 다음 페이지를 가져온다 — 첫 페이지는 null.
  Future<ReviewPage> fetchPage(
    String packId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 10,
  }) async {
    var query = _reviews(
      packId,
    ).orderBy('createdAt', descending: true).limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();

    return ReviewPage(
      reviews: snapshot.docs
          .map((doc) => StoryPackReview.fromFirestore(doc.id, doc.data()))
          .toList(),
      lastDoc: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      // 정확히 pageSize개를 받았다면 다음 페이지가 있을 가능성이 있다고 본다 —
      // 흔한 "한 개 더 얹어서 물어보기"까지는 안 하는 근사치라, 마지막
      // 페이지에서 "더 보기"를 한 번 더 눌러 빈 결과를 받을 수는 있다(그때
      // hasMore를 false로 내린다).
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  /// 리뷰 작성 폼을 열 때 미리 채워 줄 기존 리뷰(있으면). 문서 id가 uid라
  /// 단건 조회로 바로 찾는다 — fetchPage로 여러 페이지를 훑을 필요가 없다.
  Future<StoryPackReview?> fetchMyReview(String packId, String uid) async {
    final snapshot = await _reviews(packId).doc(uid).get();
    final data = snapshot.data();
    if (data == null) return null;
    return StoryPackReview.fromFirestore(uid, data);
  }

  /// 이 유저의 기존 리뷰가 있으면 rating/text/작성자 정보만 갱신하고
  /// createdAt은 그대로 둔다(최초 작성 시각 보존) — 없으면 새로 만든다.
  /// 두 번 왕복(조회 후 분기)하는 이유는 createdAt을 "최초 생성 시에만"
  /// 서버 타임스탬프로 찍기 위해서다 — set()으로 통째로 덮어쓰면 수정할
  /// 때마다 createdAt이 밀린다.
  Future<void> submitReview({
    required String packId,
    required String uid,
    required int rating,
    required String text,
    required String authorDisplayName,
    required String? authorPhotoUrl,
  }) async {
    final doc = _reviews(packId).doc(uid);
    final existing = await doc.get();

    final fields = {
      'rating': rating,
      'text': text,
      'authorDisplayName': authorDisplayName,
      'authorPhotoUrl': authorPhotoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (existing.exists) {
      await doc.update(fields);
    } else {
      await doc.set({...fields, 'createdAt': FieldValue.serverTimestamp()});
    }
  }
}
