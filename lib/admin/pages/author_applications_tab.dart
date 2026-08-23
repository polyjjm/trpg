import 'package:flutter/material.dart';

import '../data/activity_log_repository.dart';
import '../data/author_application_repository.dart';
import '../models/activity_event.dart';
import '../models/author_application.dart';
import '../widgets/admin_theme.dart';
import 'approvals/approval_filter.dart'
    show
        ApprovalStatusFilter,
        ApprovalStatusFilterLabel,
        formatRequestedDate,
        formatWaitedLabel;

/// "작가 신청" 탭 — admin 전용. 대기 중인 작가 신청서를 검토(승인/반려)한다.
///
/// 여기서 하는 승인은 "작가 자격"만 판단한다 — 이 계정이 실제로 쓴 이야기는
/// 여전히 "승인 대기함" 탭의 노드 승인 흐름(status/pendingAction/liveSnapshot)을
/// 그대로 거쳐야 한다. 두 검토는 완전히 별개다.
class AuthorApplicationsTab extends StatefulWidget {
  final AuthorApplicationRepository repository;
  final String reviewerUid;

  /// 승인/반려를 개요의 "최근 활동"에 남기고, "처리됨"/"전체" 상태에서
  /// 처리 이력을 읽어온다. null이면 기록도, 이력 조회도 하지 않는다.
  final ActivityLogRepository? activityLog;

  const AuthorApplicationsTab({
    super.key,
    required this.repository,
    required this.reviewerUid,
    this.activityLog,
  });

  @override
  State<AuthorApplicationsTab> createState() => _AuthorApplicationsTabState();
}

class _AuthorApplicationsTabState extends State<AuthorApplicationsTab> {
  /// ApprovalsTab에서 겪은 것과 같은 이유로 State에 한 번만 만든다 — build()가
  /// 다시 돌 때마다 watchPendingApplications()를 새로 부르면 승인/반려 직후
  /// 목록이 나타났다 사라지는 것처럼 깜빡인다.
  late final Stream<List<AuthorApplication>> _pendingStream = widget.repository
      .watchPendingApplications();

  /// "처리됨"/"전체" 상태에서만 쓰인다.
  late final Stream<List<ActivityEvent>> _historyStream =
      widget.activityLog?.watchApprovalHistory(
        kinds: const [
          ActivityKind.authorApproved,
          ActivityKind.authorRejected,
          // 자격 회수/계정 정지·해제(author_management_section.dart)도 같은
          // "이 계정에 무슨 일이 있었는지"를 묻는 이력이라 여기 같이 묶는다 —
          // author_management_section.dart는 이 탭과 달리 목록+상세 구조가
          // 아니라서 별도 처리 이력 화면을 새로 만들 이유가 없었다.
          ActivityKind.authorRevoked,
          ActivityKind.authorAccountDisabled,
          ActivityKind.authorAccountReenabled,
        ],
      ) ??
      Stream.value(const <ActivityEvent>[]);

  ApprovalStatusFilter _status = ApprovalStatusFilter.pending;

  /// activityLog.log()는 자체적으로 예외를 삼킨다(ActivityLogRepository 문서
  /// 참고) — 로그 기록 실패가 승인/반려 자체를 실패한 것처럼 보이면 안 되므로
  /// 여기서 추가 try/catch를 두지 않는다.
  Future<void> _log({
    required AuthorApplication application,
    required bool approved,
  }) async {
    final log = widget.activityLog;
    if (log == null) return;
    // author_application_preview.dart(개요의 "작가 신청" 카드)가 같은 동작을
    // 처리할 때 쓰는 문구와 정확히 맞춘다 — 어느 화면에서 처리했든 "최근 활동"
    // 카드에 같은 문장이 남아야 한다.
    await log.log(
      kind: approved
          ? ActivityKind.authorApproved
          : ActivityKind.authorRejected,
      actorUid: widget.reviewerUid,
      message: approved
          ? '${_nameOf(application)} 작가 신청 승인'
          : '${_nameOf(application)} 작가 신청 반려',
    );
  }

  Future<void> _handleApprove(AuthorApplication application) async {
    await widget.repository.approveApplication(
      application,
      reviewerUid: widget.reviewerUid,
    );
    await _log(application: application, approved: true);
  }

