import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../data/story_pack_review_repository.dart';
import '../models/story_pack.dart';
import '../models/story_pack_review.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// StoryPackDetailPage의 "리뷰" 섹션 — 최신순 페이지네이션 목록("더 보기"
/// 버튼 방식, 무한 스크롤 아님) + [eligible]일 때만 보이는 "리뷰 작성"
/// 진입점. 평균 평점/개수 자체는 이 위젯이 아니라 상위 stat row가 이미
/// StoryPack.avgRating/reviewCount(서버에서 집계된 값)로 보여준다 — 여기
/// 목록은 개별 리뷰 본문만 다룬다.
class PackReviewsSection extends StatefulWidget {
  final StoryPack pack;

  /// 로그인 + (무료 팩이거나 소유) — 리뷰/댓글 작성 자격. 보안 규칙이 실제
  /// 쓰기를 다시 한번 검증하므로, 이 플래그는 어디까지나 UI 진입점을
  /// 보여줄지 결정하는 용도다.
  final bool eligible;

  const PackReviewsSection({
    super.key,
    required this.pack,
    required this.eligible,
  });

  @override
  State<PackReviewsSection> createState() => _PackReviewsSectionState();
}

class _PackReviewsSectionState extends State<PackReviewsSection> {
  final StoryPackReviewRepository _repository = StoryPackReviewRepository();

  final List<StoryPackReview> _reviews = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMore();
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
      );
      if (!mounted) return;
      setState(() {
        _reviews.addAll(page.reviews);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      // pack_comments_section.dart의 같은 수정과 이유가 같다 — 조용히
      // 삼키고 "리뷰 없음"과 구분 안 되게 두면, 규칙/색인 미배포 같은 실제
      // 오류가 화면에서도 콘솔에서도 안 보이게 된다.
      debugPrint('리뷰 목록 불러오기 실패: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _hasMore = false;
        _errorMessage = '리뷰를 불러오지 못했어요.';
      });
    }
  }

  void _retry() {
    setState(() => _hasMore = true);
    _loadMore();
  }

  Future<void> _openReviewForm() async {
    final authService = AuthScope.of(context);
    final uid = authService.userId;
    if (uid == null) return;

    final existing = await _repository.fetchMyReview(widget.pack.id, uid);
    if (!mounted) return;

    final result = await showDialog<_ReviewFormResult>(
      context: context,
      builder: (_) => _ReviewFormDialog(
        initialRating: existing?.rating ?? 5,
        initialText: existing?.text ?? '',
      ),
    );
    if (result == null || !mounted) return;

    await _repository.submitReview(
      packId: widget.pack.id,
      uid: uid,
      rating: result.rating,
      text: result.text,
      authorDisplayName: authService.displayName ?? '익명',
      authorPhotoUrl: authService.photoUrl,
    );
    if (!mounted) return;

    // 새로 쓴/고친 리뷰가 최신순 맨 위로 오도록 목록을 처음부터 다시 받는다 —
    // 페이지 몇 장을 이미 불러온 상태에서 그 안 어딘가를 부분 갱신하는 것보다
    // 훨씬 간단하고, 리뷰 작성은 자주 있는 일이 아니라 다시 불러오는 비용도
    // 크지 않다.
    setState(() {
      _reviews.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Text + Spacer는 TextButton의 최소 탭 타깃 폭(Material 기본
            // 최소 크기)까지 감안하면 좁은 화면에서 오버플로가 났다(실제로
            // "RenderFlex overflowed by 5.0 pixels" 버그) — Text 쪽을
            // Expanded로 감싸 남는 공간을 정확히 흡수하게 하면 어떤 폭에서도
            // 넘치지 않는다. Spacer는 더 필요 없다(Expanded가 이미 그 역할).
            const Expanded(
              child: Text(
                '리뷰',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                ),
              ),
            ),
            if (widget.eligible)
              TextButton(
                onPressed: _openReviewForm,
                child: const Text(
                  '리뷰 작성',
                  style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
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
        else if (_reviews.isEmpty && _loadedOnce)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '아직 리뷰가 없어요.',
              style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.6)),
            ),
          )
        else
          for (final review in _reviews) _ReviewTile(review: review),
        if (_loading)
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
                onPressed: _loadMore,
                child: Text(
                  '리뷰 더 보기',
                  style: TextStyle(color: _ivory.withOpacity(0.7)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final StoryPackReview review;

  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                url: review.authorPhotoUrl,
                name: review.authorDisplayName,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.authorDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ivory,
                  ),
                ),
              ),
              _StarRow(rating: review.rating, size: 14),
            ],
          ),
          if (review.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.white.withOpacity(0.85),
              ),
            ),
          ],
        ],
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

class _StarRow extends StatelessWidget {
  final int rating;
  final double size;

  const _StarRow({required this.rating, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_border_rounded,
            size: size,
            color: _gold,
          ),
      ],
    );
  }
}

class _ReviewFormResult {
  final int rating;
  final String text;

  const _ReviewFormResult({required this.rating, required this.text});
}

class _ReviewFormDialog extends StatefulWidget {
  final int initialRating;
  final String initialText;

  const _ReviewFormDialog({
    required this.initialRating,
    required this.initialText,
  });

  @override
  State<_ReviewFormDialog> createState() => _ReviewFormDialogState();
}

class _ReviewFormDialogState extends State<_ReviewFormDialog> {
  late int _rating = widget.initialRating;
  late final TextEditingController _textController = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF151515),
      title: const Text('리뷰 작성', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: _gold,
                    size: 28,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '이 이야기는 어땠나요? (선택)',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _ReviewFormResult(
              rating: _rating,
              text: _textController.text.trim(),
            ),
          ),
          child: const Text(
            '등록',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
