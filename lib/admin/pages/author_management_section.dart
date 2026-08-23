import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/user/author_application_status.dart';
import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../../core/user/user_role.dart';
import '../data/activity_log_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/author_account_service.dart';
import '../models/activity_event.dart';
import '../models/admin_story_pack.dart';
import '../widgets/account_disable_dialog.dart';
import '../widgets/admin_theme.dart';
import '../widgets/checkbox_row.dart';
import '../widgets/labeled_field.dart';
import 'approvals/node_diff_view.dart' show ApprovalActionButton;

/// "작가 관리" — 승인된 작가(role == 'author') 목록과 각자의 스토리팩 개수,
/// 그리고 두 가지 조치: **자격 회수**(role을 reader로 되돌리는, 되돌릴 수
/// 있는 조치)와 **계정 정지**(Firebase Auth 로그인 자체를 막는, 마찬가지로
/// 되돌릴 수 있는 조치). 둘 다 완전한 계정 삭제가 아니다 — 삭제(예: 법적/
/// 개인정보 요청)는 훨씬 무겁게 게이트해야 할 별도 기능이라 지금은 다루지
/// 않는다.
class AuthorManagementSection extends StatefulWidget {
  final UserProfileRepository userProfileRepository;
  final AdminStoryRepository storyRepository;
  final String reviewerUid;

  /// 자격 회수/계정 정지·해제를 개요의 "최근 활동"에 남긴다. null이면
  /// 기록하지 않는다. 계정 정지/해제 자체는 setAuthorAccountDisabled Cloud
  /// Function이 서버에서 이미 기록하므로(중복 방지) 이 저장소는 자격 회수
  /// 로그(클라이언트 직접 쓰기)에만 쓰인다.
  final ActivityLogRepository? activityLog;

  const AuthorManagementSection({
    super.key,
    required this.userProfileRepository,
    required this.storyRepository,
    required this.reviewerUid,
    this.activityLog,
  });

  @override
  State<AuthorManagementSection> createState() =>
      _AuthorManagementSectionState();
}

class _AuthorManagementSectionState extends State<AuthorManagementSection> {
  late final Stream<List<UserProfile>> _authorsStream = widget
      .userProfileRepository
      .watchAuthors();
  late final Stream<List<AdminStoryPack>> _packsStream = widget.storyRepository
      .watchPacks();

  /// 처리 중인 uid — 버튼 중복 클릭 방지.
  final Set<String> _processingUids = {};

  Future<void> _handleRevoke(UserProfile author) async {
    if (_processingUids.contains(author.uid)) return;
    final result = await showDialog<_RevokeResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RevokeDialog(author: author),
    );
    if (result == null || !mounted) return;

