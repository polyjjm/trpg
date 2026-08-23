import 'package:flutter/material.dart';

import '../../models/activity_event.dart';
import '../../widgets/admin_theme.dart';

/// 최근 활동 카드 헤더의 종류 필터 칩 — 클라이언트 필터일 뿐이다(Firestore
/// 쿼리를 늘리지 않는다, 요청 사양). "승인·반려"는 나머지(상품/배너/공지)를
/// 빼고 전부, "상품·운영"은 그 셋만 — [ActivityKindDisplay]가 이미 두
/// 그룹(승인/반려 계열 vs 그 외)으로 색을 가르고 있으므로 그 판정을 그대로
/// 재사용한다.
enum _ActivityFilterCategory { all, approvalsAndRejections, operations }

extension on _ActivityFilterCategory {
  String get label => switch (this) {
    _ActivityFilterCategory.all => '전체',
    _ActivityFilterCategory.approvalsAndRejections => '승인·반려',
    _ActivityFilterCategory.operations => '상품·운영',
  };

  bool matches(ActivityKind kind) => switch (this) {
    _ActivityFilterCategory.all => true,
    _ActivityFilterCategory.approvalsAndRejections =>
      kind != ActivityKind.productChanged &&
          kind != ActivityKind.bannerChanged &&
          kind != ActivityKind.noticeChanged,
    _ActivityFilterCategory.operations =>
      kind == ActivityKind.productChanged ||
          kind == ActivityKind.bannerChanged ||
          kind == ActivityKind.noticeChanged,
  };
}

/// 개요의 "최근 활동" 카드. activityLog에 기록이 없으면(아직 아무 활동도
/// 기록되지 않은 초기 상태) 빈 문구만 보여준다 — 카드를 숨기지는 않는다.
/// 운영자가 "활동 로그가 원래 여기 있다"는 걸 알아야 로그가 비어 있는 게
/// 이상 신호인지 판단할 수 있다.
class RecentActivityCard extends StatefulWidget {
  final Stream<List<ActivityEvent>> activityStream;

  const RecentActivityCard({super.key, required this.activityStream});

  @override
  State<RecentActivityCard> createState() => _RecentActivityCardState();
}

class _RecentActivityCardState extends State<RecentActivityCard> {
  _ActivityFilterCategory _category = _ActivityFilterCategory.all;

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
                  '최근 활동',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.ivory,
                  ),
                ),
                const Spacer(),
                for (final category in _ActivityFilterCategory.values) ...[
                  _FilterChip(
                    label: category.label,
                    selected: _category == category,
                    onTap: () => setState(() => _category = category),
                  ),
                  if (category != _ActivityFilterCategory.values.last)
                    const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          StreamBuilder<List<ActivityEvent>>(
            stream: widget.activityStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: SelectableText(
                    '최근 활동을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  ),
                );
              }

              final events = snapshot.data;
              if (events == null) {
                return Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    '불러오는 중…',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                );
              }
              if (events.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    '아직 기록된 활동이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  ),
                );
              }

              final visible = events
                  .where((event) => _category.matches(event.kind))
                  .toList();
              if (visible.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    '이 필터에 해당하는 활동이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final event in visible) _ActivityRow(event: event),
                  ],
                ),
              );
            },
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
          color: selected ? AdminColors.badgeBg : Colors.transparent,
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AdminColors.gold : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

/// 종류 라벨 배지 — status_tag.dart의 파스텔 bg + 진한 텍스트 관례
/// (ActivityKindDisplay.badgeBg/badgeText가 실제 색 판정을 담당한다).
class _ActivityKindBadge extends StatelessWidget {
  final ActivityKind kind;

  const _ActivityKindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kind.badgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        kind.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: kind.badgeText,
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityEvent event;

  const _ActivityRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(
              color: event.kind.dotColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActivityKindBadge(kind: event.kind),
                const SizedBox(height: 4),
                Text(
                  event.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: AdminColors.ivory,
                    height: 1.5,
                  ),
                ),
                if (event.createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _relative(event.createdAt!),
                    style: TextStyle(fontSize: 11, color: AdminColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 사흘까지는 상대 시간, 그 이후는 날짜 — "5일 전"보다 "08.18"이 더 쓸모 있다.
String _relative(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  if (diff.inDays < 1) return '${diff.inHours}시간 전';
  if (diff.inDays < 4) return '${diff.inDays}일 전';
  return '${at.month.toString().padLeft(2, '0')}.${at.day.toString().padLeft(2, '0')}';
}