  Future<void> _handleReject(
    BuildContext context,
    AuthorApplication application,
  ) async {
    final reason = await _promptRejectionReason(context);
    if (reason == null) return;

    await widget.repository.rejectApplication(
      application,
      reviewerUid: widget.reviewerUid,
      reason: reason.isEmpty ? null : reason,
    );
    await _log(application: application, approved: false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '작가 신청',
              style: TextStyle(
                fontSize: 16,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '승인하면 이 계정이 바로 작가 편집기를 쓸 수 있어요. 이 계정이 실제로 쓰는 이야기는 '
              '여전히 "승인 대기함" 탭에서 따로 검토해요 — 여기서는 작가 자격만 판단해요.',
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final status in ApprovalStatusFilter.values)
                  _StatusChip(
                    label: status.label,
                    selected: _status == status,
                    onTap: () => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_status != ApprovalStatusFilter.handled)
              StreamBuilder<List<AuthorApplication>>(
                stream: _pendingStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SelectableText(
                      '작가 신청 목록을 불러오지 못했어요: ${snapshot.error}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.danger,
                      ),
                    );
                  }

                  final applications =
                      snapshot.data ?? const <AuthorApplication>[];
                  if (applications.isEmpty) {
                    return Text(
                      '대기 중인 신청이 없어요.',
                      style: TextStyle(fontSize: 13, color: AdminColors.muted),
                    );
                  }
                  return Column(
                    children: [
                      for (final application in applications)
                        _ApplicationCard(
                          application: application,
                          onApprove: () => _handleApprove(application),
                          onReject: () => _handleReject(context, application),
                        ),
                    ],
                  );
                },
              ),
            if (_status != ApprovalStatusFilter.pending) ...[
              if (_status == ApprovalStatusFilter.all)
                const SizedBox(height: 24),
              Text(
                '처리됨',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.muted,
                ),
              ),
              const SizedBox(height: 10),
              StreamBuilder<List<ActivityEvent>>(
                stream: _historyStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SelectableText(
                      '처리 이력을 불러오지 못했어요: ${snapshot.error}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.danger,
                      ),
                    );
                  }

                  final events = snapshot.data;
                  if (events == null) {
                    return Text(
                      '불러오는 중…',
                      style: TextStyle(fontSize: 13, color: AdminColors.muted),
                    );
                  }
                  if (events.isEmpty) {
                    return Text(
                      '처리된 신청이 없어요.',
                      style: TextStyle(fontSize: 13, color: AdminColors.muted),
                    );
                  }
                  return Column(
                    children: [
                      for (final event in events)
                        _HistoryApplicationCard(event: event),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
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

/// 처리 이력 한 건 — 읽기 전용, 승인/반려 버튼이 없다. 개요의 "최근 활동"
/// 카드([RecentActivityCard])와 같은 방식으로 결과 배지 + 완성된 한 줄
/// ([ActivityEvent.message])을 같이 보여준다 — activityLog는 구조화된
/// 필드 대신 완성된 문장을 남기는 설계라(activity_event.dart 문서 참고),
/// 반려 사유가 있어도 별도 필드가 아니라 이 문장 안에 있을 때만 보인다.
class _HistoryApplicationCard extends StatelessWidget {
  final ActivityEvent event;

  const _HistoryApplicationCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final approved = event.kind.isApprovalFamily;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.message,
                  style: TextStyle(fontSize: 13, color: AdminColors.ivory),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatRequestedDate(event.createdAt)} 처리'
                  '${event.createdAt == null ? '' : ' (${formatWaitedLabel(event.createdAt)} 전)'}',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: approved ? AdminColors.approveBg : AdminColors.rejectBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              approved ? '승인됨' : '반려됨',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: approved
                    ? AdminColors.approveText
                    : AdminColors.rejectText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _nameOf(AuthorApplication application) =>
    application.displayName.isEmpty ? '(이름 없음)' : application.displayName;

class _ApplicationCard extends StatelessWidget {
  final AuthorApplication application;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApplicationCard({
    required this.application,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.displayName.isEmpty
                          ? '(이름 없음)'
                          : application.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AdminColors.ivory,
                      ),
                    ),
                    if (application.submittedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDate(application.submittedAt!)} 제출',
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ActionButton(
                label: '승인',
                bg: AdminColors.approveBg,
                fg: AdminColors.approveText,
                border: AdminColors.approveBorder,
                onTap: onApprove,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                label: '반려',
                bg: AdminColors.rejectBg,
                fg: AdminColors.rejectText,
                border: AdminColors.rejectBorder,
                onTap: onReject,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            application.bio.isEmpty ? '(자기소개 없음)' : application.bio,
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.ivory,
              height: 1.6,
            ),
          ),
          if (application.portfolioLinks.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final link in application.portfolioLinks)
              Text(
                link,
                style: const TextStyle(fontSize: 12, color: AdminColors.accent),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: fg)),
      ),
    );
  }
}

Future<String?> _promptRejectionReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text('반려 사유 (선택)', style: TextStyle(color: AdminColors.ivory)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        style: TextStyle(color: AdminColors.ivory),
        decoration: InputDecoration(
          hintText: '신청자에게 보여줄 사유를 적어주세요. 비워두면 사유 없이 반려돼요.',
          hintStyle: TextStyle(color: AdminColors.muted, fontSize: 12),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AdminColors.border),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AdminColors.gold),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text(
            '반려하기',
            style: TextStyle(color: AdminColors.rejectText),
          ),
        ),
      ],
    ),
  );
}

String _formatDate(DateTime dt) =>
    '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
