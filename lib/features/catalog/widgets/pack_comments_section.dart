import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../data/story_pack_comment_repository.dart';
import '../models/story_pack.dart';
import '../models/story_pack_comment.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// StoryPackDetailPage의 "댓글" 섹션 — 리뷰 섹션 바로 아래. 최상위 댓글은
/// 페이지네이션("더 보기") 목록이고, 각 최상위 댓글 아래 답글(parentCommentId로
/// 한 단계만 중첩, 답글의 답글은 없음)이 들여쓰기로 바로 딸려 나온다 — 답글은
/// 별도 "더 보기" 없이 [StoryPackCommentRepository.fetchReplies]로 한 번에
/// 가져온다(스레드가 보통 짧아서). [eligible]은 댓글/답글 "작성" 자격
/// (canReviewPack)만 가린다 — 좋아요는 로그인만 돼 있으면 누구나 누를 수
/// 있다(firestore.rules의 likes 규칙이 그렇게 더 느슨하다).
class PackCommentsSection extends StatefulWidget {
  final StoryPack pack;
  final bool eligible;

  const PackCommentsSection({
    super.key,
    required this.pack,
    required this.eligible,
  });

  @override
  State<PackCommentsSection> createState() => _PackCommentsSectionState();
}

class _PackCommentsSectionState extends State<PackCommentsSection> {
  final StoryPackCommentRepository _repository = StoryPackCommentRepository();
  final TextEditingController _inputController = TextEditingController();

  final List<StoryPackComment> _comments = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _posting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final page = await _repository.fetchPage(
        widget.pack.id,
        startAfter: _lastDoc,
        pageSize: 5,
      );
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.comments);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      // 여기서 삼키고 조용히 "댓글 없음"처럼 보이게 두면 안 된다 — 실제로
      // 복합 색인 미배포(FAILED_PRECONDITION)나 규칙 미배포(permission-denied)
      // 때문에 쿼리 자체가 실패해도 화면은 빈 목록과 구분이 안 갔던 버그가
      // 있었다. 콘솔에도 원본 예외를 남기고, 화면에도 "빈 목록"과 다른
      // 에러 문구를 명시적으로 보여준다.
      debugPrint('댓글 목록 불러오기 실패: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        // "더 보기"를 같이 보여주면 방금 실패한 요청과 헷갈린다 — 아래
        // "다시 시도" 버튼 하나로만 재시도하게 한다.
        _hasMore = false;
        _errorMessage = '댓글을 불러오지 못했어요.';
      });
    }
  }

  Future<void> _postComment() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _posting) return;

    final authService = AuthScope.of(context);
    final uid = authService.userId;
    if (uid == null) return;

    setState(() => _posting = true);
    try {
      final comment = await _repository.postComment(
        packId: widget.pack.id,
        uid: uid,
        text: text,
        authorDisplayName: authService.displayName ?? '익명',
        authorPhotoUrl: authService.photoUrl,
      );
      if (!mounted) return;
      _inputController.clear();
      // 이미 불러온 페이지 위에 바로 꽂는다 — 처음부터 다시 불러오지 않는다.
      setState(() => _comments.insert(0, comment));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _removeComment(String commentId) {
    setState(() => _comments.removeWhere((c) => c.id == commentId));
  }

  /// _loadMore()는 실패 시 _hasMore를 false로 내려서 "더 보기"와 에러 상태가
  /// 동시에 보이지 않게 하는데, 그러면 "다시 시도"가 다시 _loadMore()를
  /// 불러도 !_hasMore 가드에 걸려 아무 일도 안 일어난다 — 재시도 직전에
  /// 다시 true로 올려 둔다.
  void _retry() {
    setState(() => _hasMore = true);
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = AuthScope.of(context).userId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '댓글',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ivory,
          ),
        ),
        const SizedBox(height: 10),
        if (widget.eligible)
          _CommentInput(
            controller: _inputController,
            posting: _posting,
            onSubmit: _postComment,
          ),
        const SizedBox(height: 10),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: Colors.redAccent.withOpacity(0.85),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.redAccent.withOpacity(0.85),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _retry,
                  child: Text(
                    '다시 시도',
                    style: TextStyle(color: _ivory.withOpacity(0.8)),
                  ),
                ),
              ],
            ),
          )
        else if (_comments.isEmpty && _loadedOnce)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '아직 댓글이 없어요.',
              style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.6)),
            ),
          )
        else
          for (final comment in _comments)
            _TopLevelCommentTile(
              key: ValueKey(comment.id),
              comment: comment,
              packId: widget.pack.id,
              eligible: widget.eligible,
              myUid: myUid,
              repository: _repository,
              onDeleted: () => _removeComment(comment.id),
            ),
        if (_loading && _comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(color: _ivory, strokeWidth: 2),
            ),
          )
        else if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: TextButton(
                onPressed: _loading ? null : _loadMore,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _ivory,
                        ),
                      )
                    : Text(
                        '댓글 더 보기',
                        style: TextStyle(color: _ivory.withOpacity(0.7)),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final bool posting;
  final VoidCallback onSubmit;
  final String hintText;

  const _CommentInput({
    required this.controller,
    required this.posting,
    required this.onSubmit,
    this.hintText = '댓글을 남겨보세요',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: 3,
            minLines: 1,
            maxLength: 300,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: posting ? null : onSubmit,
          icon: posting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _gold,
                  ),
                )
              : const Icon(Icons.send_rounded, color: _gold),
        ),
      ],
    );
  }
}

