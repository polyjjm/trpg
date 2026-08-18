import 'package:flutter/material.dart';

import '../data/author_application_repository.dart';
import '../models/author_application.dart';
import '../widgets/admin_theme.dart';

/// "작가 신청" 탭 — admin 전용. 대기 중인 작가 신청서를 검토(승인/반려)한다.
///
/// 여기서 하는 승인은 "작가 자격"만 판단한다 — 이 계정이 실제로 쓴 이야기는
/// 여전히 "승인 대기함" 탭의 노드 승인 흐름(status/pendingAction/liveSnapshot)을
/// 그대로 거쳐야 한다. 두 검토는 완전히 별개다.
class AuthorApplicationsTab extends StatefulWidget {
  final AuthorApplicationRepository repository;
  final String reviewerUid;

  const AuthorApplicationsTab({
    super.key,
    required this.repository,
    required this.reviewerUid,
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
                        onApprove: () => widget.repository.approveApplication(
                          application,
                          reviewerUid: widget.reviewerUid,
                        ),
                        onReject: () => _handleReject(context, application),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

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
