import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/audio/audio_service.dart';
import '../data/admin_bgm_repository.dart';
import '../models/admin_bgm.dart';
import '../widgets/admin_theme.dart';
import '../widgets/library_search_field.dart';

/// "배경음악 라이브러리" 탭 — SfxLibraryTab과 같은 구조(업로드 → Firebase
/// Storage, 그리드 목록, 미리듣기 재생 버튼)에서 카테고리 필터만 뺐다(BGM은
/// 트랙 수가 적어 분류가 필요 없다는 판단, admin_bgm.dart 참고). 라이브러리는
/// 팩/작가 구분 없이 전체가 공유한다 — images/sfxLibrary와 같은 이유다.
class BgmLibraryTab extends StatefulWidget {
  final AdminBgmRepository repository;
  final String? currentUserId;

  const BgmLibraryTab({
    super.key,
    required this.repository,
    required this.currentUserId,
  });

  @override
  State<BgmLibraryTab> createState() => _BgmLibraryTabState();
}

class _BgmLibraryTabState extends State<BgmLibraryTab> {
  bool _isUploading = false;

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

    setState(() => _isUploading = true);

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      try {
        await widget.repository.uploadBgm(
          bytes: bytes,
          fileName: file.name,
          uploadedBy: widget.currentUserId,
        );
      } catch (e) {
        debugPrint('BGM 업로드 실패: $e');
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
            '배경음악 라이브러리',
            style: TextStyle(
              fontSize: 16,
              color: AdminColors.ivory,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '여기에 업로드한 배경음악을 노드의 연출 효과("배경음악")와 팩 설정의 "기본 배경음악"에서 고를 수 있어요.',
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
                  _isUploading ? '업로드 중...' : '클릭해서 배경음악 업로드 (여러 개 선택 가능)',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          LibrarySearchField(
            controller: _searchController,
            hintText: '배경음악 이름 검색',
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<AdminBgm>>(
            stream: widget.repository.watchBgmLibrary(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SelectableText(
                  '배경음악 목록을 불러오지 못했어요: ${snapshot.error}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.danger,
                  ),
                );
              }

              final bgmItems = snapshot.data ?? const <AdminBgm>[];
              final needle = _searchQuery.trim().toLowerCase();
              final filtered = bgmItems
                  .where(
                    (b) =>
                        needle.isEmpty || b.name.toLowerCase().contains(needle),
                  )
                  .toList();

              if (filtered.isEmpty) {
                return Text(
                  bgmItems.isEmpty ? '업로드된 배경음악이 없어요.' : '검색 결과가 없습니다.',
                  style: TextStyle(fontSize: 13, color: AdminColors.muted),
                );
              }

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final bgm in filtered)
                    _BgmCard(
                      bgm: bgm,
                      onDelete: () => widget.repository.deleteBgm(bgm),
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

/// SfxLibraryTab의 _SfxCard와 같은 카드 골격 — 카테고리 배지만 없다.
class _BgmCard extends StatelessWidget {
  final AdminBgm bgm;
  final VoidCallback onDelete;

  const _BgmCard({required this.bgm, required this.onDelete});

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
          InkWell(
            onTap: () => AudioService.instance.playSfx(bgm.storageUrl),
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
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              bgm.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AdminColors.muted),
            ),
          ),
          InkWell(
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
        ],
      ),
    );
  }
}
