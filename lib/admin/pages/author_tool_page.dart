import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/auth/google_auth_service.dart';
import '../../core/constants/asset_paths.dart';
import '../../core/constants/external_links.dart';
import '../../core/platform/open_external_link.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/admin_notice_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';
import 'admin_dashboard_page.dart';
import 'admin_gate_page.dart';
import 'image_library_tab.dart';
import 'notices_tab.dart';
import 'pack_settings_page.dart';
import 'story_tab_view.dart';

enum _AdminTab { story, images, notices }

/// 로그인 + 역할 확인(author/admin) 통과 후 보이는 "작가 도구" 본체 —
/// 콘텐츠 편집(스토리 노드/이미지 라이브러리/공지사항)만 다룬다. author와
/// admin 둘 다 여기로 들어온다. 플랫폼 운영 기능(승인 대기함/작가 신청/장르
/// 관리 등)은 별도의 AdminDashboardPage로 분리됐다 — admin 계정만 "관리자
/// 페이지로" 링크로 그쪽에 들어갈 수 있다.
///
/// topbar(닉네임) → pack-bar(스토리팩 전환/생성) → navtabs → 탭별 본문
/// 순서로, story_editor_prototype.html의 레이아웃을 그대로 따른다.
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
  final AdminNoticeRepository _noticeRepository = AdminNoticeRepository();
  final UserProfileRepository _userProfileRepository = UserProfileRepository();

  final TextEditingController _nicknameController = TextEditingController(text: '좀비작가');

  _AdminTab _activeTab = _AdminTab.story;
  String? _activePackId;

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
      MaterialPageRoute(builder: (_) => AdminGatePage(authService: widget.authService)),
    );
  }

  void _openAdminDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDashboardPage(authService: widget.authService, email: widget.email),
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
          final activePackId = (_activePackId != null && packs.any((p) => p.id == _activePackId))
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
              ),
              _PackBar(
                packs: packs,
                activePackId: activePackId,
                onPackChanged: (id) => setState(() => _activePackId = id),
                onNewPack: _handleNewPack,
                onOpenSettings: activePackId == null ? null : () => _openPackSettings(activePackId),
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
    return const Center(
      child: Text('먼저 "+ 새 스토리팩"으로 스토리팩을 만들어주세요.', style: TextStyle(color: AdminColors.muted, fontSize: 13)),
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
        );
      case _AdminTab.images:
        return ImageLibraryTab(repository: _imageRepository);
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

class _TopBar extends StatelessWidget {
  final TextEditingController nicknameController;
  final String email;
  final bool isAdmin;
  final VoidCallback onOpenAdminDashboard;
  final VoidCallback onSignOut;

  const _TopBar({
    required this.nicknameController,
    required this.email,
    required this.isAdmin,
    required this.onOpenAdminDashboard,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          SvgPicture.asset(UiPaths.logo, width: 20, height: 20),
          const SizedBox(width: 8),
          const Text('작가 도구', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.ivory)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF3A3A2A), borderRadius: BorderRadius.circular(999)),
            child: Text(email, style: const TextStyle(fontSize: 10, color: AdminColors.gold)),
          ),
          const Spacer(),
          const Text('작가 닉네임', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
          const SizedBox(width: 6),
          SizedBox(
            width: 140,
            child: TextField(
              controller: nicknameController,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: AdminColors.ivory),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AdminColors.panel2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AdminColors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (isAdmin) ...[
            InkWell(
              onTap: onOpenAdminDashboard,
              child: const Text('관리자 페이지로', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
            ),
            const SizedBox(width: 14),
          ],
          InkWell(
            onTap: () => openExternalLink(ExternalLinks.readerAppUrl),
            child: const Text('독자로 보기', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
          ),
          const SizedBox(width: 14),
          InkWell(
            onTap: onSignOut,
            child: const Text('로그아웃', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
          ),
        ],
      ),
    );
  }
}

class _PackBar extends StatelessWidget {
  final List<AdminStoryPack> packs;
  final String? activePackId;
  final ValueChanged<String> onPackChanged;
  final VoidCallback onNewPack;
  final VoidCallback? onOpenSettings;

  const _PackBar({
    required this.packs,
    required this.activePackId,
    required this.onPackChanged,
    required this.onNewPack,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF131315),
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          const Text('스토리팩', style: TextStyle(fontSize: 11, color: AdminColors.muted)),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: activePackId,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AdminColors.panel2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AdminColors.border),
                ),
              ),
              dropdownColor: AdminColors.panel2,
              style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
              items: packs
                  .map((p) => DropdownMenuItem<String>(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (id) {
                if (id != null) onPackChanged(id);
              },
            ),
          ),
          OutlinedButton(
            onPressed: onNewPack,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.gold,
              side: const BorderSide(color: AdminColors.border, style: BorderStyle.solid),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('+ 새 스토리팩', style: TextStyle(fontSize: 12)),
          ),
          OutlinedButton(
            onPressed: onOpenSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.ivory,
              side: const BorderSide(color: AdminColors.border, style: BorderStyle.solid),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('팩 설정', style: TextStyle(fontSize: 12)),
          ),
          const Text(
            '한 계정으로 여러 스토리팩을 만들 수 있어요. 아래 노드/공지사항은 선택된 스토리팩 기준이에요.',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
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
      decoration: const BoxDecoration(
        color: AdminColors.panel,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          _NavTab(label: '스토리 노드', selected: active == _AdminTab.story, onTap: () => onSelected(_AdminTab.story)),
          _NavTab(label: '이미지 라이브러리', selected: active == _AdminTab.images, onTap: () => onSelected(_AdminTab.images)),
          _NavTab(label: '공지사항', selected: active == _AdminTab.notices, onTap: () => onSelected(_AdminTab.notices)),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? AdminColors.gold : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, color: selected ? AdminColors.gold : AdminColors.muted),
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
      title: const Text('새 스토리팩', style: TextStyle(color: AdminColors.ivory)),
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
                style: const TextStyle(color: AdminColors.ivory),
                decoration: InputDecoration(
                  hintText: '스토리팩 이름을 입력하세요.',
                  hintStyle: const TextStyle(color: AdminColors.muted),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AdminColors.border)),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AdminColors.gold)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('타입', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TypeOption(
                      label: '인터랙티브',
                      selected: _type == StoryPackType.interactive,
                      onTap: () => setState(() => _type = StoryPackType.interactive),
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
              const Text(
                '만든 뒤에는 바꿀 수 없어요 — 노드/챕터 구조가 서로 달라요.',
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
              const SizedBox(height: 6),
              const Text(
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
          child: const Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: _titleController.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (_titleController.text.trim(), _type)),
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

  const _TypeOption({required this.label, required this.selected, required this.onTap});

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
          border: Border.all(color: selected ? AdminColors.gold : AdminColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, color: selected ? AdminColors.gold : AdminColors.ivory)),
      ),
    );
  }
}
