import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/story_pack_comment.dart';

/// [StoryPackReviewRepository.fetchPage]의 ReviewPage와 같은 모양 —
/// CommentsSection 위젯의 "더 보기" 커서 페이지네이션에 쓴다. 답글
/// ([StoryPackCommentRepository.fetchReplies])은 페이지네이션이 없어서 이
/// 타입을 쓰지 않는다.
class CommentPage {
  final List<StoryPackComment> comments;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const CommentPage({
    required this.comments,
    required this.lastDoc,
    required this.hasMore,
  });
}

/// storyPacks/{packId}/comments 컬렉션 — 삭제는 소프트 삭제(isDeleted)뿐이고,
/// 답글은 parentCommentId로 한 단계만 중첩된다(답글의 답글은 없음 —
/// firestore.rules가 서버에서도 강제한다). 좋아요(likes 서브컬렉션)는 이
/// 저장소가 문서 자체는 안 다루고, likeCount 집계 읽기/토글만 다룬다 —
/// 실제 집계는 Cloud Function(onCommentLikeWritten)의 몫이다.
class StoryPackCommentRepository {
  StoryPackCommentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _comments(String packId) =>
      _firestore.collection('storyPacks').doc(packId).collection('comments');

  DocumentReference<Map<String, dynamic>> _comment(
    String packId,
    String commentId,
  ) => _comments(packId).doc(commentId);

  DocumentReference<Map<String, dynamic>> _likeDoc(
    String packId,
    String commentId,
    String uid,
  ) => _comment(packId, commentId).collection('likes').doc(uid);

  /// 최상위 댓글만(parentCommentId == null) — isDeleted 필터와 함께라 복합
  /// 색인이 필요하다(firestore.indexes.json).
  Future<CommentPage> fetchPage(
    String packId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 20,
  }) async {
    var query = _comments(packId)
        .where('isDeleted', isEqualTo: false)
        .where('parentCommentId', isEqualTo: null)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();

    return CommentPage(
      comments: snapshot.docs
          .map((doc) => StoryPackComment.fromFirestore(doc.id, doc.data()))
          .toList(),
      lastDoc: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  /// 특정 최상위 댓글의 답글 전체 — 오래된 순(등록 순서대로 읽히도록).
  /// 답글 스레드는 보통 짧아서 페이지네이션 없이 한 번에 가져온다(200개
  /// 상한은 병적으로 답글이 몰리는 경우를 막는 방어선일 뿐, UI에 "더 보기"는
  /// 없다).
  Future<List<StoryPackComment>> fetchReplies(
    String packId,
    String parentCommentId,
  ) async {
    final snapshot = await _comments(packId)
        .where('parentCommentId', isEqualTo: parentCommentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt')
        .limit(200)
        .get();
    return snapshot.docs
        .map((doc) => StoryPackComment.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  /// [parentCommentId]를 주면 답글로, 안 주면(기본 null) 최상위 댓글로 쓴다 —
  /// 문서 모양은 완전히 같고 이 필드 하나로 갈릴 뿐이다.
  ///
  /// 방금 쓴 댓글/답글을 로컬에서 그대로 되돌려준다 — 호출부가 목록을 처음부터
  /// 다시 안 불러오고 이 값을 바로 목록에 꽂아 넣을 수 있게 하기 위해서다.
  /// createdAt은 FieldValue.serverTimestamp()가 아직 로컬에서 안 풀려서
  /// DateTime.now()로 근사한다 — 최상위 목록은 어차피 맨 위에 꽂으므로 실제
  /// 서버 값과 몇 초 어긋나도 정렬에 영향이 없다.
  Future<StoryPackComment> postComment({
    required String packId,
    required String uid,
    required String text,
    required String authorDisplayName,
    required String? authorPhotoUrl,
    String? parentCommentId,
  }) async {
    final doc = await _comments(packId).add({
      'uid': uid,
      'text': text,
      'authorDisplayName': authorDisplayName,
      'authorPhotoUrl': authorPhotoUrl,
      'isDeleted': false,
      'parentCommentId': parentCommentId,
      'likeCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return StoryPackComment(
      id: doc.id,
      uid: uid,
      text: text,
      createdAt: DateTime.now(),
      authorDisplayName: authorDisplayName,
      authorPhotoUrl: authorPhotoUrl,
      isDeleted: false,
      parentCommentId: parentCommentId,
      likeCount: 0,
    );
  }

  /// 본인 댓글만 지울 수 있다 — 보안 규칙이 isDeleted를 true로 바꾸는 것
  /// 외에는 아무 필드도 못 바꾸게 강제한다(update 자체는 허용, 다른 필드
  /// 변경은 거부). 최상위 댓글/답글 둘 다 같은 메서드로 지운다.
  Future<void> deleteComment(String packId, String commentId) async {
    await _comment(packId, commentId).update({'isDeleted': true});
  }

  /// 댓글 문서의 likeCount 필드를 실시간으로 본다 — Cloud Function이 좋아요
  /// 쓰기마다 갱신하는 값을 그대로 구독한다(클라이언트가 likes 서브컬렉션을
  /// 직접 세지 않는다).
  Stream<int> watchLikeCount(String packId, String commentId) {
    return _comment(packId, commentId).snapshots().map(
      (doc) => (doc.data()?['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// 내가 이 댓글에 좋아요를 눌렀는지 — likes/{내 uid} 문서 하나의 존재
  /// 여부만 본다(전체 likes 서브컬렉션을 훑지 않는다).
  Stream<bool> watchMyLike(String packId, String commentId, String uid) {
    return _likeDoc(
      packId,
      commentId,
      uid,
    ).snapshots().map((doc) => doc.exists);
  }

  /// 좋아요 문서가 있으면 지우고, 없으면 만든다 — 트랜잭션으로 감싸서
  /// 빠르게 두 번 탭했을 때 "있었는데 없다고 읽고 또 만드는" 경합을 막는다.
  Future<void> toggleLike(String packId, String commentId, String uid) async {
    final ref = _likeDoc(packId, commentId, uid);
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (snapshot.exists) {
        tx.delete(ref);
      } else {
        tx.set(ref, {'createdAt': FieldValue.serverTimestamp()});
      }
    });
  }
}
