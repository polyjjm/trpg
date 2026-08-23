import 'package:flutter/material.dart';

import '../../data/activity_log_repository.dart';
import '../../data/author_application_repository.dart';
import '../../models/activity_event.dart';
import '../../models/author_application.dart';
import '../../widgets/admin_theme.dart';

/// 개요의 "작가 신청" 카드 — 여기서는 인라인 승인/반려를 허용한다. 노드
/// 승인과 달리 판단 근거가 카드 안에 전부 있고(자기소개 + 포트폴리오 링크),
/// 되돌릴 수 있는 결정이라(반려 후 재신청 가능) 개요에서 바로 처리해도
/// 위험하지 않다.
///
/// 처리 로직은 [AuthorApplicationRepository]의 기존 메서드를 그대로 부른다 —
/// 이 카드는 "작가 신청" 탭과 완전히 같은 일을 더 짧은 화면으로 하는 것이고,
/// 승인 규칙을 두 번 구현하지 않는다.
class AuthorApplicationPreview extends StatefulWidget {
  final AuthorApplicationRepository repository;
  final Stream<List<AuthorApplication>> pendingStream;
  final ActivityLogRepository activityLog;
  final String reviewerUid;
  final VoidCallback onSeeAll;
  final int maxCards;

  const AuthorApplicationPreview({
    super.key,
    required this.repository,
    required this.pendingStream,
    required this.activityLog,
    required this.reviewerUid,
    required this.onSeeAll,
    this.maxCards = 3,
  });

  @override
  State<AuthorApplicationPreview> createState() =>
      _AuthorApplicationPreviewState();
}

class _AuthorApplicationPreviewState extends State<AuthorApplicationPreview> {
  /// 처리 중인 신청 uid — 같은 버튼을 두 번 누르는 것을 막는다(승인이
  /// 배치 커밋이라 왕복이 짧지 않다).
  final Set<String> _busy = {};

  Future<void> _approve(AuthorApplication application) async {
    if (_busy.contains(application.uid)) return;
    setState(() => _busy.add(application.uid));
    try {
      await widget.repository.approveApplication(
        application,
        reviewerUid: widget.reviewerUid,
      );
      await widget.activityLog.log(
        kind: ActivityKind.authorApproved,
        actorUid: widget.reviewerUid,
        message: '${_nameOf(application)} 작가 신청 승인',
      );
    } finally {
      if (mounted) setState(() => _busy.remove(application.uid));
    }
  }

  Future<void> _reject(AuthorApplication application) async {
    if (_busy.contains(application.uid)) return;
    final reason = await _promptRejectionReason(context);
    if (reason == null) return;

    setState(() => _busy.add(application.uid));
    try {
      await widget.repository.rejectApplication(
        application,
        reviewerUid: widget.reviewerUid,
        reason: reason.isEmpty ? null : reason,
      );
      await widget.activityLog.log(
        kind: ActivityKind.authorRejected,
        actorUid: widget.reviewerUid,
        message: '${_nameOf(application)} 작가 신청 반려',
      );
    } finally {
      if (mounted) setState(() => _busy.remove(application.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AuthorApplication>>(
      stream: widget.pendingStream,
      builder: (context, snapshot) {
        final applications = snapshot.data;
        final shown = applications == null
            ? const <AuthorApplication>[]
            : applications.take(widget.maxCards).toList();

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AdminColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '작가 신청',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.ivory,
                      ),
                    ),
                    if (applications != null && applications.isNotEmpty) ...[
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
                          '${applications.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.statusPendingText,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (applications != null &&
                        applications.length > widget.maxCards)
                      InkWell(
                        onTap: widget.onSeeAll,
                        child: const Text(
                          '전체 보기',
                          style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.gold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: SelectableText(
                    '작가 신청을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  ),
                )
              else if (applications == null)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    '불러오는 중…',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                )
              else if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    '대기 중인 신청이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  ),
                )
              else
                for (final application in shown)
                  _ApplicationRow(
                    application: application,
                    busy: _busy.contains(application.uid),
                    onApprove: () => _approve(application),
                    onReject: () => _reject(application),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  final AuthorApplication application;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApplicationRow({
    required this.application,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _nameOf(application),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AdminColors.ivory,
                  ),
                ),
              ),
              if (application.submittedAt != null)
                Text(
                  _waited(application.submittedAt!),
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            application.bio.isEmpty ? '(자기소개 없음)' : application.bio,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: AdminColors.muted,
              height: 1.5,
            ),
          ),
          if (application.portfolioLinks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '포트폴리오 ${application.portfolioLinks.length}건',
              style: const TextStyle(fontSize: 11, color: AdminColors.accent),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _SmallButton(
                label: '승인',
                bg: AdminColors.approveBg,
                fg: AdminColors.approveText,
                border: AdminColors.approveBorder,
                onTap: busy ? null : onApprove,
              ),
              const SizedBox(width: 8),
              _SmallButton(
                label: '반려',
                bg: AdminColors.rejectBg,
                fg: AdminColors.rejectText,
                border: AdminColors.rejectBorder,
                onTap: busy ? null : onReject,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  /// null이면 처리 중 — 눌러도 아무 일도 없고 살짝 흐리게 보인다.
  final VoidCallback? onTap;

  const _SmallButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

String _nameOf(AuthorApplication application) =>
    application.displayName.isEmpty ? '(이름 없음)' : application.displayName;

String _waited(DateTime submittedAt) {
  final diff = DateTime.now().difference(submittedAt);
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  if (diff.inDays < 1) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}

/// AuthorApplicationsTab의 같은 다이얼로그와 문구·동작을 맞춘다 — 비워두면
/// 사유 없이 반려된다.
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
