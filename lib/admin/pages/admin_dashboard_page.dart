import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/auth/google_auth_service.dart';
import '../../core/constants/asset_paths.dart';
import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/activity_log_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/author_application_repository.dart';
import '../data/genre_repository.dart';
import '../data/home_banner_repository.dart';
import '../models/activity_event.dart';
import '../models/admin_story_pack.dart';
import '../models/author_application.dart';
import '../models/pending_node_ref.dart';
import '../widgets/account_menu.dart';
import '../widgets/admin_theme.dart';
import '../widgets/coming_soon_placeholder.dart';
import '../widgets/metric_card.dart';
import 'admin_gate_page.dart';
import 'all_story_packs_section.dart';
import 'approvals_tab.dart';
import 'author_applications_tab.dart';
import '../data/admin_image_repository.dart';
import 'genre_management_section.dart';
import 'global_notice_management_section.dart';
import '../data/global_notice_repository.dart';
import 'home_banner_management_section.dart';
import '../data/home_event_repository.dart';
import 'home_event_management_section.dart';
import 'billing_dashboard_section.dart';
import '../data/billing_repository.dart';
import 'overview/admin_card_grid.dart';
import 'overview/author_application_preview.dart';
import 'overview/pending_queue_preview.dart';
import 'overview/recent_activity_card.dart';
import 'overview/revenue_cards_row.dart';
import 'pack_approvals_tab.dart';
import 'pack_bundle_management_section.dart';
import '../data/pack_bundle_repository.dart';
import 'point_package_management_section.dart';
import '../data/point_package_repository.dart';
import 'maintenance_section.dart';
import '../data/maintenance_service.dart';
import 'user_management_page.dart';

enum _AdminSection {
  overview,
  approvals,
  packApprovals,
  reports,
  allWorks,
  authorApplications,
  userManagement,
  genreManagement,
  homeBanners,
  homeEvents,
  globalNotices,
  pointPackages,
  packBundles,
  billing,
  maintenance,
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
  final HomeEventRepository _homeEventRepository = HomeEventRepository();
  final AdminPointPackageRepository _pointPackageRepository =
      AdminPointPackageRepository();
  final AdminPackBundleRepository _packBundleRepository =
      AdminPackBundleRepository();
  final AdminBillingRepository _billingRepository = AdminBillingRepository();
  final AdminGlobalNoticeRepository _globalNoticeRepository =
      AdminGlobalNoticeRepository();
  final AdminImageRepository _imageRepository = AdminImageRepository();
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final MaintenanceService _maintenanceService = MaintenanceService();

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

  // 개요의 "최근 활동" 카드 전용 — 다른 화면은 이 스트림을 쓰지 않는다.
  late final Stream<List<ActivityEvent>> _overviewActivityStream =
      _activityLogRepository.watchRecent(limit: 6);

