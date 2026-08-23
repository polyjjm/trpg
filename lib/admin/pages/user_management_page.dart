import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../../core/user/user_role.dart';
import '../data/activity_log_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/author_account_service.dart';
import '../widgets/account_disable_dialog.dart';
import '../widgets/admin_theme.dart';
import 'approvals/approval_filter.dart' show formatRequestedDate;
import 'approvals/node_diff_view.dart' show ApprovalActionButton;
import 'author_management_section.dart';

/// "회원 관리" — 작가 탭(기존 AuthorManagementSection을 그대로 옮겨 옴)과
/// 회원 탭(모든 role을 아우르는 검색/조회) 둘을 하나의 화면으로 묶는다.
/// billing_dashboard_section.dart의 TabBar/TabBarView 패턴을 그대로
/// 따른다 — 이 admin 도구에서 탭 화면을 만들 때 이미 쓰고 있던 유일한
/// 패턴이라 새로 고안하지 않는다.
///
/// 예전엔 사이드바에 "작가 관리"만 따로 있었는데, 승인된 작가만 보여줘서
/// 일반 독자 계정을 찾아볼 방법이 없었다 — "그냥 일반유저 검색 목적"이라는
/// 요청 그대로, 회원 탭은 가벼운 목록+검색+필터일 뿐 무거운 관리 기능을
/// 새로 만들지 않는다(계정 정지/해제는 이미 있는 기능을 재사용할 뿐이다).
class UserManagementPage extends StatefulWidget {
  final UserProfileRepository userProfileRepository;
  final AdminStoryRepository storyRepository;
  final String reviewerUid;
  final ActivityLogRepository? activityLog;

  const UserManagementPage({
    super.key,
    required this.userProfileRepository,
    required this.storyRepository,
    required this.reviewerUid,
    this.activityLog,
  });

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Text(
            '회원 관리',
            style: TextStyle(
              fontSize: 16,
              color: AdminColors.ivory,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AdminColors.gold,
          unselectedLabelColor: AdminColors.muted,
          indicatorColor: AdminColors.gold,
          tabs: const [
            Tab(text: '작가'),
            Tab(text: '회원'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              AuthorManagementSection(
                userProfileRepository: widget.userProfileRepository,
                storyRepository: widget.storyRepository,
                reviewerUid: widget.reviewerUid,
                activityLog: widget.activityLog,
              ),
              _AllUsersTab(userProfileRepository: widget.userProfileRepository),
            ],
          ),
        ),
      ],
    );
  }
}

class _AllUsersTab extends StatefulWidget {
  final UserProfileRepository userProfileRepository;

  const _AllUsersTab({required this.userProfileRepository});

  @override
  State<_AllUsersTab> createState() => _AllUsersTabState();
}

class _AllUsersTabState extends State<_AllUsersTab> {
  late final Stream<List<UserProfile>> _usersStream = widget
      .userProfileRepository
      .watchAllUsers();

  String _query = '';
  UserRole? _roleFilter;

  /// 처리 중인 uid — 버튼 중복 클릭 방지(author_management_section.dart와
  /// 같은 패턴).
  final Set<String> _processingUids = {};

