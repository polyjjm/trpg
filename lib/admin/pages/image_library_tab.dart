import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/admin_image_repository.dart';
import '../models/admin_image.dart';
import '../widgets/admin_theme.dart';

/// "이미지 라이브러리" 탭 — 업로드(→ Firebase Storage) + 그리드 목록.
class ImageLibraryTab extends StatefulWidget {
  final AdminImageRepository repository;

  const ImageLibraryTab({super.key, required this.repository});

  @override
  State<ImageLibraryTab> createState() => _ImageLibraryTabState();
}

class _ImageLibraryTabState extends State<ImageLibraryTab> {
  bool _isUploading = false;

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    setState(() => _isUploading = true);

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      try {
        await widget.repository.uploadImage(bytes: bytes, fileName: file.name);
      } catch (e) {
        debugPrint('이미지 업로드 실패: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isUploading = false);
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
          const SizedBox(height: 16),
          StreamBuilder<List<AdminImage>>(
            stream: widget.repository.watchImages(),
            builder: (context, snapshot) {
              final images = snapshot.data ?? const <AdminImage>[];
              if (images.isEmpty) {
                return Text(
                  '업로드된 이미지가 없어요.',
                  style: TextStyle(fontSize: 13, color: AdminColors.muted),
                );
              }
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final image in images)
                    _ImageCard(
                      image: image,
                      onDelete: () => widget.repository.deleteImage(image),
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

class _ImageCard extends StatelessWidget {
  final AdminImage image;
  final VoidCallback onDelete;

  const _ImageCard({required this.image, required this.onDelete});

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
          SizedBox(
            height: 90,
            child: Image.network(
              image.url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  ColoredBox(color: AdminColors.panel2),
            ),
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
          InkWell(
            onTap: onDelete,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AdminColors.border)),
              ),
              child: const Text(
                '삭제',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AdminColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