/// 최상위 댓글 한 편 — 자기 본문/좋아요/삭제(본인만) + "답글" 액션(눌리면
/// 인라인 입력창이 펼쳐진다) + 그 아래 들여쓴 답글 목록. 답글도 같은
/// [_CommentBody]로 그리는데, trailingAction을 null로 줘서 "답글" 액션이
/// 없다는 점만 다르다(중첩 1단계 제한 — UI에서부터 답글에는 답글 버튼을
/// 아예 안 준다).
class _TopLevelCommentTile extends StatefulWidget {
  final StoryPackComment comment;
  final String packId;
  final bool eligible;
  final String? myUid;
  final StoryPackCommentRepository repository;
  final VoidCallback onDeleted;

  const _TopLevelCommentTile({
    super.key,
    required this.comment,
    required this.packId,
    required this.eligible,
    required this.myUid,
    required this.repository,
    required this.onDeleted,
  });

  @override
  State<_TopLevelCommentTile> createState() => _TopLevelCommentTileState();
}

class _TopLevelCommentTileState extends State<_TopLevelCommentTile> {
  final TextEditingController _replyController = TextEditingController();

  List<StoryPackComment> _replies = [];
  bool _loadingReplies = true;
  bool _replyInputVisible = false;
  bool _postingReply = false;
  String? _repliesError;

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadReplies() async {
    setState(() => _repliesError = null);
    try {
      final replies = await widget.repository.fetchReplies(
        widget.packId,
        widget.comment.id,
      );
      if (!mounted) return;
      setState(() {
        _replies = replies;
        _loadingReplies = false;
      });
    } catch (e) {
      // pack_comments_section의 최상위 댓글 로딩과 같은 이유 — 조용히
      // 삼키고 빈 답글 목록처럼 보이게 두지 않는다.
      debugPrint('답글 목록 불러오기 실패(${widget.comment.id}): $e');
      if (!mounted) return;
      setState(() {
        _loadingReplies = false;
        _repliesError = '답글을 불러오지 못했어요.';
      });
    }
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    final uid = widget.myUid;
    if (text.isEmpty || _postingReply || uid == null) return;

    final authService = AuthScope.of(context);
    setState(() => _postingReply = true);
    try {
      final reply = await widget.repository.postComment(
        packId: widget.packId,
        uid: uid,
        text: text,
        authorDisplayName: authService.displayName ?? '익명',
        authorPhotoUrl: authService.photoUrl,
        parentCommentId: widget.comment.id,
      );
      if (!mounted) return;
      _replyController.clear();
      // 답글은 페이지네이션이 없으니 전체를 다시 불러오지 않고 오래된 순
      // 목록 맨 뒤에 바로 이어 붙인다.
      setState(() {
        _replyInputVisible = false;
        _replies = [..._replies, reply];
      });
    } finally {
      if (mounted) setState(() => _postingReply = false);
    }
  }

  Future<void> _deleteReply(StoryPackComment reply) async {
    await widget.repository.deleteComment(widget.packId, reply.id);
    if (!mounted) return;
    setState(() => _replies.removeWhere((r) => r.id == reply.id));
  }

