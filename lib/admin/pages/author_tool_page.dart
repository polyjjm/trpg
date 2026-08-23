import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/auth/google_auth_service.dart';
import '../../core/constants/asset_paths.dart';
import '../../core/constants/external_links.dart';
import '../../core/platform/open_external_link.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/admin_notice_repository.dart';
import '../data/admin_bgm_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_sfx_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/admin_tts_voice_repository.dart';
import '../data/node_edit_session_cache.dart';
import '../models/admin_story_pack.dart';
import '../models/pack_submit_state.dart';
import '../models/story_pack_type.dart';
import '../widgets/account_menu.dart';
import '../widgets/admin_theme.dart';
import 'admin_dashboard_page.dart';
import 'admin_gate_page.dart';
import 'bgm_library_tab.dart';
import 'image_library_tab.dart';
import 'notices_tab.dart';
import 'pack_settings_page.dart';
import 'sfx_library_tab.dart';
import 'story_tab_view.dart';

enum _AdminTab { story, images, sfx, bgm, notices }

/// 로그인 + 역할 확인(author/admin) 통과 후 보이는 "작가 도구" 본체 —
/// 콘텐츠 편집(스토리 노드/이미지 라이브러리/공지사항)만 다룬다. author와
/// admin 둘 다 여기로 들어온다. 플랫폼 운영 기능(승인 대기함/작가 신청/장르
/// 관리 등)은 별도의 AdminDashboardPage다.
///
/// 상단 바 구성이 바뀌었다 — 예전엔 로고/팩 선택/팩 설정 버튼/테마/이메일
/// 배지/닉네임 입력칸/링크 3개가 전부 한 줄에 늘어서서, 정작 중요한 액션이
/// 어느 것인지 읽히지 않았다. 지금은:
///
/// - 팩 설정은 팩 셀렉터 안으로 들어갔다(드롭다운 + 구분선 + 톱니) — 팩에
///   딸린 설정이니 팩을 고르는 컨트롤이 그걸 여는 자리이기도 한 게 자연스럽다.
/// - "변경사항 전체 승인요청"이 여기로 올라왔다 — 팩 단위 액션인데 예전엔
///   노드 목록 사이드바 안에 있어서 묻혔다. 이 화면에서 유일한 코랄 채움
///   버튼이라, 한 프레임 안에서 이게 주 액션임이 분명해진다.
/// - 이메일 배지 / 닉네임 입력칸 / 로그아웃 링크는 아바타 메뉴로 접었다 —
///   닉네임은 상시 노출될 값이 아니라 프로필에 속한다.
/// - "독자로 보기"와 "관리자 페이지로"는 새 창으로 연다.
class AuthorToolPage extends StatefulWidget {
  final GoogleAuthService authService;
  final String email;

  /// author는 콘텐츠 편집만, admin은 여기에 더해 "관리자 페이지로"도 본다.
  final bool isAdmin;

  const AuthorToolPage({
    super.key,
    required this.authService,
    required this.email,
    required this.isAdmin,
  });

  @override
  State<AuthorToolPage> createState() => _AuthorToolPageState();
}

class _AuthorToolPageState extends State<AuthorToolPage> {
  final AdminStoryRepository _storyRepository = AdminStoryRepository();
  final AdminImageRepository _imageRepository = AdminImageRepository();
  final AdminSfxRepository _sfxRepository = AdminSfxRepository();
  final AdminBgmRepository _bgmRepository = AdminBgmRepository();
  final AdminTtsVoiceRepository _ttsVoiceRepository = AdminTtsVoiceRepository();
  final AdminNoticeRepository _noticeRepository = AdminNoticeRepository();
  final UserProfileRepository _userProfileRepository = UserProfileRepository();

  _AdminTab _activeTab = _AdminTab.story;
  String? _activePackId;

  /// 저장 안 한 노드 편집 내용의 세션 캐시 — 이 State가 살아있는 동안
  /// (로그아웃 전까지) 하나만 만들어서 StoryTabView에 그대로 내려준다.
  /// StoryTabView 자신은 팩을 바꿀 때마다 통째로 재생성되므로, 캐시가 거기
  /// 속해 있으면 전환할 때마다 사라진다.
  final NodeEditSessionCache _sessionCache = NodeEditSessionCache();

