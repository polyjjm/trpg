import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/home_banner_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/home_banner.dart';
import '../widgets/admin_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/labeled_field.dart';

/// "홈 배너 관리" — homeBanners 컬렉션을 여기서 만들고 고치고 순서를
/// 바꾼다. GenreManagementSection과 같은 급의 "설정" 하위 섹션이지만, 삭제
/// 없이 비활성만 지원하는 장르와 달리 배너는 실제 삭제도 지원한다(다른
/// 문서를 참조당하는 자원이 아니라서). 이미지 전용 배너로 단순화되면서
/// 헤드라인/서브텍스트/배경색 입력 대신 ImageLibraryTab과 같은 업로드
/// 흐름(file_picker → Storage 업로드)을 쓴다.
class HomeBannerManagementSection extends StatefulWidget {
  final HomeBannerRepository repository;
  final Stream<List<AdminStoryPack>> packsStream;

  const HomeBannerManagementSection({
    super.key,
    required this.repository,
    required this.packsStream,
  });

  @override
  State<HomeBannerManagementSection> createState() => _HomeBannerManagementSectionState();
}

class _HomeBannerManagementSectionState extends State<HomeBannerManagementSection> {
  late final Stream<List<AdminHomeBanner>> _bannersStream = widget.repository.watchAllBanners();

  Future<void> _openCreateDialog(List<AdminStoryPack> packs, int nextSortOrder) async {
    final result = await showDialog<_BannerFormResult>(
      context: context,
      builder: (_) => _BannerFormDialog(existing: null, packs: packs),
    );
    if (result == null) return;

    final imageBytes = result.imageBytes;
    if (imageBytes == null) return; // 폼이 이미지 없이는 제출을 못 하게 막아 둔다.

    await widget.repository.createBanner(
      imageBytes: imageBytes,
      linkedPackId: result.linkedPackId,
      sortOrder: nextSortOrder,
      active: result.active,
      startAt: result.startAt,
      endAt: result.endAt,
    );
  }

  Future<void> _openEditDialog(AdminHomeBanner banner, List<AdminStoryPack> packs) async {
    final result = await showDialog<_BannerFormResult>(
      context: context,
      builder: (_) => _BannerFormDialog(existing: banner, packs: packs),
    );
    if (result == null) return;

    await widget.repository.updateBanner(
      banner.id,
      imageBytes: result.imageBytes,
      linkedPackId: result.linkedPackId,
      sortOrder: banner.sortOrder,
      active: result.active,
      startAt: result.startAt,
      endAt: result.endAt,
    );
  }

  Future<void> _delete(AdminHomeBanner banner) async {
    final confirmed = await showConfirmDialog(context, '이 배너를 삭제할까요?');
    if (!confirmed) return;
    await widget.repository.deleteBanner(banner);
  }