  Future<void> _deleteSelf() async {
    await widget.repository.deleteComment(widget.packId, widget.comment.id);
    widget.onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentBody(
            comment: comment,
            packId: widget.packId,
            myUid: widget.myUid,
            repository: widget.repository,
            canDelete: comment.uid == widget.myUid,
            onDelete: _deleteSelf,
            trailingAction: widget.eligible
                ? _TextAction(
                    label: '답글',
                    onTap: () => setState(
                      () => _replyInputVisible = !_replyInputVisible,
                    ),
                  )
                : null,
          ),
          if (_replyInputVisible)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 8),
              child: _CommentInput(
                controller: _replyController,
                posting: _postingReply,
                onSubmit: _submitReply,
                hintText: '${comment.authorDisplayName}님에게 답글 남기기',
              ),
            ),
          if (_loadingReplies)
            const Padding(
              padding: EdgeInsets.only(left: 34, top: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _ivory),
              ),
            )
          else if (_repliesError != null)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: Colors.redAccent.withOpacity(0.85),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _repliesError!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.redAccent.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _loadReplies,
                    child: Text(
                      '다시 시도',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _ivory.withOpacity(0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final reply in _replies)
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 10),
                child: _CommentBody(
                  comment: reply,
                  packId: widget.packId,
                  myUid: widget.myUid,
                  repository: widget.repository,
                  canDelete: reply.uid == widget.myUid,
                  onDelete: () => _deleteReply(reply),
                  // 답글에는 "답글" 액션이 없다 — 중첩은 딱 한 단계만.
                  trailingAction: null,
                ),
              ),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: _ivory.withOpacity(0.6),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 댓글 한 줄(최상위/답글 공통) — 아바타 + 이름 + 본문 + [likeButton] +
/// 본인이면 삭제 버튼, 그 아래 줄에 [trailingAction](답글 버튼, 답글 자신은
/// null)까지. 들여쓰기는 이 위젯이 아니라 호출부(Padding)가 맡는다.
class _CommentBody extends StatelessWidget {
  final StoryPackComment comment;
  final String packId;
  final String? myUid;
  final StoryPackCommentRepository repository;
  final bool canDelete;
  final VoidCallback onDelete;
  final Widget? trailingAction;

  const _CommentBody({
    required this.comment,
    required this.packId,
    required this.myUid,
    required this.repository,
    required this.canDelete,
    required this.onDelete,
    required this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(url: comment.authorPhotoUrl, name: comment.authorDisplayName),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comment.authorDisplayName,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _ivory,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                comment.text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _LikeButton(
                    packId: packId,
                    commentId: comment.id,
                    myUid: myUid,
                    initialLikeCount: comment.likeCount,
                    repository: repository,
                  ),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 14),
                    trailingAction!,
                  ],
                ],
              ),
            ],
          ),
        ),
        if (canDelete)
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: _ivory.withOpacity(0.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// 하트 아이콘 + likeCount. [StoryPackCommentRepository.watchLikeCount]로
/// 댓글 문서의 likeCount(Cloud Function이 갱신)를 실시간으로 보여주고,
/// [StoryPackCommentRepository.watchMyLike]로 내 좋아요 여부(내 uid 문서
/// 하나만 구독 — likes 서브컬렉션 전체를 훑지 않는다)를 반영해 채워진/빈
/// 하트를 고른다. 로그인 안 했으면(myUid == null) 눌러도 아무 일도 안
/// 일어난다 — canReviewPack과 무관하게 로그인만 하면 되는, 댓글 작성보다
/// 낮은 문턱이라 여기서는 eligible을 아예 안 본다.
class _LikeButton extends StatelessWidget {
  final String packId;
  final String commentId;
  final String? myUid;
  final int initialLikeCount;
  final StoryPackCommentRepository repository;

  const _LikeButton({
    required this.packId,
    required this.commentId,
    required this.myUid,
    required this.initialLikeCount,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final myUid = this.myUid;

    return StreamBuilder<int>(
      stream: repository.watchLikeCount(packId, commentId),
      initialData: initialLikeCount,
      builder: (context, countSnapshot) {
        final count = countSnapshot.data ?? initialLikeCount;

        if (myUid == null) {
          return _LikeDisplay(liked: false, count: count, onTap: null);
        }

        return StreamBuilder<bool>(
          stream: repository.watchMyLike(packId, commentId, myUid),
          initialData: false,
          builder: (context, likedSnapshot) {
            final liked = likedSnapshot.data ?? false;
            return _LikeDisplay(
              liked: liked,
              count: count,
              onTap: () => repository.toggleLike(packId, commentId, myUid),
            );
          },
        );
      },
    );
  }
}

class _LikeDisplay extends StatelessWidget {
  final bool liked;
  final int count;
  final VoidCallback? onTap;

  const _LikeDisplay({
    required this.liked,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 14,
              color: liked ? const Color(0xFFFF6B4A) : _ivory.withOpacity(0.5),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                color: _ivory.withOpacity(0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;

  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return CircleAvatar(
      radius: 13,
      backgroundColor: Colors.white.withOpacity(0.12),
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? Text(
              name.isEmpty ? '?' : name.substring(0, 1),
              style: const TextStyle(
                fontSize: 11,
                color: _ivory,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