  @override
  void initState() {
    super.initState();
    // 관리자 페이지를 새 창으로 여는 방식: 같은 앱을 ?admin=1로 한 번 더
    // 띄우고(로그인/역할 확인은 AdminGatePage가 평소처럼 처리한다), 작가
    // 도구가 뜨는 즉시 관리자 페이지를 밀어 넣는다. 별도 배포물이 아니라
    // 같은 앱 안의 화면이라, 라우팅을 새로 깔지 않고 이걸로 끝난다.
    //
    // Navigator를 initState에서 바로 쓸 수 없으니 첫 프레임 뒤로 미룬다.
    if (widget.isAdmin && ExternalLinks.isAdminDeepLink) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pushAdminDashboard();
      });
    }
  }

  Future<void> _handleSignOut() async {
    await widget.authService.signOut();
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminGatePage(authService: widget.authService),
      ),
    );
  }

  /// 관리자 페이지 — 새 창으로 연다. 지금 주소에 admin=1을 붙인 URL이라
  /// (ExternalLinks.adminDashboardUrl) 배포 주소가 무엇이든 그대로 동작한다.
  void _openAdminDashboard() {
    openExternalLink(ExternalLinks.adminDashboardUrl);
  }

  /// ?admin=1로 열린 창에서 실제로 관리자 페이지를 띄운다.
  void _pushAdminDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDashboardPage(
          authService: widget.authService,
          email: widget.email,
        ),
      ),
    );
  }

  Future<void> _handleNewPack() async {
    final authorId = widget.authService.userId;
    if (authorId == null) return;

    final result = await showDialog<(String, StoryPackType)>(
      context: context,
      builder: (_) => const _NewPackDialog(),
    );
    if (result == null) return;

    final profile = await _userProfileRepository.fetchProfile(authorId);
    final (title, type) = result;
    final pack = await _storyRepository.createPack(
      title: title,
      authorId: authorId,
      authorName: profile?.displayName ?? '',
      type: type,
    );
    if (!mounted) return;
    setState(() => _activePackId = pack.id);
    _openPackSettings(pack.id);
  }

  void _openPackSettings(String packId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackSettingsPage(
          packId: packId,
          repository: _storyRepository,
          imageRepository: _imageRepository,
          bgmRepository: _bgmRepository,
          ttsVoiceRepository: _ttsVoiceRepository,
        ),
      ),
    );
  }

  /// admin은 전체 스토리팩을, author는 자기 소유 스토리팩만 본다.
  ///
  /// `late final`로 State가 살아있는 동안 딱 한 번만 만든다 — 예전엔 getter라
  /// build()가 돌 때마다 새 Stream을 만들어 반환했고, 그러면 바깥
  /// StreamBuilder가 "다른 스트림으로 바뀌었다"고 보고 구독을 끊었다 다시
  /// 맺으면서 화면 전체가 매번 깜빡였다.
  late final Stream<List<AdminStoryPack>> _packsStream = _createPacksStream();

  Stream<List<AdminStoryPack>> _createPacksStream() {
    final authorId = widget.authService.userId;
    if (widget.isAdmin || authorId == null) {
      return _storyRepository.watchPacks();
    }
    return _storyRepository.watchPacksForAuthor(authorId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      body: StreamBuilder<List<AdminStoryPack>>(
        stream: _packsStream,
        builder: (context, snapshot) {
          final packs = snapshot.data ?? const <AdminStoryPack>[];
          final activePackId =
              (_activePackId != null && packs.any((p) => p.id == _activePackId))
              ? _activePackId
              : (packs.isNotEmpty ? packs.first.id : null);
          final activePack = activePackId == null
              ? null
              : packs.where((p) => p.id == activePackId).firstOrNull;

          return Column(
            children: [
              _TopBar(
                email: widget.email,
                isAdmin: widget.isAdmin,
                onOpenAdminDashboard: _openAdminDashboard,
                onSignOut: _handleSignOut,
                packs: packs,
                activePack: activePack,
                onPackChanged: (id) => setState(() => _activePackId = id),
                onNewPack: _handleNewPack,
                onOpenSettings: activePackId == null
                    ? null
                    : () => _openPackSettings(activePackId),
              ),
              _NavTabs(
                active: _activeTab,
                onSelected: (tab) => setState(() => _activeTab = tab),
              ),
              Expanded(child: _buildBody(activePackId, packs)),
            ],
          );
        },
      ),
    );
  }

  /// 스토리팩 선택이 꼭 있어야 하는 탭(스토리 노드/공지사항)에서만 쓰는 안내문.
  Widget _noPackSelectedPlaceholder() {
    return Center(
      child: Text(
        '먼저 "+ 새 스토리팩"으로 스토리팩을 만들어주세요.',
        style: TextStyle(color: AdminColors.muted, fontSize: 13),
      ),
    );
  }

  Widget _buildBody(String? activePackId, List<AdminStoryPack> packs) {
    switch (_activeTab) {
      case _AdminTab.story:
        if (activePackId == null) return _noPackSelectedPlaceholder();
        final activePackMatches = packs.where((p) => p.id == activePackId);
        if (activePackMatches.isEmpty) return _noPackSelectedPlaceholder();
        final activePack = activePackMatches.first;
        return StoryTabView(
          key: ValueKey('story_$activePackId'),
          packId: activePackId,
          pack: activePack,
          repository: _storyRepository,
          imageRepository: _imageRepository,
          sfxRepository: _sfxRepository,
          bgmRepository: _bgmRepository,
          ttsVoiceRepository: _ttsVoiceRepository,
          sessionCache: _sessionCache,
        );
      case _AdminTab.images:
        return ImageLibraryTab(repository: _imageRepository);
      case _AdminTab.sfx:
        return SfxLibraryTab(
          repository: _sfxRepository,
          currentUserId: widget.authService.userId,
        );
      case _AdminTab.bgm:
        return BgmLibraryTab(
          repository: _bgmRepository,
          currentUserId: widget.authService.userId,
        );
      case _AdminTab.notices:
        if (activePackId == null) return _noPackSelectedPlaceholder();
        return NoticesTab(
          key: ValueKey('notices_$activePackId'),
          packId: activePackId,
          repository: _noticeRepository,
        );
    }
  }
}