  Future<void> _handleToggleDisabled(UserProfile profile) async {
    if (_processingUids.contains(profile.uid)) return;
    final disabling = !profile.accountDisabled;
    final result = await showDialog<DisableAccountResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DisableAccountDialog(
        profile: profile,
        disabling: disabling,
        // "작품도 함께 비공개" 체크박스는 대상이 작가일 때만 의미가 있다 —
        // 독자/관리자 계정은 애초에 storyPacks를 소유하지 않는다(요청 사양).
        showSuspendPacksCheckbox: profile.role == UserRole.author,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _processingUids.add(profile.uid));
    try {
      // activityLog 기록은 setAuthorAccountDisabled Cloud Function이 서버에서
      // 직접 한다 — author_management_section.dart의 같은 액션과 동일한
      // 이유로 여기서 다시 기록하지 않는다.
      await AuthorAccountService().setAccountDisabled(
        uid: profile.uid,
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
      if (mounted) setState(() => _processingUids.remove(profile.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '모든 회원 계정이에요. 이름/이메일/UID로 찾거나 역할별로 좁혀 볼 수 '
            '있어요. 자격 회수 같은 작가 전용 조치는 작가 탭에서 해요 — 여기는 '
            '조회와 계정 정지/해제만 다뤄요.',
            style: TextStyle(
              fontSize: 12,
              color: AdminColors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _FilterBar(
            query: _query,
            role: _roleFilter,
            onQueryChanged: (value) => setState(() => _query = value),
            onRoleChanged: (value) => setState(() => _roleFilter = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<UserProfile>>(
              stream: _usersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText(
                    '회원 목록을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text(
                    '불러오는 중...',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                final users = snapshot.data ?? const <UserProfile>[];
                final filtered = _applyFilter(
                  users,
                  query: _query,
                  role: _roleFilter,
                );
                if (filtered.isEmpty) {
                  return Text(
                    '조건에 해당하는 회원이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final profile in filtered)
                        _UserRow(
                          profile: profile,
                          processing: _processingUids.contains(profile.uid),
                          onToggleDisabled: () =>
                              _handleToggleDisabled(profile),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// [users]에 검색어/역할 필터를 적용하고 가입일 내림차순으로 정렬한다
/// (createdAt이 없는 계정은 항상 맨 뒤 — approvals/approval_filter.dart의
/// applyApprovalFilter가 requestedAt 없는 노드를 다루는 것과 같은 규칙).
List<UserProfile> _applyFilter(
  List<UserProfile> users, {
  required String query,
  required UserRole? role,
}) {
  final normalizedQuery = query.trim().toLowerCase();

  final filtered = users.where((profile) {
    if (role != null && profile.role != role) return false;
    if (normalizedQuery.isEmpty) return true;
    final haystack = [
      profile.displayName,
      profile.email,
      profile.uid,
    ].join(' ').toLowerCase();
    return haystack.contains(normalizedQuery);
  }).toList();

  filtered.sort((a, b) {
    final x = a.createdAt;
    final y = b.createdAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x); // 최신 가입이 먼저.
  });
  return filtered;
}

class _FilterBar extends StatelessWidget {
  final String query;
  final UserRole? role;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<UserRole?> onRoleChanged;

  const _FilterBar({
    required this.query,
    required this.role,
    required this.onQueryChanged,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            onChanged: onQueryChanged,
            style: TextStyle(fontSize: 12, color: AdminColors.ivory),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              hintText: '이름 · 이메일 · UID 검색',
              hintStyle: TextStyle(fontSize: 12, color: AdminColors.muted),
              filled: true,
              fillColor: AdminColors.panel,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AdminColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AdminColors.gold),
              ),
            ),
          ),
        ),
        _RoleChip(
          label: '전체',
          selected: role == null,
          onTap: () => onRoleChanged(null),
        ),
        for (final option in UserRole.values)
          _RoleChip(
            label: option.label,
            selected: role == option,
            onTap: () => onRoleChanged(option),
          ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
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

extension on UserRole {
  String get label => switch (this) {
    UserRole.reader => '독자',
    UserRole.author => '작가',
    UserRole.admin => '관리자',
  };
}

class _UserRow extends StatelessWidget {
  final UserProfile profile;
  final bool processing;
  final VoidCallback onToggleDisabled;

  const _UserRow({
    required this.profile,
    required this.processing,
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
                        const SizedBox(width: 8),
                        _RoleBadge(role: profile.role),
                        if (profile.accountDisabled) ...[
                          const SizedBox(width: 6),
                          const _DisabledBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.email.isEmpty ? '(이메일 없음)' : profile.email,
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.uid,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AdminColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.createdAt != null
                          ? '가입일: ${formatRequestedDate(profile.createdAt)}'
                          : '가입일 미상',
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ],
                ),
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

/// role 배지 — status_tag.dart의 파스텔 bg + 진한 텍스트 배지 관례를 그대로
/// 따른다. 작가는 이미 있는 승인 파스텔 쌍(approveBg/Text — 작가 관리
/// 화면에서 승인된 작가를 다루는 것과 같은 의미)을, 관리자는 상단 바의
/// 이메일 배지/"관리자" 타이틀과 같은 badgeBg + gold를, 독자는 특별히
/// 강조할 이유가 없는 기본 계정이라 panel2 + muted를 쓴다 — 셋 다 새 색을
/// 만들지 않는다.
class _RoleBadge extends StatelessWidget {
  final UserRole role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (role) {
      UserRole.reader => (AdminColors.panel2, AdminColors.muted),
      UserRole.author => (AdminColors.approveBg, AdminColors.approveText),
      UserRole.admin => (AdminColors.badgeBg, AdminColors.gold),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// "정지됨" 배지 — author_management_section.dart의 _DisabledBadge와 같은
/// 색(dirtyBannerBg/Text, 제재 조치 계열의 유일한 앰버 톤).
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
