import 'package:flutter/material.dart';

import '../data/global_notice_repository.dart';
import '../models/global_notice.dart';
import '../widgets/admin_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/labeled_field.dart';

/// "공지사항 관리" — notices 컬렉션(앱 전체 공지, 팩과 무관)을 여기서
/// 만들고 고친다. GenreManagementSection/PointPackageManagementSection과
/// 같은 급의 설정 섹션이다. writerNotices(스토리팩별 작가 공지, "작가
/// 도구"의 NoticesTab)와는 완전히 다른 기능 — 헷갈리지 않게 사이드바
/// 라벨도 "공지사항 관리"로 명확히 구분해 둔다.
class GlobalNoticeManagementSection extends StatefulWidget {
  final AdminGlobalNoticeRepository repository;

  /// 새 공지를 쓴 admin의 uid — notices.authorId에 그대로 기록된다(감사
  /// 목적, 독자에게는 안 보인다).
  final String authorUid;

  const GlobalNoticeManagementSection({
    super.key,
    required this.repository,
    required this.authorUid,
  });

  @override
  State<GlobalNoticeManagementSection> createState() => _GlobalNoticeManagementSectionState();
}

class _GlobalNoticeManagementSectionState extends State<GlobalNoticeManagementSection> {
  late final Stream<List<AdminGlobalNotice>> _noticesStream = widget.repository.watchAllNotices();

  Future<void> _openCreateDialog() async {
    final result = await showDialog<_NoticeFormResult>(
      context: context,
      builder: (_) => const _NoticeFormDialog(existing: null),
    );
    if (result == null) return;

    await widget.repository.createNotice(
      title: result.title,
      body: result.body,
      authorId: widget.authorUid,
    );
  }

  Future<void> _openEditDialog(AdminGlobalNotice notice) async {
    final result = await showDialog<_NoticeFormResult>(
      context: context,
      builder: (_) => _NoticeFormDialog(existing: notice),
    );
    if (result == null) return;

    await widget.repository.updateNotice(
      notice.id,
      title: result.title,
      body: result.body,
      active: result.active,
    );
  }

  Future<void> _toggleActive(AdminGlobalNotice notice) async {
    await widget.repository.updateNotice(
      notice.id,
      title: notice.title,
      body: notice.body,
      active: !notice.active,
    );
  }

  Future<void> _delete(AdminGlobalNotice notice) async {
    final confirmed = await showConfirmDialog(context, '"${notice.title}" 공지를 삭제할까요?');
    if (!confirmed) return;
    await widget.repository.deleteNotice(notice.id);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '공지사항 관리',
                    style: TextStyle(fontSize: 16, color: AdminColors.ivory, fontWeight: FontWeight.w700),
                  ),
                ),
                ElevatedButton(
                  onPressed: _openCreateDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('+ 새 공지', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '여기서 올린 공지가 앱 하단 "공지사항" 탭에 최신순으로 나타나요. '
              '비활성으로 바꾸면 목록에서 감추기만 하고 지우지는 않아요 — 나중에 다시 켤 수 있어요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<AdminGlobalNotice>>(
              stream: _noticesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText(
                    '공지사항 목록을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(fontSize: 12, color: AdminColors.danger),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                }

                final notices = snapshot.data ?? const <AdminGlobalNotice>[];
                if (notices.isEmpty) {
                  return Text(
                    '등록된 공지사항이 없어요. "+ 새 공지"로 첫 공지를 만들어보세요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                return Column(
                  children: [
                    for (final notice in notices)
                      _NoticeRow(
                        notice: notice,
                        onEdit: () => _openEditDialog(notice),
                        onToggleActive: () => _toggleActive(notice),
                        onDelete: () => _delete(notice),
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

class _NoticeRow extends StatelessWidget {
  final AdminGlobalNotice notice;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _NoticeRow({
    required this.notice,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !notice.active;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AdminColors.panel,
          border: Border.all(color: AdminColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notice.title.isEmpty ? '(제목 없음)' : notice.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AdminColors.ivory),
                        ),
                      ),
                      if (dimmed) ...[
                        const SizedBox(width: 6),
                        const _Chip(text: '비활성'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(notice.createdAt),
                    style: TextStyle(fontSize: 11, color: AdminColors.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notice.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AdminColors.ivory, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: notice.active,
              onChanged: (_) => onToggleActive(),
              activeThumbColor: AdminColors.gold,
            ),
            InkWell(
              onTap: onEdit,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('편집', style: TextStyle(fontSize: 12, color: AdminColors.accent)),
              ),
            ),
            InkWell(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('삭제', style: TextStyle(fontSize: 12, color: AdminColors.danger)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '(작성 중)';
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _Chip extends StatelessWidget {
  final String text;

  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AdminColors.statusDraftBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 9, color: AdminColors.statusDraftText)),
    );
  }
}

class _NoticeFormResult {
  final String title;
  final String body;
  final bool active;

  const _NoticeFormResult({required this.title, required this.body, required this.active});
}

/// 새 공지 만들기/기존 공지 편집을 같은 폼으로 처리한다.
class _NoticeFormDialog extends StatefulWidget {
  final AdminGlobalNotice? existing;

  const _NoticeFormDialog({required this.existing});

  @override
  State<_NoticeFormDialog> createState() => _NoticeFormDialogState();
}

class _NoticeFormDialogState extends State<_NoticeFormDialog> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _bodyController =
      TextEditingController(text: widget.existing?.body ?? '');
  late bool _active = widget.existing?.active ?? true;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onChanged);
    _bodyController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty && _bodyController.text.trim().isNotEmpty;

  void _submit() {
    Navigator.pop(
      context,
      _NoticeFormResult(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(isEditing ? '공지 편집' : '새 공지', style: TextStyle(color: AdminColors.ivory)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                label: '제목',
                child: TextField(
                  controller: _titleController,
                  autofocus: true,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: 서버 점검 안내'),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: '내용',
                child: TextField(
                  controller: _bodyController,
                  maxLines: 6,
                  minLines: 4,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '내용을 적어주세요.'),
                ),
              ),
              if (isEditing) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('활성', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
                    const Spacer(),
                    Switch(
                      value: _active,
                      onChanged: (value) => setState(() => _active = value),
                      activeThumbColor: AdminColors.gold,
                    ),
                  ],
                ),
              ],
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
          onPressed: _canSubmit ? _submit : null,
          child: Text(isEditing ? '저장' : '만들기', style: const TextStyle(color: AdminColors.gold)),
        ),
      ],
    );
  }
}
