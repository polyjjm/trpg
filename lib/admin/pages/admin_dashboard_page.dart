import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/auth/google_auth_service.dart';
import '../../core/constants/asset_paths.dart';
import '../../core/constants/external_links.dart';
import '../../core/platform/open_external_link.dart';
import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/author_application_repository.dart';
import '../data/genre_repository.dart';
import '../data/home_banner_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/author_application.dart';
import '../models/pending_node_ref.dart';
import '../widgets/admin_theme.dart';
import '../widgets/coming_soon_placeholder.dart';
import '../widgets/metric_card.dart';
import 'admin_gate_page.dart';
import 'all_story_packs_section.dart';
import 'approvals_tab.dart';
import 'author_applications_tab.dart';
import 'author_management_section.dart';
import 'genre_management_section.dart';
import 'home_banner_management_section.dart';
import 'pack_approvals_tab.dart';

enum _AdminSection {
  overview,
  approvals,
  packApprovals,
  reports,
  allWorks,
  authorApplications,
  authorManagement,
  genreManagement,
  homeBanners,
}

/// 플랫폼 운영 전용 페이지 — author 도구(AuthorToolPage)와 별개다. 콘텐츠
/// 작성이 아니라 "이 플랫폼 전체를 운영하는 데 필요한 기능"(콘텐츠 승인,
/// 작가 심사, 장르 관리 등)을 한 곳에 모은다.
///
/// author 도구의 "관리자 페이지로" 링크로만 들어오는 걸 전제로 하지만,
/// 그 하나의 진입점만 믿지 않고 여기서도 다시 한번 role을 확인한다("탭을
/// 숨기는" 방식이 아니라 진짜 라우트 단위 게이트) — AdminGatePage와 같은
/// FutureBuilder 패턴을 그대로 따른다.
class AdminDashboardPage extends StatefulWidget {
  final GoogleAuthService authService;
  final String email;
  final UserProfileRepository? userProfileRepository;

  const AdminDashboardPage({
    super.key,
    required this.authService,
    required this.email,
    this.userProfileRepository,
  });

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late final UserProfileRepository _userProfileRepository =
      widget.userProfileRepository ?? UserProfileRepository();
  late final Future<UserProfile?> _profileFuture = _loadProfile();

  Future<UserProfile?> _loadProfile() {
    final uid = widget.authService.userId;
    if (uid == null) return Future.value(null);
    return _userProfileRepository.fetchProfile(uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AdminColors.bg,
            body: const Center(
              child: CircularProgressIndicator(color: AdminColors.gold),
            ),
          );
        }

        final profile = snapshot.data;
        if (profile == null || !profile.isAdmin) {
          return const _NotAuthorized();
        }

        return _AdminDashboardShell(
          authService: widget.authService,
          email: widget.email,
        );
      },
    );
  }
}