    setState(() => _processingUids.add(author.uid));
    try {
      await widget.userProfileRepository.updateRole(
        author.uid,
        UserRole.reader,
        // 회수 후 재신청이 가능해야 한다(AuthorApplicationStatus.none/rejected
        // 일 때만 AdminGatePage가 재신청 폼을 보여준다) — 반려가 아니라
        // 관리자가 기존 자격을 거둬들이는 것이므로 rejected가 아니라 none이
        // 정확한 의미다.
        authorApplicationStatus: AuthorApplicationStatus.none,
      );
      if (result.suspendPacks) {
        await widget.storyRepository.suspendPacksForAuthor(
          author.uid,
          reviewerUid: widget.reviewerUid,
          reason: result.reason ?? '작가 자격 회수로 인한 일괄 비공개',
        );
      }
      final log = widget.activityLog;
      if (log != null) {
        final name = author.displayName.isEmpty
            ? '(이름 없음)'
            : author.displayName;
        await log.log(
          kind: ActivityKind.authorRevoked,
          actorUid: widget.reviewerUid,
          message:
              '$name 작가 자격 회수'
              '${result.suspendPacks ? ' (작품 함께 비공개)' : ''}',
          authorName: author.displayName,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('작가 자격을 회수했어요.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('자격 회수에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _processingUids.remove(author.uid));
    }
  }

  Future<void> _handleToggleDisabled(UserProfile author) async {
    if (_processingUids.contains(author.uid)) return;
    final disabling = !author.accountDisabled;
    final result = await showDialog<DisableAccountResult>(
      context: context,
      barrierDismissible: false,
      // 이 탭은 대상이 항상 작가라 체크박스를 늘 보여준다 — 옮기기 전
      // 동작과 완전히 같다(account_disable_dialog.dart 문서 참고).
      builder: (_) => DisableAccountDialog(
        profile: author,
        disabling: disabling,
        showSuspendPacksCheckbox: true,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _processingUids.add(author.uid));
    try {
      // activityLog 기록은 setAuthorAccountDisabled Cloud Function이 서버에서
      // 직접 한다(위 클래스 문서 참고) — 여기서 다시 기록하면 같은 조치가
      // 두 줄로 남는다.
      await AuthorAccountService().setAccountDisabled(
        uid: author.uid,
        disabled: disabling,
        suspendPacks: disabling && result.suspendPacks,
        reason: result.reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(disabling ? '계정을 정지했어요.' : '정지를 해제했어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is FirebaseFunctionsException
          ? (e.message ?? '처리에 실패했어요.')
          : '처리에 실패했어요: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AdminColors.danger),
      );
    } finally {
      if (mounted) setState(() => _processingUids.remove(author.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '작가 관리',
              style: TextStyle(
                fontSize: 16,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '승인된 작가 계정과 각자 만든 스토리팩 수예요. "자격 회수"는 role을 '
              'reader로 되돌리고(되돌릴 수 있음), "계정 정지"는 로그인 자체를 '
              '막아요(마찬가지로 되돌릴 수 있음 — 진짜 계정 삭제는 아니에요).',
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<UserProfile>>(
              stream: _authorsStream,
              builder: (context, authorsSnapshot) {
                if (authorsSnapshot.hasError) {
                  return SelectableText(
                    '작가 목록을 불러오지 못했어요: ${authorsSnapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  );
                }
                if (authorsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return Text(
                    '불러오는 중...',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                final authors = List<UserProfile>.of(
                  authorsSnapshot.data ?? const <UserProfile>[],
                )..sort((a, b) => a.displayName.compareTo(b.displayName));
                if (authors.isEmpty) {
                  return Text(
                    '승인된 작가가 아직 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                return StreamBuilder<List<AdminStoryPack>>(
                  stream: _packsStream,
                  builder: (context, packsSnapshot) {
                    final packs =
                        packsSnapshot.data ?? const <AdminStoryPack>[];
                    final packCountByAuthor = <String, int>{};
                    for (final pack in packs) {
                      packCountByAuthor[pack.authorId] =
                          (packCountByAuthor[pack.authorId] ?? 0) + 1;
                    }

                    return Column(
                      children: [
                        for (final author in authors)
                          _AuthorRow(
                            profile: author,
                            packCount: packCountByAuthor[author.uid] ?? 0,
                            processing: _processingUids.contains(author.uid),
                            onRevoke: () => _handleRevoke(author),
                            onToggleDisabled: () =>
                                _handleToggleDisabled(author),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final UserProfile profile;
  final int packCount;
  final bool processing;
  final VoidCallback onRevoke;
  final VoidCallback onToggleDisabled;

  const _AuthorRow({
    required this.profile,
    required this.packCount,
    required this.processing,
    required this.onRevoke,
    required this.onToggleDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName.isEmpty
                                ? '(이름 없음)'
                                : profile.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AdminColors.ivory,
                            ),
                          ),
                        ),
                        if (profile.accountDisabled) ...[
                          const SizedBox(width: 8),
                          const _DisabledBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.email,
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AdminColors.panel2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '작품 $packCount개',
                  style: TextStyle(fontSize: 12, color: AdminColors.ivory),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              ApprovalActionButton(
                label: '자격 회수',
                bg: AdminColors.rejectBg,
                fg: AdminColors.rejectText,
                border: AdminColors.rejectBorder,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                fontSize: 12,
                onTap: processing ? null : onRevoke,
              ),
              const SizedBox(width: 8),
              ApprovalActionButton(
                label: profile.accountDisabled ? '정지 해제' : '계정 정지',
                bg: profile.accountDisabled
                    ? AdminColors.approveBg
                    : AdminColors.rejectBg,
                fg: profile.accountDisabled
                    ? AdminColors.approveText
                    : AdminColors.rejectText,
                border: profile.accountDisabled
                    ? AdminColors.approveBorder
                    : AdminColors.rejectBorder,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                fontSize: 12,
                onTap: processing ? null : onToggleDisabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "정지됨" 배지 — all_story_packs_section.dart의 "내려짐" 배지와 같은
/// 색(dirtyBannerBg/Text, 제재 조치 계열의 유일한 앰버 톤)을 쓴다 — 둘 다
/// "지금 관리자 조치로 제한된 상태"라는 같은 의미라서 같은 색으로 통일한다.
class _DisabledBadge extends StatelessWidget {
  const _DisabledBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AdminColors.dirtyBannerBg,
        border: Border.all(color: AdminColors.dirtyBannerBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '정지됨',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AdminColors.dirtyBannerText,
        ),
      ),
    );
  }
}

class _RevokeResult {
  final String? reason;
  final bool suspendPacks;

  const _RevokeResult({required this.reason, required this.suspendPacks});
}

/// 사유는 선택이다 — 반려/강제 내리기와 달리 "작가에게 그대로 전달되는
/// 사유"가 아니라 admin 내부 기록용이라, 굳이 강제할 이유가 없다는 판단
/// (요청 사양에도 "reason field (optional)"로 명시돼 있다).
class _RevokeDialog extends StatefulWidget {
  final UserProfile author;

  const _RevokeDialog({required this.author});

  @override
  State<_RevokeDialog> createState() => _RevokeDialogState();
}

class _RevokeDialogState extends State<_RevokeDialog> {
  final TextEditingController _reasonController = TextEditingController();
  bool _suspendPacks = true;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.author.displayName.isEmpty
        ? '(이름 없음)'
        : widget.author.displayName;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text('작가 자격 회수', style: TextStyle(color: AdminColors.ivory)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name 계정의 역할을 독자(reader)로 되돌려요. 작가 편집기 접근 '
              '권한이 즉시 사라져요 — role을 다시 author로 바꾸면 되돌릴 수 있어요.',
              style: TextStyle(
                fontSize: 12.5,
                color: AdminColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '사유 (선택)',
              child: TextField(
                controller: _reasonController,
                maxLines: 2,
                style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                decoration: adminInputDecoration(hintText: '예: 이용 정책 위반'),
              ),
            ),
            const SizedBox(height: 14),
            CheckboxRow(
              value: _suspendPacks,
              onChanged: (value) => setState(() => _suspendPacks = value),
              label: '이 작가의 작품도 함께 비공개 처리',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _RevokeResult(
              reason: _reasonController.text.trim().isEmpty
                  ? null
                  : _reasonController.text.trim(),
              suspendPacks: _suspendPacks,
            ),
          ),
          child: Text('자격 회수', style: TextStyle(color: AdminColors.rejectText)),
        ),
      ],
    );
  }
}
