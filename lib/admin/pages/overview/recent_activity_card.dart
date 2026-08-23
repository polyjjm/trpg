import 'package:flutter/material.dart';

import '../../models/activity_event.dart';
import '../../widgets/admin_theme.dart';

/// 개요의 "최근 활동" 카드. activityLog에 기록이 없으면(아직 아무 활동도
/// 기록되지 않은 초기 상태) 빈 문구만 보여준다 — 카드를 숨기지는 않는다.
/// 운영자가 "활동 로그가 원래 여기 있다"는 걸 알아야 로그가 비어 있는 게
/// 이상 신호인지 판단할 수 있다.
class RecentActivityCard extends StatelessWidget {
  final Stream<List<ActivityEvent>> activityStream;

  const RecentActivityCard({super.key, required this.activityStream});

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
            child: Text(
              '최근 활동',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AdminColors.ivory,
              ),
            ),
          ),
          StreamBuilder<List<ActivityEvent>>(
            stream: activityStream,
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
                return const Padding(
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

              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final event in events) _ActivityRow(event: event),
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
            decoration: const BoxDecoration(
              color: AdminColors.gold,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
