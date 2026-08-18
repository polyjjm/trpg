import 'package:flutter/material.dart';

import '../data/genre_repository.dart';
import '../models/genre.dart';
import '../widgets/admin_theme.dart';
import '../widgets/labeled_field.dart';

/// "장르 관리" — genres 컬렉션을 콘솔 대신 여기서 만들고 고친다. 삭제는 없다
/// — 이미 이 장르 slug를 쓰는 스토리팩이 있을 수 있어서, 안 쓰게 하려면
/// 비활성으로 내리는 것만 지원한다(GenreRepository.updateGenre 참고).
class GenreManagementSection extends StatefulWidget {
  final GenreRepository repository;

  const GenreManagementSection({super.key, required this.repository});

  @override
  State<GenreManagementSection> createState() => _GenreManagementSectionState();
}

class _GenreManagementSectionState extends State<GenreManagementSection> {
  late final Stream<List<Genre>> _genresStream = widget.repository
      .watchAllGenres();

  Future<void> _openCreateDialog() async {
    final result = await showDialog<_GenreFormResult>(
      context: context,
      builder: (_) => const _GenreFormDialog(existing: null),
    );
    if (result == null) return;

    await widget.repository.createGenre(
      name: result.name,
      slug: result.slug,
      sortOrder: result.sortOrder,
      active: result.active,
    );
  }

  Future<void> _openEditDialog(Genre genre) async {
    final result = await showDialog<_GenreFormResult>(
      context: context,
      builder: (_) => _GenreFormDialog(existing: genre),
    );
    if (result == null) return;

    await widget.repository.updateGenre(
      genre.id,
      name: result.name,
      slug: result.slug,
      sortOrder: result.sortOrder,
      active: result.active,
    );
  }

  Future<void> _toggleActive(Genre genre) async {
    await widget.repository.updateGenre(
      genre.id,
      name: genre.name,
      slug: genre.slug,
      sortOrder: genre.sortOrder,
      active: !genre.active,
    );
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '장르 관리',
                    style: TextStyle(
                      fontSize: 16,
                      color: AdminColors.ivory,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _openCreateDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '+ 새 장르',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '여기서 만들고 고친 장르가 새 스토리팩 만들기 화면의 장르 선택지로 바로 나타나요. '
              '삭제는 지원하지 않아요 — 안 쓰려면 비활성으로 내려주세요(이미 이 장르를 쓰는 작품이 있을 수 있어요).',
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Genre>>(
              stream: _genresStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText(
                    '장르 목록을 불러오지 못했어요: ${snapshot.error}',
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

                final genres = snapshot.data ?? const <Genre>[];
                if (genres.isEmpty) {
                  return Text(
                    '등록된 장르가 없어요. "+ 새 장르"로 첫 장르를 만들어보세요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                return Column(
                  children: [
                    for (final genre in genres)
                      _GenreRow(
                        genre: genre,
                        onEdit: () => _openEditDialog(genre),
                        onToggleActive: () => _toggleActive(genre),
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

class _GenreRow extends StatelessWidget {
  final Genre genre;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _GenreRow({
    required this.genre,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !genre.active;

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
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        genre.name.isEmpty ? '(이름 없음)' : genre.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AdminColors.ivory,
                        ),
                      ),
                      if (dimmed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AdminColors.statusDraftBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            '비활성',
                            style: TextStyle(
                              fontSize: 9,
                              color: AdminColors.statusDraftText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'slug: ${genre.slug} · 정렬: ${genre.sortOrder}',
                    style: TextStyle(fontSize: 11, color: AdminColors.muted),
                  ),
                ],
              ),
            ),
            Switch(
              value: genre.active,
              onChanged: (_) => onToggleActive(),
              activeThumbColor: AdminColors.gold,
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onEdit,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '편집',
                  style: TextStyle(fontSize: 12, color: AdminColors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreFormResult {
  final String name;
  final String slug;
  final int sortOrder;
  final bool active;

  const _GenreFormResult({
    required this.name,
    required this.slug,
    required this.sortOrder,
    required this.active,
  });
}

/// 새 장르 만들기/기존 장르 편집을 같은 폼으로 처리한다. [existing]이 null이면
/// 생성, 아니면 그 값으로 필드를 채운 편집 모드다.
class _GenreFormDialog extends StatefulWidget {
  final Genre? existing;

  const _GenreFormDialog({required this.existing});

  @override
  State<_GenreFormDialog> createState() => _GenreFormDialogState();
}

class _GenreFormDialogState extends State<_GenreFormDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _slugController = TextEditingController(
    text: widget.existing?.slug ?? '',
  );
  late final TextEditingController _sortOrderController = TextEditingController(
    text: '${widget.existing?.sortOrder ?? 0}',
  );
  late bool _active = widget.existing?.active ?? true;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onChanged);
    _slugController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _slugController.text.trim().isNotEmpty;

  void _submit() {
    final sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 0;
    Navigator.pop(
      context,
      _GenreFormResult(
        name: _nameController.text.trim(),
        slug: _slugController.text.trim(),
        sortOrder: sortOrder,
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(
        isEditing ? '장르 편집' : '새 장르',
        style: TextStyle(color: AdminColors.ivory),
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                label: '이름',
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: 공포'),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'slug (storyPack에 저장되는 값, 영문 권장)',
                child: TextField(
                  controller: _slugController,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: horror'),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: '정렬 순서 (작을수록 먼저 표시)',
                child: TextField(
                  controller: _sortOrderController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: 1'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '활성',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                  const Spacer(),
                  Switch(
                    value: _active,
                    onChanged: (value) => setState(() => _active = value),
                    activeThumbColor: AdminColors.gold,
                  ),
                ],
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
          onPressed: _canSubmit ? _submit : null,
          child: Text(
            isEditing ? '저장' : '만들기',
            style: const TextStyle(color: AdminColors.gold),
          ),
        ),
      ],
    );
  }
}
