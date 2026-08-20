import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/audio/audio_service.dart';
import '../data/admin_sfx_repository.dart';
import '../models/admin_sfx.dart';
import '../models/admin_sfx_category.dart';
import '../widgets/admin_theme.dart';
import '../widgets/library_search_field.dart';
import '../widgets/sfx_category_badge.dart';
import '../widgets/sfx_category_picker_dialog.dart';

/// "효과음 라이브러리" 탭 — ImageLibraryTab과 같은 구조(업로드 → Firebase
/// Storage, 카테고리 필터 칩, 그리드 목록)에 미리듣기 재생 버튼만 더한다.
/// 라이브러리는 팩/작가 구분 없이 전체가 공유한다 — images와 같은 이유다.
class SfxLibraryTab extends StatefulWidget {
  final AdminSfxRepository repository;
  final String? currentUserId;

  const SfxLibraryTab({
    super.key,
    required this.repository,
    required this.currentUserId,
  });

  @override
  State<SfxLibraryTab> createState() => _SfxLibraryTabState();
}

class _SfxLibraryTabState extends State<SfxLibraryTab> {
  bool _isUploading = false;

  /// null이면 "전체".
  AdminSfxCategory? _filter;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    // 한 번에 고른 파일 전부에 같은 분류를 적용한다 — ImageLibraryTab과 같은
    // 이유(여러 개 업로드가 매번 고르게 하면 번거로워진다).
    final category = await showDialog<AdminSfxCategory>(
      context: context,
      builder: (_) => const SfxCategoryPickerDialog(
        initial: AdminSfxCategory.other,
        title: '카테고리 선택',
        confirmLabel: '업로드',
      ),
    );
    if (category == null || !mounted) return;

    setState(() => _isUploading = true);

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      try {
        await widget.repository.uploadSfx(
          bytes: bytes,
          fileName: file.name,
          category: category,
          uploadedBy: widget.currentUserId,
        );
      } catch (e) {
        debugPrint('효과음 업로드 실패: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isUploading = false);
  }

  Future<void> _handleChangeCategory(AdminSfx sfx) async {
    final category = await showDialog<AdminSfxCategory>(
      context: context,
      builder: (_) => SfxCategoryPickerDialog(
        initial: sfx.category,
        title: '카테고리 변경',
        confirmLabel: '변경',
      ),
    );
    if (category == null || category == sfx.category) return;
    await widget.repository.updateCategory(sfx.id, category);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '효과음 라이브러리',
            style: TextStyle(
              fontSize: 16,
              color: AdminColors.ivory,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '여기에 업로드한 효과음을 노드의 연출 효과("효과음")에서 고를 수 있어요.',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _isUploading ? null : _handleUpload,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: AdminColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _isUploading ? '업로드 중...' : '클릭해서 효과음 업로드 (여러 개 선택 가능)',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          LibrarySearchField(
            controller: _searchController,
            hintText: '효과음 이름 검색',
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<AdminSfx>>(
            stream: widget.repository.watchSfxLibrary(),
            builder: (context, snapshot) {
              final sfxItems = snapshot.data ?? const <AdminSfx>[];

              final counts = <AdminSfxCategory, int>{
                for (final category in AdminSfxCategory.values)
                  category: sfxItems
                      .where((s) => s.category == category)
                      .length,
              };

              final filter = _filter;
              final needle = _searchQuery.trim().toLowerCase();
              final filtered = sfxItems
                  .where((s) => filter == null || s.category == filter)
                  .where(
                    (s) =>
                        needle.isEmpty || s.name.toLowerCase().contains(needle),
                  )
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: '전체',
                        count: sfxItems.length,
                        selected: filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final category in AdminSfxCategory.values)
                        _FilterChip(
                          label: category.label,
                          count: counts[category] ?? 0,
                          selected: filter == category,
                          onTap: () => setState(() => _filter = category),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    Text(
                      sfxItems.isEmpty
                          ? '업로드된 효과음이 없어요.'
                          : needle.isNotEmpty
                          ? '검색 결과가 없습니다.'
                          : '이 카테고리에는 효과음이 없어요.',
                      style: TextStyle(fontSize: 13, color: AdminColors.muted),
                    )
                  else
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final sfx in filtered)
                          _SfxCard(
                            sfx: sfx,
                            onDelete: () => widget.repository.deleteSfx(sfx),
                            onChangeCategory: () => _handleChangeCategory(sfx),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : AdminColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

/// ImageLibraryTab의 _ImageCard와 같은 카드 골격이지만, 효과음에는 썸네일이
/// 없다 — 대신 위쪽에 재생 아이콘 자리를 두고, 누르면 AudioService로 바로
/// 미리듣기를 재생한다(작가가 노드에 넣기 전에 소리를 확인할 수 있게).
class _SfxCard extends StatelessWidget {
  final AdminSfx sfx;
  final VoidCallback onDelete;
  final VoidCallback onChangeCategory;

  const _SfxCard({
    required this.sfx,
    required this.onDelete,
    required this.onChangeCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              InkWell(
                onTap: () => AudioService.instance.playSfx(sfx.storageUrl),
                child: Container(
                  height: 66,
                  width: double.infinity,
                  color: AdminColors.panel2,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 32,
                    color: AdminColors.gold,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: SfxCategoryBadge(category: sfx.category),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              sfx.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AdminColors.muted),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onChangeCategory,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AdminColors.border),
                      ),
                    ),
                    child: Text(
                      '카테고리 변경',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AdminColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 26, color: AdminColors.border),
              Expanded(
                child: InkWell(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AdminColors.border),
                      ),
                    ),
                    child: Text(
                      '삭제',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AdminColors.danger,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
