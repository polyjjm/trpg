import 'package:flutter/material.dart';

import '../../core/auth/google_auth_service.dart';
import '../data/admin_notice_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/pending_node_ref.dart';
import '../widgets/admin_theme.dart';
import 'admin_gate_page.dart';
import 'approvals_tab.dart';
import 'image_library_tab.dart';
import 'notices_tab.dart';
import 'story_tab_view.dart';

enum _AdminTab { story, images, notices, approvals }

/// 로그인 + 화이트리스트 통과 후 보이는 편집기 본체.
/// topbar(닉네임) → pack-bar(스토리팩 전환/생성) → navtabs → 탭별 본문
/// 순서로, story_editor_prototype.html의 레이아웃을 그대로 따른다.
class AdminShellPage extends StatefulWidget {
  final GoogleAuthService authService;
  final String email;

  const AdminShellPage({super.key, required this.authService, required this.email});

  @override
  State<AdminShellPage> createState() => _AdminShellPageState();
}

class _AdminShellPageState extends State<AdminShellPage> {
  final AdminStoryRepository _storyRepository = AdminStoryRepository();
  final AdminImageRepository _imageRepository = AdminImageRepository();
  final AdminNoticeRepository _noticeRepository = AdminNoticeRepository();

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
    final title = await _promptText(
      context,
      title: '새 스토리팩',
      hint: '스토리팩 이름을 입력하세요.',
    );
    if (title == null || title.trim().isEmpty) return;

    final pack = await _storyRepository.createPack(title.trim());
    if (!mounted) return;
    setState(() => _activePackId = pack.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      body: StreamBuilder<List<AdminStoryPack>>(
        stream: _storyRepository.watchPacks(),
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
  final ValueChanged<_AdminTab> onSelected;

  const _NavTabs({required this.active, required this.repository, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PendingNodeRef>>(
      stream: repository.watchPendingNodes(),
      builder: (context, snapshot) {
        final pendingCount = snapshot.data?.length ?? 0;

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
              _NavTab(
                label: pendingCount > 0 ? '승인 대기함 · $pendingCount' : '승인 대기함',
                selected: active == _AdminTab.approvals,
                onTap: () => onSelected(_AdminTab.approvals),
              ),
            ],
          ),
        );
      },
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

Future<String?> _promptText(BuildContext context, {required String title, required String hint}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(title, style: const TextStyle(color: AdminColors.ivory)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: AdminColors.ivory),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AdminColors.muted),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AdminColors.border)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AdminColors.gold)),
        ),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('만들기', style: TextStyle(color: AdminColors.gold)),
        ),
      ],
    ),
  );
}