class _NotAuthorized extends StatelessWidget {
  const _NotAuthorized();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: AdminColors.danger,
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  '관리자 권한이 없어요',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.ivory,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '이 페이지는 admin 계정만 볼 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AdminColors.muted),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.ivory,
                    side: BorderSide(color: AdminColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('작가 도구로 돌아가기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminDashboardShell extends StatefulWidget {
  final GoogleAuthService authService;
  final String email;

  const _AdminDashboardShell({required this.authService, required this.email});

  @override
  State<_AdminDashboardShell> createState() => _AdminDashboardShellState();
}

class _AdminDashboardShellState extends State<_AdminDashboardShell> {
  final AdminStoryRepository _storyRepository = AdminStoryRepository();
  final AuthorApplicationRepository _authorApplicationRepository =
      AuthorApplicationRepository();
  final UserProfileRepository _userProfileRepository = UserProfileRepository();
  final GenreRepository _genreRepository = GenreRepository();
  final HomeBannerRepository _homeBannerRepository = HomeBannerRepository();

  _AdminSection _activeSection = _AdminSection.overview;

  // 사이드바 배지 전용 — 개요 카드, ApprovalsTab/AuthorApplicationsTab 자체
  // 구독과는 각각 별개 인스턴스다. _NavTabs/ApprovalsTab에서 겪었던 "부모가
  // 재빌드될 때마다 새 스트림이 생겨서 깜빡이는" 문제를 피하려고 late final로
  // State가 살아있는 동안 한 번만 만든다.
  late final Stream<List<PendingNodeRef>> _sidebarPendingNodesStream =
      _storyRepository.watchPendingNodes();
  late final Stream<List<AuthorApplication>> _sidebarPendingApplicationsStream =
      _authorApplicationRepository.watchPendingApplications();
  late final Stream<List<AdminStoryPack>> _sidebarPendingSerializationStream =
      _storyRepository.watchPendingSerializationRequests();
  late final Stream<List<AdminStoryPack>> _sidebarPendingMetadataStream =
      _storyRepository.watchPendingMetadataEdits();

  // 개요 카드 전용 — 사이드바 배지와도, ApprovalsTab 자체 구독과도 별개.
  late final Stream<List<PendingNodeRef>> _overviewPendingNodesStream =
      _storyRepository.watchPendingNodes();
  late final Stream<List<AuthorApplication>>
  _overviewPendingApplicationsStream = _authorApplicationRepository
      .watchPendingApplications();
  late final Stream<List<AdminStoryPack>> _overviewPacksStream =
      _storyRepository.watchPacks();
  late final Stream<List<UserProfile>> _overviewAuthorsStream =
      _userProfileRepository.watchAuthors();

  // ApprovalsTab에 넘길 packTitles를 만들기 위한, 위 개요 카드용과도 별개인
  // 팩 목록 구독.
  late final Stream<List<AdminStoryPack>> _packTitlesStream = _storyRepository
      .watchPacks();

  Future<void> _handleSignOut() async {
    await widget.authService.signOut();
    if (!mounted) return;
    // 작가 도구까지 포함해 스택을 통째로 비우고 게이트부터 다시 시작한다 —
    // 로그아웃 후 pop만 하면 이미 로그아웃된 작가 도구 화면이 남아있게 된다.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminGatePage(authService: widget.authService),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      body: Column(
        children: [
          _DashboardTopBar(
            email: widget.email,
            onBackToAuthorTool: () => Navigator.pop(context),
            onSignOut: _handleSignOut,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  active: _activeSection,
                  onSelected: (section) =>
                      setState(() => _activeSection = section),
                  pendingNodesStream: _sidebarPendingNodesStream,
                  pendingApplicationsStream: _sidebarPendingApplicationsStream,
                  pendingSerializationStream:
                      _sidebarPendingSerializationStream,
                  pendingMetadataStream: _sidebarPendingMetadataStream,
                ),
                Container(width: 1, color: AdminColors.border),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_activeSection) {
      case _AdminSection.overview:
        return _OverviewSection(
          pendingNodesStream: _overviewPendingNodesStream,
          pendingApplicationsStream: _overviewPendingApplicationsStream,
          authorsStream: _overviewAuthorsStream,
          packsStream: _overviewPacksStream,
        );
      case _AdminSection.approvals:
        return StreamBuilder<List<AdminStoryPack>>(
          stream: _packTitlesStream,
          builder: (context, snapshot) {
            final packs = snapshot.data ?? const <AdminStoryPack>[];
            return ApprovalsTab(
              repository: _storyRepository,
              packTitles: {for (final p in packs) p.id: p.title},
            );
          },
        );
      case _AdminSection.packApprovals:
        return PackApprovalsTab(
          repository: _storyRepository,
          reviewerUid: widget.authService.userId ?? '',
        );
      case _AdminSection.reports:
        return const ComingSoonPlaceholder(
          title: '신고 처리는 아직 준비중이에요',
          description: '신고 접수 기능이 생기면 여기서 검토·처리해요.',
        );
      case _AdminSection.allWorks:
        return AllStoryPacksSection(
          storyRepository: _storyRepository,
          userProfileRepository: _userProfileRepository,
        );
      case _AdminSection.authorApplications:
        return AuthorApplicationsTab(
          repository: _authorApplicationRepository,
          reviewerUid: widget.authService.userId ?? '',
        );
      case _AdminSection.authorManagement:
        return AuthorManagementSection(
          userProfileRepository: _userProfileRepository,
          storyRepository: _storyRepository,
        );
      case _AdminSection.genreManagement:
        return GenreManagementSection(repository: _genreRepository);
      case _AdminSection.homeBanners:
        return HomeBannerManagementSection(
          repository: _homeBannerRepository,
          packsStream: _packTitlesStream,
        );
    }
  }
}

class _DashboardTopBar extends StatelessWidget {
  final String email;
  final VoidCallback onBackToAuthorTool;
  final VoidCallback onSignOut;

  const _DashboardTopBar({
    required this.email,
    required this.onBackToAuthorTool,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          SvgPicture.asset(UiPaths.logo, width: 20, height: 20),
          const SizedBox(width: 8),
          Text(
            '관리자',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AdminColors.ivory,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AdminColors.badgeBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              email,
              style: const TextStyle(fontSize: 10, color: AdminColors.gold),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onBackToAuthorTool,
            child: Text(
              '작가 도구로',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
          ),
          const SizedBox(width: 14),
          InkWell(
            onTap: () => openExternalLink(ExternalLinks.readerAppUrl),
            child: Text(
              '독자로 보기',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
          ),
          const SizedBox(width: 14),
          InkWell(
            onTap: onSignOut,
            child: Text(
              '로그아웃',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final _AdminSection active;
  final ValueChanged<_AdminSection> onSelected;
  final Stream<List<PendingNodeRef>> pendingNodesStream;
  final Stream<List<AuthorApplication>> pendingApplicationsStream;
  final Stream<List<AdminStoryPack>> pendingSerializationStream;
  final Stream<List<AdminStoryPack>> pendingMetadataStream;

  const _Sidebar({
    required this.active,
    required this.onSelected,
    required this.pendingNodesStream,
    required this.pendingApplicationsStream,
    required this.pendingSerializationStream,
    required this.pendingMetadataStream,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AdminColors.panel,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _SidebarItem(
            icon: Icons.dashboard_rounded,
            label: '개요',
            selected: active == _AdminSection.overview,
            onTap: () => onSelected(_AdminSection.overview),
          ),
          const SizedBox(height: 14),
          const _SidebarSectionHeader('콘텐츠 운영'),
          StreamBuilder<List<PendingNodeRef>>(
            stream: pendingNodesStream,
            builder: (context, snapshot) => _SidebarItem(
              icon: Icons.fact_check_rounded,
              label: '승인 대기함',
              badgeCount: snapshot.data?.length,
              selected: active == _AdminSection.approvals,
              onTap: () => onSelected(_AdminSection.approvals),
            ),
          ),
          StreamBuilder<List<AdminStoryPack>>(
            stream: pendingSerializationStream,
            builder: (context, serializationSnapshot) {
              return StreamBuilder<List<AdminStoryPack>>(
                stream: pendingMetadataStream,
                builder: (context, metadataSnapshot) {
                  final count =
                      (serializationSnapshot.data?.length ?? 0) +
                      (metadataSnapshot.data?.length ?? 0);
                  return _SidebarItem(
                    icon: Icons.rate_review_rounded,
                    label: '스토리팩 승인',
                    badgeCount: count,
                    selected: active == _AdminSection.packApprovals,
                    onTap: () => onSelected(_AdminSection.packApprovals),
                  );
                },
              );
            },
          ),
          _SidebarItem(
            icon: Icons.flag_rounded,
            label: '신고 처리',
            selected: active == _AdminSection.reports,
            onTap: () => onSelected(_AdminSection.reports),
          ),
          _SidebarItem(
            icon: Icons.auto_stories_rounded,
            label: '전체 작품 목록',
            selected: active == _AdminSection.allWorks,
            onTap: () => onSelected(_AdminSection.allWorks),
          ),
          const SizedBox(height: 14),
          const _SidebarSectionHeader('사람 관리'),
          StreamBuilder<List<AuthorApplication>>(
            stream: pendingApplicationsStream,
            builder: (context, snapshot) => _SidebarItem(
              icon: Icons.how_to_reg_rounded,
              label: '작가 신청',
              badgeCount: snapshot.data?.length,
              selected: active == _AdminSection.authorApplications,
              onTap: () => onSelected(_AdminSection.authorApplications),
            ),
          ),
          _SidebarItem(
            icon: Icons.groups_rounded,
            label: '작가 관리',
            selected: active == _AdminSection.authorManagement,
            onTap: () => onSelected(_AdminSection.authorManagement),
          ),
          const SizedBox(height: 14),
          const _SidebarSectionHeader('돈 관리'),
          const _SidebarPlaceholderItem(
            icon: Icons.receipt_long_rounded,
            label: '결제 내역',
          ),
          const _SidebarPlaceholderItem(
            icon: Icons.bar_chart_rounded,
            label: '매출 대시보드',
          ),
          const SizedBox(height: 14),
          const _SidebarSectionHeader('설정'),
          _SidebarItem(
            icon: Icons.sell_rounded,
            label: '장르 관리',
            selected: active == _AdminSection.genreManagement,
            onTap: () => onSelected(_AdminSection.genreManagement),
          ),
          _SidebarItem(
            icon: Icons.view_carousel_rounded,
            label: '홈 배너 관리',
            selected: active == _AdminSection.homeBanners,
            onTap: () => onSelected(_AdminSection.homeBanners),
          ),
        ],
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  final String label;

  const _SidebarSectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: AdminColors.muted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badgeCount;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AdminColors.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AdminColors.gold : AdminColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? AdminColors.gold : AdminColors.ivory,
                ),
              ),
            ),
            if (badgeCount != null && badgeCount! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminColors.statusPendingBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AdminColors.statusPendingText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "돈 관리" 아래 결제 내역/매출 대시보드 — 백엔드가 아예 없어 클릭할 수
/// 없다. 로드맵에는 보이되, 흐릿하고 "준비중" 표시가 붙은 채로 조용히 있는다.
class _SidebarPlaceholderItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SidebarPlaceholderItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AdminColors.muted.withOpacity(0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.muted.withOpacity(0.5),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: AdminColors.border),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '준비중',
              style: TextStyle(fontSize: 9, color: AdminColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  final Stream<List<PendingNodeRef>> pendingNodesStream;
  final Stream<List<AuthorApplication>> pendingApplicationsStream;
  final Stream<List<UserProfile>> authorsStream;
  final Stream<List<AdminStoryPack>> packsStream;

  const _OverviewSection({
    required this.pendingNodesStream,
    required this.pendingApplicationsStream,
    required this.authorsStream,
    required this.packsStream,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '개요',
            style: TextStyle(
              fontSize: 18,
              color: AdminColors.ivory,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '드릴다운하기 전에 한눈에 보는 현재 상태예요.',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 180,
                child: StreamBuilder<List<PendingNodeRef>>(
                  stream: pendingNodesStream,
                  builder: (context, snapshot) =>
                      MetricCard(label: '승인 대기', count: snapshot.data?.length),
                ),
              ),
              SizedBox(
                width: 180,
                child: StreamBuilder<List<AuthorApplication>>(
                  stream: pendingApplicationsStream,
                  builder: (context, snapshot) =>
                      MetricCard(label: '작가 신청', count: snapshot.data?.length),
                ),
              ),
              SizedBox(
                width: 180,
                child: StreamBuilder<List<UserProfile>>(
                  stream: authorsStream,
                  builder: (context, snapshot) =>
                      MetricCard(label: '전체 작가', count: snapshot.data?.length),
                ),
              ),
              SizedBox(
                width: 180,
                child: StreamBuilder<List<AdminStoryPack>>(
                  stream: packsStream,
                  builder: (context, snapshot) =>
                      MetricCard(label: '전체 작품', count: snapshot.data?.length),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