/// 로고 → 팩 셀렉터(+팩 설정) → (여백) → 전체 승인요청 → 독자로 보기 →
/// 테마 → 아바타 메뉴.
class _TopBar extends StatelessWidget {
  final String email;
  final bool isAdmin;
  final VoidCallback onOpenAdminDashboard;
  final VoidCallback onSignOut;
  final List<AdminStoryPack> packs;
  final AdminStoryPack? activePack;
  final ValueChanged<String> onPackChanged;
  final VoidCallback onNewPack;
  final VoidCallback? onOpenSettings;

  const _TopBar({
    required this.email,
    required this.isAdmin,
    required this.onOpenAdminDashboard,
    required this.onSignOut,
    required this.packs,
    required this.activePack,
    required this.onPackChanged,
    required this.onNewPack,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      // ⚠️ SingleChildScrollView로 감싸면 안 된다 — 내용이 뷰포트보다 좁을 때
      // Viewport가 가운데로 몰아버려서, 넓은 화면에서 상단 바 내용 전체가
      // 화면 중앙에 뭉쳐 보인다(실제로 그렇게 됐다). 좁은 창에서 잘리는 건
      // Spacer가 0으로 줄어든 뒤의 이야기이고, 그때도 오른쪽 항목들은
      // 남는다.
      child: Row(
        children: [
          SvgPicture.asset(UiPaths.logo, width: 36, height: 36),
          const SizedBox(width: 11),
          Text(
            '작가 도구',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AdminColors.ivory,
            ),
          ),
          const SizedBox(width: 14),
          _VerticalRule(),
          const SizedBox(width: 14),
          _PackSelectorPill(
            packs: packs,
            activePack: activePack,
            onPackChanged: onPackChanged,
            onNewPack: onNewPack,
            onOpenSettings: onOpenSettings,
          ),
          const Spacer(),
          ValueListenableBuilder<PackSubmitState?>(
            // 전역 notifier(pack_submit_state.dart) — 값을 채우는 건
            // StoryTabView다. 아직 안 채웠으면 버튼이 아예 없다.
            valueListenable: packSubmitState,
            builder: (context, state, _) {
              if (state == null || state.unsubmittedCount == 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _SubmitAllButton(
                  count: state.unsubmittedCount,
                  onTap: state.onSubmitAll,
                ),
              );
            },
          ),
          _VerticalRule(),
          const SizedBox(width: 8),
          const ThemeModeToggle(),
          const SizedBox(width: 8),
          AccountMenu(
            email: email,
            isAdmin: isAdmin,
            onOpenAdminDashboard: onOpenAdminDashboard,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _VerticalRule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 22, color: AdminColors.border);
  }
}

/// 이 화면에서 유일한 코랄 채움 버튼 — 팩 단위 승인 요청.
class _SubmitAllButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _SubmitAllButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AdminColors.gold,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '변경사항 전체 승인요청',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 19),
              height: 19,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 팩 전환 드롭다운 + "+"(새 스토리팩) + 구분선 + 톱니(팩 설정)를 하나의
/// 컨트롤로 묶는다 — 팩 설정은 지금 보고 있는 팩에 딸린 설정이니, 팩을
/// 고르는 컨트롤이 그걸 여는 자리이기도 한 게 자연스럽다. 예전엔 옆에
/// 따로 놓인 "팩 설정" 버튼이었다.
class _PackSelectorPill extends StatelessWidget {
  final List<AdminStoryPack> packs;
  final AdminStoryPack? activePack;
  final ValueChanged<String> onPackChanged;
  final VoidCallback onNewPack;
  final VoidCallback? onOpenSettings;

