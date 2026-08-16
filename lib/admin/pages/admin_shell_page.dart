import 'package:flutter/material.dart';

import '../../core/auth/google_auth_service.dart';
import '../../core/constants/external_links.dart';
import '../../core/platform/open_external_link.dart';
import '../data/admin_notice_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/author_application_repository.dart';
import '../data/genre_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/author_application.dart';
import '../models/genre.dart';
import '../models/pending_node_ref.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';
import 'admin_gate_page.dart';
import 'approvals_tab.dart';
import 'author_applications_tab.dart';
import 'image_library_tab.dart';
import 'notices_tab.dart';
import 'story_tab_view.dart';

enum _AdminTab { story, images, notices, approvals, authorApplications }

/// 로그인 + 역할 확인(author/admin) 통과 후 보이는 편집기 본체.
/// topbar(닉네임) → pack-bar(스토리팩 전환/생성) → navtabs → 탭별 본문
/// 순서로, story_editor_prototype.html의 레이아웃을 그대로 따른다.
class AdminShellPage extends StatefulWidget {
  final GoogleAuthService authService;
  final String email;

  /// author는 콘텐츠 편집만, admin은 여기에 더해 "작가 신청" 검토 탭까지 본다.
  final bool isAdmin;

  const AdminShellPage({
    super.key,
    required this.authService,
    required this.email,
    required this.isAdmin,
  });

  @override
  State<AdminShellPage> createState() => _AdminShellPageState();
}

class _AdminShellPageState extends State<AdminShellPage> {
  final AdminStoryRepository _storyRepository = AdminStoryRepository();
  final AdminImageRepository _imageRepository = AdminImageRepository();
  final AdminNoticeRepository _noticeRepository = AdminNoticeRepository();
  final AuthorApplicationRepository _authorApplicationRepository = AuthorApplicationRepository();
  final GenreRepository _genreRepository = GenreRepository();

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

  Future<void> _handleNewPack() async {
    final authorId = widget.authService.userId;
    if (authorId == null) return;

    final result = await showDialog<(String, StoryPackType, List<String>)>(
      context: context,
      builder: (_) => _NewPackDialog(genreRepository: _genreRepository),
    );
    if (result == null) return;

    final (title, type, genres) = result;
    final pack = await _storyRepository.createPack(
      title: title,
      authorId: authorId,
      type: type,
      genres: genres,
    );
    if (!mounted) return;
    setState(() => _activePackId = pack.id);
  }

  /// admin은 전체 스토리팩을, author는 자기 소유 스토리팩만 본다.
  Stream<List<AdminStoryPack>> get _packsStream {
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
                onSignOut: _handleSignOut,
              ),
              _PackBar(
                packs: packs,
                activePackId: activePackId,
                onPackChanged: (id) => setState(() => _activePackId = id),
                onNewPack: _handleNewPack,
              ),
              _NavTabs(
                active: _activeTab,
                repository: _storyRepository,
                isAdmin: widget.isAdmin,
                authorApplicationRepository: widget.isAdmin ? _authorApplicationRepository : null,
                onSelected: (tab) => setState(() => _activeTab = tab),
              ),
              Expanded(child: _buildBody(activePackId, packs)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(String? activePackId, List<AdminStoryPack> packs) {
    if (activePackId == null) {
      return const Center(
        child: Text('먼저 "+ 새 스토리팩"으로 스토리팩을 만들어주세요.', style: TextStyle(color: AdminColors.muted, fontSize: 13)),
      );
    }

    switch (_activeTab) {
      case _AdminTab.story:
        return StoryTabView(
          key: ValueKey('story_$activePackId'),
          packId: activePackId,
          repository: _storyRepository,
          imageRepository: _imageRepository,
        );
      case _AdminTab.images:
        return ImageLibraryTab(repository: _imageRepository);
      case _AdminTab.notices:
        return NoticesTab(
          key: ValueKey('notices_$activePackId'),
          packId: activePackId,
          repository: _noticeRepository,
        );
      case _AdminTab.approvals:
        return ApprovalsTab(
          repository: _storyRepository,
          packTitles: {for (final p in packs) p.id: p.title},
        );
      case _AdminTab.authorApplications:
        return AuthorApplicationsTab(
          repository: _authorApplicationRepository,
          reviewerUid: widget.authService.userId ?? '',
        );
    }
  }
}

class _TopBar extends StatelessWidget {
  final TextEditingController nicknameController;
  final String email;
  final VoidCallback onSignOut;