  // ApprovalsTab에 넘길 packTitles를 만들기 위한, 위 개요 카드용과도 별개인
  // 팩 목록 구독. 개요의 대기함 미리보기도 작품 제목/작가 이름을 여기서
  // 가져온다(구독을 또 만들지 않는다).
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
        return StreamBuilder<List<AdminStoryPack>>(
          stream: _packTitlesStream,
          builder: (context, snapshot) {
            final packs = snapshot.data ?? const <AdminStoryPack>[];
            return _OverviewSection(
              queueStream: _overviewPendingNodesStream,
              pendingApplicationsStream: _overviewPendingApplicationsStream,
              authorsStream: _overviewAuthorsStream,
              packsStream: _overviewPacksStream,
              activityStream: _overviewActivityStream,
              billingRepository: _billingRepository,
              applicationRepository: _authorApplicationRepository,
              activityLogRepository: _activityLogRepository,
              reviewerUid: widget.authService.userId ?? '',
              packTitles: {for (final p in packs) p.id: p.title},
              packAuthors: {for (final p in packs) p.id: p.authorName},
              onNavigate: (section) => setState(() => _activeSection = section),
            );
          },
        );
      case _AdminSection.approvals:
        return StreamBuilder<List<AdminStoryPack>>(
          stream: _packTitlesStream,
          builder: (context, snapshot) {
            final packs = snapshot.data ?? const <AdminStoryPack>[];
            return ApprovalsTab(
              repository: _storyRepository,
              imageRepository: _imageRepository,
              activityLog: _activityLogRepository,
              reviewerUid: widget.authService.userId ?? '',
              packTitles: {for (final p in packs) p.id: p.title},
              packTypes: {for (final p in packs) p.id: p.type},
              packAuthors: {for (final p in packs) p.id: p.authorName},
            );
          },
        );
      case _AdminSection.packApprovals:
        return StreamBuilder<List<AdminStoryPack>>(
          stream: _packTitlesStream,
          builder: (context, snapshot) {
            final packs = snapshot.data ?? const <AdminStoryPack>[];
            return PackApprovalsTab(
              repository: _storyRepository,
              imageRepository: _imageRepository,
              activityLog: _activityLogRepository,
              reviewerUid: widget.authService.userId ?? '',
              packTitles: {for (final p in packs) p.id: p.title},
              packAuthors: {for (final p in packs) p.id: p.authorName},
            );
          },
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
          activityLog: _activityLogRepository,
          reviewerUid: widget.authService.userId ?? '',
        );
      case _AdminSection.authorApplications:
        return AuthorApplicationsTab(
          repository: _authorApplicationRepository,
          activityLog: _activityLogRepository,
          reviewerUid: widget.authService.userId ?? '',
        );
      case _AdminSection.userManagement:
        return UserManagementPage(
          userProfileRepository: _userProfileRepository,
          storyRepository: _storyRepository,
          activityLog: _activityLogRepository,
          reviewerUid: widget.authService.userId ?? '',
        );
      case _AdminSection.genreManagement:
        return GenreManagementSection(repository: _genreRepository);
      case _AdminSection.homeBanners:
        return HomeBannerManagementSection(
          repository: _homeBannerRepository,
          packsStream: _packTitlesStream,
        );
      case _AdminSection.homeEvents:
        return HomeEventManagementSection(
          repository: _homeEventRepository,
          packsStream: _packTitlesStream,
        );
      case _AdminSection.globalNotices:
        return GlobalNoticeManagementSection(
          repository: _globalNoticeRepository,
          authorUid: widget.authService.userId ?? '',
        );
      case _AdminSection.pointPackages:
        return PointPackageManagementSection(
          repository: _pointPackageRepository,
        );
      case _AdminSection.packBundles:
        return PackBundleManagementSection(
          repository: _packBundleRepository,
          packsStream: _packTitlesStream,
        );
      case _AdminSection.billing:
        return BillingDashboardSection(
          billingRepository: _billingRepository,
          pointPackageRepository: _pointPackageRepository,
          storyRepository: _storyRepository,
          bundleRepository: _packBundleRepository,
        );
      case _AdminSection.maintenance:
        return MaintenanceSection(service: _maintenanceService);
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          SvgPicture.asset(UiPaths.logo, width: 36, height: 36),
          const SizedBox(width: 11),
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
          const ThemeModeToggle(),
          const SizedBox(width: 8),
          AccountMenu(
            email: email,
            isAdmin: true,
            // 이미 관리자 페이지에 있으므로 "관리자 페이지" 항목은 자기
            // 자신을 가리키는 중복 링크다 — 숨긴다.
            showAdminLink: false,
            onBackToAuthorTool: onBackToAuthorTool,
            onSignOut: onSignOut,
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
            label: '대시보드',
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
            label: '회원 관리',
            selected: active == _AdminSection.userManagement,
            onTap: () => onSelected(_AdminSection.userManagement),
          ),
          const SizedBox(height: 14),
          const _SidebarSectionHeader('돈 관리'),
          _SidebarItem(
            icon: Icons.paid_rounded,
            label: '포인트 상품 관리',
            selected: active == _AdminSection.pointPackages,
            onTap: () => onSelected(_AdminSection.pointPackages),
          ),
          _SidebarItem(
            icon: Icons.card_giftcard_rounded,
            label: '번들 상품 관리',
            selected: active == _AdminSection.packBundles,
            onTap: () => onSelected(_AdminSection.packBundles),
          ),
          _SidebarItem(
            icon: Icons.receipt_long_rounded,
            label: '결제·정산 관리',
            selected: active == _AdminSection.billing,
            onTap: () => onSelected(_AdminSection.billing),
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
          _SidebarItem(
            icon: Icons.celebration_rounded,
            label: '홈 이벤트 관리',
            selected: active == _AdminSection.homeEvents,
            onTap: () => onSelected(_AdminSection.homeEvents),
          ),
          _SidebarItem(
            icon: Icons.campaign_rounded,
            label: '공지사항 관리',
            selected: active == _AdminSection.globalNotices,
            onTap: () => onSelected(_AdminSection.globalNotices),
          ),
          const _SidebarSectionHeader('시스템'),
          _SidebarItem(
            icon: Icons.build_rounded,
            label: '유지보수',
            selected: active == _AdminSection.maintenance,
            onTap: () => onSelected(_AdminSection.maintenance),
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

/// 개요 — 드릴다운 전에 "지금 뭐가 밀려 있나"를 한 화면에서 판단하게 하는
/// 것이 목적이다. 그래서 숫자 카드(양) → 매출 카드(돈) → 대기함(무엇이
/// 얼마나 오래) → 작가 신청(바로 처리 가능) → 최근 활동(방금 무슨 일이
/// 있었나) 순으로 위계를 잡았다.
///
/// 승인/반려 중 개요에서 직접 처리하는 건 작가 신청뿐이다 — 이유는
/// overview/author_application_preview.dart와
/// overview/pending_queue_preview.dart의 클래스 doc 참고.
class _OverviewSection extends StatelessWidget {
  final Stream<List<PendingNodeRef>> queueStream;
  final Stream<List<AuthorApplication>> pendingApplicationsStream;
  final Stream<List<UserProfile>> authorsStream;
  final Stream<List<AdminStoryPack>> packsStream;
  final Stream<List<ActivityEvent>> activityStream;
  final AdminBillingRepository billingRepository;
  final AuthorApplicationRepository applicationRepository;
  final ActivityLogRepository activityLogRepository;
  final String reviewerUid;
  final Map<String, String> packTitles;
  final Map<String, String> packAuthors;
  final ValueChanged<_AdminSection> onNavigate;

  const _OverviewSection({
    required this.queueStream,
    required this.pendingApplicationsStream,
    required this.authorsStream,
    required this.packsStream,
    required this.activityStream,
    required this.billingRepository,
    required this.applicationRepository,
    required this.activityLogRepository,
    required this.reviewerUid,
    required this.packTitles,
    required this.packAuthors,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '대시보드',
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
          const SizedBox(height: 20),

          _CountCards(
            queueStream: queueStream,
            pendingApplicationsStream: pendingApplicationsStream,
            authorsStream: authorsStream,
            packsStream: packsStream,
          ),
          const SizedBox(height: 12),

          RevenueCardsRow(billingRepository: billingRepository),
          const SizedBox(height: 24),

          // 넓을 때는 좌 1.7 : 우 1, 좁을 때는 위아래로 쌓는다 — 사이드바가
          // 240을 고정으로 먹기 때문에 1100 미만에서는 2열이 둘 다 좁아진다.
          LayoutBuilder(
            builder: (context, constraints) {
              final queue = PendingQueuePreview(
                pendingNodesStream: queueStream,
                packTitles: packTitles,
                packAuthors: packAuthors,
                onSeeAll: () => onNavigate(_AdminSection.approvals),
              );
              final side = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthorApplicationPreview(
                    repository: applicationRepository,
                    pendingStream: pendingApplicationsStream,
                    activityLog: activityLogRepository,
                    reviewerUid: reviewerUid,
                    onSeeAll: () =>
                        onNavigate(_AdminSection.authorApplications),
                  ),
                  const SizedBox(height: 20),
                  RecentActivityCard(activityStream: activityStream),
                ],
              );

              if (constraints.maxWidth < 1100) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [queue, const SizedBox(height: 20), side],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 17, child: queue),
                  const SizedBox(width: 20),
                  Expanded(flex: 10, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 숫자 카드 4장 — 카드마다 스트림이 달라서 StreamBuilder를 카드 단위로
/// 감싼다(하나가 늦게 와도 나머지는 먼저 숫자를 보여준다).
class _CountCards extends StatelessWidget {
  final Stream<List<PendingNodeRef>> queueStream;
  final Stream<List<AuthorApplication>> pendingApplicationsStream;
  final Stream<List<UserProfile>> authorsStream;
  final Stream<List<AdminStoryPack>> packsStream;

  const _CountCards({
    required this.queueStream,
    required this.pendingApplicationsStream,
    required this.authorsStream,
    required this.packsStream,
  });

  @override
  Widget build(BuildContext context) {
    return AdminCardGrid(
      children: [
        StreamBuilder<List<PendingNodeRef>>(
          stream: queueStream,
          builder: (context, snapshot) =>
              MetricCard(label: '승인 대기', count: snapshot.data?.length),
        ),
        StreamBuilder<List<AuthorApplication>>(
          stream: pendingApplicationsStream,
          builder: (context, snapshot) =>
              MetricCard(label: '작가 신청', count: snapshot.data?.length),
        ),
        StreamBuilder<List<UserProfile>>(
          stream: authorsStream,
          builder: (context, snapshot) =>
              MetricCard(label: '전체 작가', count: snapshot.data?.length),
        ),
        StreamBuilder<List<AdminStoryPack>>(
          stream: packsStream,
          builder: (context, snapshot) =>
              MetricCard(label: '전체 작품', count: snapshot.data?.length),
        ),
      ],
    );
  }
}
