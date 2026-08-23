import 'package:flutter/material.dart';

import '../../models/pending_action.dart';
import '../../models/pending_node_ref.dart';
import '../../widgets/admin_theme.dart';
import '../../widgets/status_tag.dart';

/// 개요의 "승인 대기함" 미리보기 — 승인/반려 버튼은 두지 않는다. 반려는 사유
/// 입력이 필수이고(ApprovalsTab), 승인은 diff를 본 뒤에 눌러야 하는 판단이라
/// 개요에서 처리하게 만들면 잘못 누르기 쉽다. 여기서는 **얼마나, 무엇이,
/// 얼마나 오래 밀려 있는지**만 보여주고 실제 처리는 탭으로 넘긴다.
///
/// 목업의 필터 칩은 전체/등록/수정/삭제 4개다 — "반려됨"은 pendingAction이
/// 비어 있어서 애초에 [PendingNodeRef] 목록에 들어오지 않는다(반려 노드는
/// 작가 쪽 화면의 관심사다).
class PendingQueuePreview extends StatefulWidget {
  final Stream<List<PendingNodeRef>> pendingNodesStream;

  /// packId → 작품 제목. 비어 있으면 packId를 그대로 보여준다.
  final Map<String, String> packTitles;

  /// packId → 작가 이름.
  final Map<String, String> packAuthors;

  /// "승인 대기함 전체 보기" — 대시보드가 사이드바 선택을 승인 대기함으로
  /// 옮긴다.
  final VoidCallback onSeeAll;

  /// 미리보기에 보여줄 최대 행 수.
  final int maxRows;

  const PendingQueuePreview({
    super.key,
    required this.pendingNodesStream,
    required this.packTitles,
    required this.packAuthors,
    required this.onSeeAll,
    this.maxRows = 6,
  });

  @override
  State<PendingQueuePreview> createState() => _PendingQueuePreviewState();
}

enum _QueueFilter { all, create, edit, delete }

class _PendingQueuePreviewState extends State<PendingQueuePreview> {
  _QueueFilter _filter = _QueueFilter.all;