  const _PackSelectorPill({
    required this.packs,
    required this.activePack,
    required this.onPackChanged,
    required this.onNewPack,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AdminColors.inputFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.inputBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activePack?.id,
                isDense: true,
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: AdminColors.muted,
                ),
                dropdownColor: AdminColors.inputDropdownMenuBg,
                style: TextStyle(
                  color: AdminColors.inputText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                hint: Text(
                  '스토리팩 선택',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13.5),
                ),
                items: packs
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(p.title, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null) onPackChanged(id);
                },
              ),
            ),
          ),
          // 팩 타입은 만든 뒤 바꿀 수 없는 값이라 배지로만 보여준다.
          if (activePack != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AdminColors.bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AdminColors.border),
              ),
              child: Text(
                activePack!.type == StoryPackType.interactive ? '인터랙티브' : '선형',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.muted,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: AdminColors.inputBorder),
          Tooltip(
            message: '새 스토리팩',
            child: InkWell(
              onTap: onNewPack,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.add_rounded,
                  size: 17,
                  color: AdminColors.gold,
                ),
              ),
            ),
          ),
          Container(width: 1, height: 20, color: AdminColors.inputBorder),
          Tooltip(
            message: '팩 설정',
            child: InkWell(
              onTap: onOpenSettings,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(7),
                bottomRight: Radius.circular(7),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                child: Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: onOpenSettings == null
                      ? AdminColors.inputDisabledBorder
                      : AdminColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTabs extends StatelessWidget {
  final _AdminTab active;
  final ValueChanged<_AdminTab> onSelected;

  const _NavTabs({required this.active, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          _NavTab(
            label: '스토리 노드',
            selected: active == _AdminTab.story,
            onTap: () => onSelected(_AdminTab.story),
          ),
          _NavTab(
            label: '이미지 라이브러리',
            selected: active == _AdminTab.images,
            onTap: () => onSelected(_AdminTab.images),
          ),
          _NavTab(
            label: '효과음 라이브러리',
            selected: active == _AdminTab.sfx,
            onTap: () => onSelected(_AdminTab.sfx),
          ),
          _NavTab(
            label: '배경음악 라이브러리',
            selected: active == _AdminTab.bgm,
            onTap: () => onSelected(_AdminTab.bgm),
          ),
          _NavTab(
            label: '공지사항',
            selected: active == _AdminTab.notices,
            onTap: () => onSelected(_AdminTab.notices),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AdminColors.gold : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? AdminColors.gold : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

/// "새 스토리팩" 다이얼로그 — 제목/타입만 받는다. 타입은 만든 뒤에는 바꿀 수
/// 없어서(인터랙티브/선형이 하위 구조부터 다르다) 여기서만 고른다. 장르/설명/
/// 표지 같은 나머지 메타데이터는 생성 직후 이동하는 PackSettingsPage에서
/// 채운다 — 그래야 나중에 같은 화면에서 다시 수정할 수 있다.
class _NewPackDialog extends StatefulWidget {
  const _NewPackDialog();

  @override
  State<_NewPackDialog> createState() => _NewPackDialogState();
}

class _NewPackDialogState extends State<_NewPackDialog> {
  final TextEditingController _titleController = TextEditingController();
  StoryPackType _type = StoryPackType.interactive;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text('새 스토리팩', style: TextStyle(color: AdminColors.ivory)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                style: TextStyle(color: AdminColors.ivory),
                decoration: InputDecoration(
                  hintText: '스토리팩 이름을 입력하세요.',
                  hintStyle: TextStyle(color: AdminColors.muted),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AdminColors.border),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AdminColors.gold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '타입',
                style: TextStyle(fontSize: 12, color: AdminColors.muted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TypeOption(
                      label: '인터랙티브',
                      selected: _type == StoryPackType.interactive,
                      onTap: () =>
                          setState(() => _type = StoryPackType.interactive),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TypeOption(
                      label: '선형',
                      selected: _type == StoryPackType.linear,
                      onTap: () => setState(() => _type = StoryPackType.linear),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '만든 뒤에는 바꿀 수 없어요 — 노드/챕터 구조가 서로 달라요.',
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
              const SizedBox(height: 6),
              Text(
                '장르/설명/표지는 다음 화면(팩 설정)에서 채워요.',
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: _titleController.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (
                  _titleController.text.trim(),
                  _type,
                )),
          child: const Text('만들기', style: TextStyle(color: AdminColors.gold)),
        ),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AdminColors.statusPendingBg : AdminColors.panel2,
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AdminColors.statusPendingText : AdminColors.ivory,
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