  const _TopBar({required this.nicknameController, required this.email, required this.onSignOut});

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
          const Text('작가 편집기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.ivory)),
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

  const _PackBar({
    required this.packs,
    required this.activePackId,
    required this.onPackChanged,
    required this.onNewPack,
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
  final AdminStoryRepository repository;

  /// author는 콘텐츠 승인 권한이 없어 "승인 대기함" 탭 자체를 못 본다.
  final bool isAdmin;

  /// null이면(author, admin이 아님) "작가 신청" 탭 자체를 렌더링하지 않는다.
  final AuthorApplicationRepository? authorApplicationRepository;
  final ValueChanged<_AdminTab> onSelected;

  const _NavTabs({
    required this.active,
    required this.repository,
    required this.isAdmin,
    required this.authorApplicationRepository,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final applicationRepository = authorApplicationRepository;

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
          if (isAdmin)
            StreamBuilder<List<PendingNodeRef>>(
              stream: repository.watchPendingNodes(),
              builder: (context, snapshot) {
                final pendingCount = snapshot.data?.length ?? 0;
                return _NavTab(
                  label: pendingCount > 0 ? '승인 대기함 · $pendingCount' : '승인 대기함',
                  selected: active == _AdminTab.approvals,
                  onTap: () => onSelected(_AdminTab.approvals),
                );
              },
            ),
          if (applicationRepository != null)
            StreamBuilder<List<AuthorApplication>>(
              stream: applicationRepository.watchPendingApplications(),
              builder: (context, appSnapshot) {
                final applicationCount = appSnapshot.data?.length ?? 0;
                return _NavTab(
                  label: applicationCount > 0 ? '작가 신청 · $applicationCount' : '작가 신청',
                  selected: active == _AdminTab.authorApplications,
                  onTap: () => onSelected(_AdminTab.authorApplications),
                );
              },
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

/// "새 스토리팩" 다이얼로그 — 제목/타입/장르를 한 번에 받는다. 타입은 만든
/// 뒤에는 바꿀 수 없어서(인터랙티브/선형이 하위 구조부터 다르다) 여기서만
/// 고른다. 장르는 genres 컬렉션에서 실시간으로 불러온 활성 장르 중 다중 선택.
class _NewPackDialog extends StatefulWidget {
  final GenreRepository genreRepository;

  const _NewPackDialog({required this.genreRepository});

  @override
  State<_NewPackDialog> createState() => _NewPackDialogState();
}

class _NewPackDialogState extends State<_NewPackDialog> {
  final TextEditingController _titleController = TextEditingController();
  StoryPackType _type = StoryPackType.interactive;
  final Set<String> _selectedGenreSlugs = {};

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

  void _toggleGenre(String slug) {
    setState(() {
      if (!_selectedGenreSlugs.remove(slug)) {
        _selectedGenreSlugs.add(slug);
      }
    });
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
              const SizedBox(height: 20),
              const Text('장르 (선택)', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
              const SizedBox(height: 8),
              StreamBuilder<List<Genre>>(
                stream: widget.genreRepository.watchActiveGenres(),
                builder: (context, snapshot) {
                  final genres = snapshot.data ?? const <Genre>[];
                  if (genres.isEmpty) {
                    return const Text('등록된 장르가 없어요.', style: TextStyle(fontSize: 12, color: AdminColors.muted));
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final genre in genres)
                        _GenreChip(
                          label: genre.name,
                          selected: _selectedGenreSlugs.contains(genre.slug),
                          onTap: () => _toggleGenre(genre.slug),
                        ),
                    ],
                  );
                },
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
              : () => Navigator.pop(context, (_titleController.text.trim(), _type, _selectedGenreSlugs.toList())),
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

class _GenreChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenreChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.statusPendingBg : AdminColors.panel2,
          border: Border.all(color: selected ? AdminColors.statusPendingText : AdminColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: selected ? AdminColors.statusPendingText : AdminColors.muted),
        ),
      ),
    );
  }
}