  bool _matches(PendingNodeRef ref) {
    switch (_filter) {
      case _QueueFilter.all:
        return true;
      case _QueueFilter.create:
        return ref.node.pendingAction == PendingAction.create;
      case _QueueFilter.edit:
        return ref.node.pendingAction == PendingAction.edit;
      case _QueueFilter.delete:
        return ref.node.pendingAction == PendingAction.delete;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PendingNodeRef>>(
      stream: widget.pendingNodesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Shell(
            count: null,
            filter: _filter,
            onFilter: (f) => setState(() => _filter = f),
            onSeeAll: widget.onSeeAll,
            oldest: null,
            child: Padding(
              padding: const EdgeInsets.all(18), // 여기에 const
              child: SelectableText(
                '승인 대기 목록을 불러오지 못했어요: ${snapshot.error}',
                style: const TextStyle(fontSize: 12, color: AdminColors.danger),
              ),
            ),
          );
        }

        final all = snapshot.data;
        // 오래 기다린 것부터 — 요청 시각이 없는(필드 도입 전) 노드는 뒤로 보낸다.
        final sorted = all == null
            ? const <PendingNodeRef>[]
            : (List<PendingNodeRef>.from(all)..sort((a, b) {
                final x = a.requestedAt;
                final y = b.requestedAt;
                if (x == null && y == null) return 0;
                if (x == null) return 1;
                if (y == null) return -1;
                return x.compareTo(y);
              }));

        final filtered = sorted.where(_matches).toList();
        final rows = filtered.take(widget.maxRows).toList();

        return _Shell(
          count: all == null ? null : filtered.length,
          filter: _filter,
          onFilter: (f) => setState(() => _filter = f),
          onSeeAll: widget.onSeeAll,
          oldest: sorted.isEmpty ? null : sorted.first.requestedAt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderRow(),
              if (all == null)
                Padding(
                  // ← 여기 const 삭제
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    '불러오는 중…',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                )
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    _filter == _QueueFilter.all
                        ? '대기 중인 요청이 없어요.'
                        : '이 조건에 해당하는 요청이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  ),
                )
              else
                for (final ref in rows)
                  _QueueRow(
                    ref: ref,
                    packTitle: widget.packTitles[ref.packId] ?? ref.packId,
                    authorName: widget.packAuthors[ref.packId] ?? '-',
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// 카드 테두리 + 헤더(제목/개수/필터 칩) + 푸터(전체 보기/가장 오래 기다린
/// 요청). 로딩·에러·목록이 모두 같은 껍데기를 쓰도록 분리했다.
class _Shell extends StatelessWidget {
  final int? count;
  final _QueueFilter filter;
  final ValueChanged<_QueueFilter> onFilter;
  final VoidCallback onSeeAll;
  final DateTime? oldest;
  final Widget child;

  const _Shell({
    required this.count,
    required this.filter,
    required this.onFilter,
    required this.onSeeAll,
    required this.oldest,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AdminColors.border)),
            ),
            child: Row(
              children: [
                Text(
                  '승인 대기함',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.ivory,
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AdminColors.statusPendingBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.statusPendingText,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                for (final entry in const {
                  _QueueFilter.all: '전체',
                  _QueueFilter.create: '등록',
                  _QueueFilter.edit: '수정',
                  _QueueFilter.delete: '삭제',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _FilterChip(
                      label: entry.value,
                      selected: filter == entry.key,
                      onTap: () => onFilter(entry.key),
                    ),
                  ),
              ],
            ),
          ),
          child,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AdminColors.border)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: onSeeAll,
                  child: const Text(
                    '승인 대기함 전체 보기',
                    style: TextStyle(fontSize: 12, color: AdminColors.gold),
                  ),
                ),
                const Spacer(),
                if (oldest != null)
                  Text(
                    '가장 오래 기다린 요청 ${formatWaited(oldest)}',
                    style: TextStyle(fontSize: 11, color: AdminColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : Colors.transparent,
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

/// 열 폭은 헤더와 각 행이 같은 flex 값을 공유해야 어긋나지 않는다 — 한 곳에
/// 상수로 둔다.
const _colNode = 32;
const _colAuthor = 18;
const _colKind = 96.0;
const _colStatus = 100.0;
const _colWaited = 68.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      // const → final
      fontSize: 11,
      color: AdminColors.muted,
      fontWeight: FontWeight.w500,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          // const [ → [
          Expanded(
            flex: _colNode,
            child: Text('작품 · 노드', style: style),
          ),
          const SizedBox(width: 12), // 각 SizedBox에 const 추가
          Expanded(
            flex: _colAuthor,
            child: Text('작가', style: style),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _colKind,
            child: Text('요청', style: style),
          ),
          SizedBox(
            width: _colStatus,
            child: Text('상태', style: style),
          ),
          SizedBox(
            width: _colWaited,
            child: Text('대기', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final PendingNodeRef ref;
  final String packTitle;
  final String authorName;

  const _QueueRow({
    required this.ref,
    required this.packTitle,
    required this.authorName,
  });

  @override
  Widget build(BuildContext context) {
    final node = ref.node;
    final preview = node.previewText;
    final nodeLine = preview.isEmpty
        ? '${node.order}. (내용 없음)'
        : '${node.order}. $preview';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _colNode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nodeLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AdminColors.ivory),
                ),
                const SizedBox(height: 2),
                Text(
                  packTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: _colAuthor,
            child: Text(
              authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _colKind,
            child: Text(
              _kindLabel(node.pendingAction),
              style: TextStyle(fontSize: 12, color: AdminColors.ivory),
            ),
          ),
          SizedBox(
            width: _colStatus,
            child: Align(
              alignment: Alignment.centerLeft,
              // dirty는 로컬 편집 세션 전용 플래그라 관리자 화면에서는 항상
              // false로 넘긴다 — 여기서 보는 건 서버에 제출된 상태다.
              child: StatusTag.forNode(node, dirtyOverride: false),
            ),
          ),
          SizedBox(
            width: _colWaited,
            child: Text(
              formatWaited(ref.requestedAt),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: AdminColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

String _kindLabel(PendingAction? action) {
  switch (action) {
    case PendingAction.create:
      return '등록';
    case PendingAction.edit:
      return '수정';
    case PendingAction.delete:
      return '삭제';
    case null:
      return '-';
  }
}

/// 경과 시간을 한 단위로만 보여준다 — 개요는 "얼마나 밀렸나"만 알면 되므로
/// '3일 4시간' 같은 두 단위 표기는 폭만 차지한다.
String formatWaited(DateTime? requestedAt) {
  if (requestedAt == null) return '-';
  final diff = DateTime.now().difference(requestedAt);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inHours < 1) return '${diff.inMinutes}분';
  if (diff.inDays < 1) return '${diff.inHours}시간';
  return '${diff.inDays}일';
}
