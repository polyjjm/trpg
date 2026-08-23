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
import '../models/story_pack_type.dart';
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
/// 관리 등)은 별도의 AdminDashboardPage로 분리됐다 — admin 계정만 "관리자
/// 페이지로" 링크로 그쪽에 들어갈 수 있다.
///
/// 통합 헤더(로고/타이틀 + 스토리팩 전환·생성·설정 + 테마 토글 + 닉네임/유저
/// 정보 + 링크, 전부 한 줄) → navtabs → 탭별 본문 순서.
class AuthorToolPage extends StatefulWidget {
  final GoogleAuthService authService;
  final String email;

  /// author는 콘텐츠 편집만, admin은 여기에 더해 "관리자 페이지로" 링크도 본다.
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

  final TextEditingController _nicknameController = TextEditingController(
    text: '좀비작가',
  );

  _AdminTab _activeTab = _AdminTab.story;
  String? _activePackId;

  /// 저장 안 한 노드 편집 내용의 세션 캐시(node_edit_session_cache.dart) —
  /// 이 State가 살아있는 동안(로그아웃 전까지) 하나만 만들어서 StoryTabView에
  /// 그대로 내려준다. StoryTabView 자신은 팩을 바꿀 때마다 통째로
  /// 재생성되므로, 캐시가 거기 속해 있으면 전환할 때마다 사라진다 — 팩/탭을
  /// 오가도 편집 중이던 내용이 남아있어야 하니 더 오래 사는 이 State가 들고
  /// 있는다.
  final NodeEditSessionCache _sessionCache = NodeEditSessionCache();

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
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

  void _openAdminDashboard() {
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
  /// build()가 돌 때마다(탭 전환, 팩 전환 등 아무 setState에서나) 새 Stream을
  /// 만들어 반환했고, 그러면 이 Stream을 구독하는 바깥 StreamBuilder가 "다른
  /// 스트림으로 바뀌었다"고 보고 구독을 끊었다 다시 맺으면서 화면 전체가
  /// 매번 깜빡였다.
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

          return Column(
            children: [
              _TopBar(
                nicknameController: _nicknameController,
                email: widget.email,
                isAdmin: widget.isAdmin,
                onOpenAdminDashboard: _openAdminDashboard,
                onSignOut: _handleSignOut,
                packs: packs,
                activePackId: activePackId,
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

/// 라이트/다크 토글 버튼 — admin_theme.dart 상단 doc에 적어 둔 대로, 지금은
/// MaterialApp.themeMode만 바꾼다(기본 Material 위젯에만 반영, AdminColors로
/// 직접 칠한 화면 대부분은 아직 반응하지 않는다).
class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AdminTheme.mode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return InkWell(
          onTap: () => AdminTheme.toggle(),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AdminColors.panel2,
              shape: BoxShape.circle,
              border: Border.all(color: AdminColors.border),
            ),
            child: Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              size: 16,
              color: AdminColors.muted,
            ),
          ),
        );
      },
    );
  }
}

/// 로고/타이틀 → 스토리팩 선택 → 팩 설정 → (여백) → 테마 토글 → 유저 정보 →
/// 링크들까지 전부 한 줄에 담는 통합 헤더 — 예전엔 스토리팩 선택 영역이
/// 별도 배경(#131315)의 두 번째 줄이었지만, 그 구분을 없애고 top bar와 같은
/// 배경 하나로 합쳤다. 화면이 좁아 한 줄에 다 안 들어가면(주로 개발자 도구를
/// 옆에 띄운 좁은 창) 잘리는 대신 가로 스크롤되게 뒀다.
class _TopBar extends StatelessWidget {
  final TextEditingController nicknameController;
  final String email;
  final bool isAdmin;
  final VoidCallback onOpenAdminDashboard;
  final VoidCallback onSignOut;
  final List<AdminStoryPack> packs;
  final String? activePackId;
  final ValueChanged<String> onPackChanged;
  final VoidCallback onNewPack;
  final VoidCallback? onOpenSettings;

  const _TopBar({
    required this.nicknameController,
    required this.email,
    required this.isAdmin,
    required this.onOpenAdminDashboard,
    required this.onSignOut,
    required this.packs,
    required this.activePackId,
    required this.onPackChanged,
    required this.onNewPack,
    required this.onOpenSettings,
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
          SvgPicture.asset(UiPaths.logo, width: 20, height: 20),
          const SizedBox(width: 8),
          Text(
            '작가 도구',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AdminColors.ivory,
            ),
          ),
          const SizedBox(width: 16),
          _PackSelectorPill(
            packs: packs,
            activePackId: activePackId,
            onPackChanged: onPackChanged,
            onNewPack: onNewPack,
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onOpenSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.ivory,
              side: BorderSide(color: AdminColors.inputBorder),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('팩 설정', style: TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          const _ThemeModeToggle(),
          const SizedBox(width: 10),
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
          const SizedBox(width: 8),
          Text(
            '작가 닉네임',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 120,
            child: TextField(
              controller: nicknameController,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: AdminColors.inputText),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AdminColors.inputFill,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AdminColors.inputBorder),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (isAdmin) ...[
            InkWell(
              onTap: onOpenAdminDashboard,
              child: Text(
                '관리자 페이지로',
                style: TextStyle(fontSize: 12, color: AdminColors.muted),
              ),
            ),
            const SizedBox(width: 14),
          ],
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

/// 드롭다운(스토리팩 전환) + "+"(새 스토리팩) 버튼을 하나의 알약 모양
/// 컨테이너로 묶는다 — 예전엔 각자 자기 테두리를 가진 별개 위젯이었다.
class _PackSelectorPill extends StatelessWidget {
  final List<AdminStoryPack> packs;
  final String? activePackId;
  final ValueChanged<String> onPackChanged;
  final VoidCallback onNewPack;

  const _PackSelectorPill({
    required this.packs,
    required this.activePackId,
    required this.onPackChanged,
    required this.onNewPack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: AdminColors.inputFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AdminColors.inputBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activePackId,
                isDense: true,
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: AdminColors.muted,
                ),
                dropdownColor: AdminColors.inputDropdownMenuBg,
                style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                hint: Text(
                  '스토리팩 선택',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13),
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
          const SizedBox(width: 4),
          Container(width: 1, height: 18, color: AdminColors.inputBorder),
          InkWell(
            onTap: onNewPack,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(7),
              child: Icon(Icons.add_rounded, size: 16, color: AdminColors.gold),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            color: selected ? AdminColors.gold : AdminColors.ivory,
          ),
        ),
      ),
    );
  }
}
