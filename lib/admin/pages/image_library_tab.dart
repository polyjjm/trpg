import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/admin_image_repository.dart';
import '../models/admin_image.dart';
import '../models/admin_image_category.dart';
import '../widgets/admin_theme.dart';
import '../widgets/category_badge.dart';
import '../widgets/category_picker_dialog.dart';

/// "이미지 라이브러리" 탭 — 업로드(→ Firebase Storage) + 카테고리 필터 칩 +
/// 그리드 목록. 라이브러리는 팩/작가 구분 없이 전체가 공유한다
/// (FIRESTORE_SCHEMA.md) — 카테고리(배경/선택지/기타)는 그 공유 목록을
/// 좁혀 보기 위한 고정 분류일 뿐, 팩별 데이터가 아니다.
class ImageLibraryTab extends StatefulWidget {
  final AdminImageRepository repository;

  const ImageLibraryTab({super.key, required this.repository});

  @override
  State<ImageLibraryTab> createState() => _ImageLibraryTabState();
}

class _ImageLibraryTabState extends State<ImageLibraryTab> {
  bool _isUploading = false;

  /// null이면 "전체".
  AdminImageCategory? _filter;

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    // 한 번에 고른 파일 전부에 같은 분류를 적용한다 — 파일마다 따로 고르게
    // 하면 여러 장 업로드가 번거로워진다. 취소하면(다이얼로그 밖 탭 포함)
    // 업로드 자체를 하지 않는다 — "건너뛰기"는 기본값(기타)을 그대로 두고
    // "업로드"를 누르는 것이지, 다이얼로그를 닫는 게 아니다.
    final category = await showDialog<AdminImageCategory>(
      context: context,
      builder: (_) => const CategoryPickerDialog(
        initial: AdminImageCategory.other,
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
        await widget.repository.uploadImage(
          bytes: bytes,
          fileName: file.name,
          category: category,
        );
      } catch (e) {
        debugPrint('이미지 업로드 실패: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isUploading = false);
  }

  Future<void> _handleChangeCategory(AdminImage image) async {
    final category = await showDialog<AdminImageCategory>(
      context: context,
      builder: (_) => CategoryPickerDialog(
        initial: image.category,
        title: '카테고리 변경',
        confirmLabel: '변경',
      ),
    );
    if (category == null || category == image.category) return;
    await widget.repository.updateCategory(image.id, category);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이미지 라이브러리',
            style: TextStyle(
              fontSize: 16,
              color: AdminColors.ivory,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '여기에 업로드한 이미지를 노드 배경이나 선택지 전용 이미지로 고를 수 있어요.',
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
                  _isUploading ? '업로드 중...' : '클릭해서 이미지 업로드 (여러 장 선택 가능)',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          StreamBuilder<List<AdminImage>>(
            stream: widget.repository.watchImages(),
            builder: (context, snapshot) {
              final images = snapshot.data ?? const <AdminImage>[];

              final counts = <AdminImageCategory, int>{
                for (final category in AdminImageCategory.values)
                  category: images.where((i) => i.category == category).length,
              };

              final filter = _filter;
              final filtered = filter == null
                  ? images
                  : images.where((i) => i.category == filter).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: '전체',
                        count: images.length,
                        selected: filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final category in AdminImageCategory.values)
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
                      images.isEmpty ? '업로드된 이미지가 없어요.' : '이 카테고리에는 이미지가 없어요.',
                      style: TextStyle(fontSize: 13, color: AdminColors.muted),
                    )
                  else
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final image in filtered)
                          _ImageCard(
                            image: image,
                            onDelete: () => widget.repository.deleteImage(image),
                            onChangeCategory: () => _handleChangeCategory(image),
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

class _ImageCard extends StatelessWidget {
  final AdminImage image;
  final VoidCallback onDelete;
  final VoidCallback onChangeCategory;

  const _ImageCard({
    required this.image,
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
              SizedBox(
                height: 90,
                width: double.infinity,
                child: Image.network(
                  image.url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      ColoredBox(color: AdminColors.panel2),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: CategoryBadge(category: image.category),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              image.name,
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
                      border: Border(top: BorderSide(color: AdminColors.border)),
                    ),
                    child: Text(
                      '카테고리 변경',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: AdminColors.muted),
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
                      border: Border(top: BorderSide(color: AdminColors.border)),
                    ),
                    child: Text(
                      '삭제',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: AdminColors.danger),
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