  Future<void> _reorder(List<AdminHomeBanner> banners, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = [...banners];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await widget.repository.reorder(reordered.map((b) => b.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminStoryPack>>(
      stream: widget.packsStream,
      builder: (context, packSnapshot) {
        final packs = packSnapshot.data ?? const <AdminStoryPack>[];
        final packTitles = {for (final p in packs) p.id: p.title};

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<List<AdminHomeBanner>>(
                  stream: _bannersStream,
                  builder: (context, snapshot) {
                    final banners = snapshot.data ?? const <AdminHomeBanner>[];
                    final nextSortOrder = banners.isEmpty
                        ? 0
                        : banners.map((b) => b.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            '홈 배너 관리',
                            style: TextStyle(fontSize: 16, color: AdminColors.ivory, fontWeight: FontWeight.w700),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _openCreateDialog(packs, nextSortOrder),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('+ 새 배너', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  '여기서 올린 이미지가 리더 홈 화면 상단의 히어로 배너로 순서대로 넘어가며 보여요(텍스트 없이 이미지 그대로). '
                  '드래그로 순서를 바꿀 수 있고, 기간을 정해두면 그 기간에만 노출돼요.',
                  style: TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<AdminHomeBanner>>(
                  stream: _bannersStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SelectableText(
                        '배너 목록을 불러오지 못했어요: ${snapshot.error}',
                        style: const TextStyle(fontSize: 12, color: AdminColors.danger),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                    }

                    final banners = snapshot.data ?? const <AdminHomeBanner>[];
                    if (banners.isEmpty) {
                      return Text(
                        '등록된 배너가 없어요. "+ 새 배너"로 첫 배너를 만들어보세요.',
                        style: TextStyle(fontSize: 13, color: AdminColors.muted),
                      );
                    }

                    return ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) => _reorder(banners, oldIndex, newIndex),
                      children: [
                        for (var i = 0; i < banners.length; i++)
                          _BannerRow(
                            key: ValueKey(banners[i].id),
                            index: i,
                            banner: banners[i],
                            linkedPackTitle: banners[i].linkedPackId != null
                                ? packTitles[banners[i].linkedPackId]
                                : null,
                            onEdit: () => _openEditDialog(banners[i], packs),
                            onDelete: () => _delete(banners[i]),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BannerRow extends StatelessWidget {
  final int index;
  final AdminHomeBanner banner;
  final String? linkedPackTitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BannerRow({
    required super.key,
    required this.index,
    required this.banner,
    required this.linkedPackTitle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !banner.active;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AdminColors.panel,
          border: Border.all(color: AdminColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_indicator_rounded, color: AdminColors.muted, size: 20),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 28,
                child: banner.imageUrl.isNotEmpty
                    ? Image.network(
                        banner.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(color: AdminColors.panel2),
                      )
                    : ColoredBox(color: AdminColors.panel2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          linkedPackTitle ?? '(연결된 팩 없음)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AdminColors.ivory),
                        ),
                      ),
                      if (dimmed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AdminColors.statusDraftBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('비활성', style: TextStyle(fontSize: 9, color: AdminColors.statusDraftText)),
                        ),
                      ],
                    ],
                  ),
                  if (banner.startAt != null || banner.endAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '기간: ${_formatDate(banner.startAt)} ~ ${_formatDate(banner.endAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ],
                ],
              ),
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
    if (date == null) return '(없음)';
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }
}

class _BannerFormResult {
  final Uint8List? imageBytes;
  final String? linkedPackId;
  final bool active;
  final DateTime? startAt;
  final DateTime? endAt;

  const _BannerFormResult({
    required this.imageBytes,
    required this.linkedPackId,
    required this.active,
    required this.startAt,
    required this.endAt,
  });
}

class _BannerFormDialog extends StatefulWidget {
  final AdminHomeBanner? existing;
  final List<AdminStoryPack> packs;

  const _BannerFormDialog({required this.existing, required this.packs});

  @override
  State<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends State<_BannerFormDialog> {
  Uint8List? _pickedImageBytes;
  late String? _linkedPackId = widget.existing?.linkedPackId;
  late bool _active = widget.existing?.active ?? true;
  late DateTime? _startAt = widget.existing?.startAt;
  late DateTime? _endAt = widget.existing?.endAt;

  bool get _isEditing => widget.existing != null;

  /// 새로 만들 땐 이미지를 반드시 골라야 하고, 편집 땐 이미 이미지가 있으니
  /// 안 바꿔도(새로 안 골라도) 제출할 수 있다.
  bool get _canSubmit => _pickedImageBytes != null || _isEditing;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    setState(() => _pickedImageBytes = bytes);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startAt : _endAt) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startAt = picked;
      } else {
        _endAt = picked;
      }
    });
  }

  void _submit() {
    Navigator.pop(
      context,
      _BannerFormResult(
        imageBytes: _pickedImageBytes,
        linkedPackId: _linkedPackId,
        active: _active,
        startAt: _startAt,
        endAt: _endAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingImageUrl = widget.existing?.imageUrl;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(_isEditing ? '배너 편집' : '새 배너', style: TextStyle(color: AdminColors.ivory)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                label: '배너 이미지',
                child: InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 110,
                    decoration: BoxDecoration(
                      border: Border.all(color: AdminColors.border),
                      borderRadius: BorderRadius.circular(10),
                      color: AdminColors.panel2,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildImagePreview(existingImageUrl),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: '연결할 스토리팩 (선택)',
                child: DropdownButtonFormField<String>(
                  initialValue: widget.packs.any((p) => p.id == _linkedPackId) ? _linkedPackId : null,
                  decoration: adminInputDecoration(hintText: '(선택 안 함)'),
                  dropdownColor: AdminColors.inputDropdownMenuBg,
                  style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('(선택 안 함)')),
                    for (final pack in widget.packs)
                      DropdownMenuItem<String>(value: pack.id, child: Text(pack.title)),
                  ],
                  onChanged: (value) => setState(() => _linkedPackId = value),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledField(
                      label: '시작일 (선택)',
                      child: _DateField(
                        date: _startAt,
                        onTap: () => _pickDate(isStart: true),
                        onClear: () => setState(() => _startAt = null),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: '종료일 (선택)',
                      child: _DateField(
                        date: _endAt,
                        onTap: () => _pickDate(isStart: false),
                        onClear: () => setState(() => _endAt = null),
                      ),
                    ),
                  ),
                ],
              ),
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
          child: Text(_isEditing ? '저장' : '만들기', style: const TextStyle(color: AdminColors.gold)),
        ),
      ],
    );
  }

  Widget _buildImagePreview(String? existingImageUrl) {
    final pickedBytes = _pickedImageBytes;
    if (pickedBytes != null) {
      return Image.memory(pickedBytes, fit: BoxFit.cover, width: double.infinity);
    }
    if (existingImageUrl != null && existingImageUrl.isNotEmpty) {
      return Image.network(
        existingImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _buildUploadPrompt(),
      );
    }
    return _buildUploadPrompt();
  }

  Widget _buildUploadPrompt() {
    return Center(
      child: Text(
        '클릭해서 이미지 업로드',
        style: TextStyle(color: AdminColors.muted, fontSize: 13),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _DateField extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateField({required this.date, required this.onTap, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AdminColors.inputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.inputBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null
                    ? '(선택 안 함)'
                    : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 13, color: date == null ? AdminColors.muted : AdminColors.inputText),
              ),
            ),
            if (date != null)
              InkWell(
                onTap: onClear,
                child: Icon(Icons.close_rounded, size: 16, color: AdminColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
