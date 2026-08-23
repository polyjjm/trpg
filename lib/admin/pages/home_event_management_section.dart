import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/home_event_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/home_event.dart';
import '../widgets/admin_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/labeled_field.dart';

/// "홈 이벤트 관리" — homeEvents 컬렉션을 여기서 만들고 고치고 순서를
/// 바꾼다. HomeBannerManagementSection과 거의 같은 구조(이미지 업로드 →
/// Storage, 삭제 지원, 드래그 재정렬)지만, 배너와 달리 이 이미지는 홈 탭이
/// 열릴 때 뜨는 모달 팝업으로 쓰인다 — 리더 쪽 "다시 보지 않기"/"오늘 이미
/// 봤음" 상태는 기기 로컬(SharedPreferences)에만 저장되고 여기서는 다루지
/// 않는다(HomeEventDismissalStore, lib/features/catalog/data/ 참고).
class HomeEventManagementSection extends StatefulWidget {
  final HomeEventRepository repository;
  final Stream<List<AdminStoryPack>> packsStream;

  const HomeEventManagementSection({
    super.key,
    required this.repository,
    required this.packsStream,
  });

  @override
  State<HomeEventManagementSection> createState() => _HomeEventManagementSectionState();
}

class _HomeEventManagementSectionState extends State<HomeEventManagementSection> {
  late final Stream<List<AdminHomeEvent>> _eventsStream = widget.repository.watchAllEvents();

  Future<void> _openCreateDialog(List<AdminStoryPack> packs, int nextSortOrder) async {
    final result = await showDialog<_EventFormResult>(
      context: context,
      builder: (_) => _EventFormDialog(existing: null, packs: packs),
    );
    if (result == null) return;

    final imageBytes = result.imageBytes;
    if (imageBytes == null) return; // 폼이 이미지 없이는 제출을 못 하게 막아 둔다.

    await widget.repository.createEvent(
      imageBytes: imageBytes,
      title: result.title,
      linkedPackId: result.linkedPackId,
      sortOrder: nextSortOrder,
      active: result.active,
      startDate: result.startDate,
      endDate: result.endDate,
    );
  }

  Future<void> _openEditDialog(AdminHomeEvent event, List<AdminStoryPack> packs) async {
    final result = await showDialog<_EventFormResult>(
      context: context,
      builder: (_) => _EventFormDialog(existing: event, packs: packs),
    );
    if (result == null) return;

    await widget.repository.updateEvent(
      event.id,
      imageBytes: result.imageBytes,
      title: result.title,
      linkedPackId: result.linkedPackId,
      sortOrder: event.sortOrder,
      active: result.active,
      startDate: result.startDate,
      endDate: result.endDate,
    );
  }

  Future<void> _delete(AdminHomeEvent event) async {
    final confirmed = await showConfirmDialog(context, '이 이벤트를 삭제할까요?');
    if (!confirmed) return;
    await widget.repository.deleteEvent(event);
  }

  Future<void> _reorder(List<AdminHomeEvent> events, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = [...events];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await widget.repository.reorder(reordered.map((e) => e.id).toList());
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
                StreamBuilder<List<AdminHomeEvent>>(
                  stream: _eventsStream,
                  builder: (context, snapshot) {
                    final events = snapshot.data ?? const <AdminHomeEvent>[];
                    final nextSortOrder = events.isEmpty
                        ? 0
                        : events.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            '홈 이벤트 관리',
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
                          child: const Text('+ 새 이벤트', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  '여기서 만든 이벤트는 홈 탭이 열릴 때 모달 팝업으로 떠요. 동시에 여러 이벤트가 활성 상태면 '
                  '정렬 순서가 가장 작은 것 하나만 보여줘요(여러 개가 겹쳐 뜨지 않아요). 독자가 "다시 보지 않기"를 '
                  '누르면 그 이벤트만 그 사람 기기에서 다시는 안 떠요 — 새 이벤트를 만들면 그 사람에게도 새로 떠요.',
                  style: TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<AdminHomeEvent>>(
                  stream: _eventsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SelectableText(
                        '이벤트 목록을 불러오지 못했어요: ${snapshot.error}',
                        style: const TextStyle(fontSize: 12, color: AdminColors.danger),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                    }

                    final events = snapshot.data ?? const <AdminHomeEvent>[];
                    if (events.isEmpty) {
                      return Text(
                        '등록된 이벤트가 없어요. "+ 새 이벤트"로 첫 이벤트를 만들어보세요.',
                        style: TextStyle(fontSize: 13, color: AdminColors.muted),
                      );
                    }

                    return ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) => _reorder(events, oldIndex, newIndex),
                      children: [
                        for (var i = 0; i < events.length; i++)
                          _EventRow(
                            key: ValueKey(events[i].id),
                            index: i,
                            event: events[i],
                            linkedPackTitle: events[i].linkedPackId != null
                                ? packTitles[events[i].linkedPackId]
                                : null,
                            onEdit: () => _openEditDialog(events[i], packs),
                            onDelete: () => _delete(events[i]),
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

class _EventRow extends StatelessWidget {
  final int index;
  final AdminHomeEvent event;
  final String? linkedPackTitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventRow({
    required super.key,
    required this.index,
    required this.event,
    required this.linkedPackTitle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !event.active;
    final title = event.title;

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
                width: 34,
                height: 42,
                child: event.imageUrl.isNotEmpty
                    ? Image.network(
                        event.imageUrl,
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
                          title != null && title.isNotEmpty ? title : (linkedPackTitle ?? '(제목 없음)'),
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
                  if (linkedPackTitle != null || event.startDate != null || event.endDate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (linkedPackTitle != null) '연결: $linkedPackTitle',
                        if (event.startDate != null || event.endDate != null)
                          '기간: ${_formatDate(event.startDate)} ~ ${_formatDate(event.endDate)}',
                      ].join(' · '),
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

class _EventFormResult {
  final Uint8List? imageBytes;
  final String? title;
  final String? linkedPackId;
  final bool active;
  final DateTime? startDate;
  final DateTime? endDate;

  const _EventFormResult({
    required this.imageBytes,
    required this.title,
    required this.linkedPackId,
    required this.active,
    required this.startDate,
    required this.endDate,
  });
}

/// 새 이벤트 만들기/기존 이벤트 편집을 같은 폼으로 처리한다. [existing]이
/// null이면 생성, 아니면 그 값으로 필드를 채운 편집 모드다.
class _EventFormDialog extends StatefulWidget {
  final AdminHomeEvent? existing;
  final List<AdminStoryPack> packs;

  const _EventFormDialog({required this.existing, required this.packs});

  @override
  State<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<_EventFormDialog> {
  Uint8List? _pickedImageBytes;
  late String? _linkedPackId = widget.existing?.linkedPackId;
  late bool _active = widget.existing?.active ?? true;
  late DateTime? _startDate = widget.existing?.startDate;
  late DateTime? _endDate = widget.existing?.endDate;
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');

  bool get _isEditing => widget.existing != null;

  /// 새로 만들 땐 이미지를 반드시 골라야 하고, 편집 땐 이미 이미지가 있으니
  /// 안 바꿔도(새로 안 골라도) 제출할 수 있다.
  bool get _canSubmit => _pickedImageBytes != null || _isEditing;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    setState(() => _pickedImageBytes = bytes);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  void _submit() {
    String? normalize(String text) => text.trim().isEmpty ? null : text.trim();

    Navigator.pop(
      context,
      _EventFormResult(
        imageBytes: _pickedImageBytes,
        title: normalize(_titleController.text),
        linkedPackId: _linkedPackId,
        active: _active,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingImageUrl = widget.existing?.imageUrl;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(_isEditing ? '이벤트 편집' : '새 이벤트', style: TextStyle(color: AdminColors.ivory)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                label: '이벤트 이미지',
                child: InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 160,
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
              const SizedBox(height: 4),
              Text(
                '독자 홈 화면에 뜨는 팝업 이미지예요(세로 4:5 비율로 잘려 보여요).',
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: '타이틀 (선택)',
                child: TextField(
                  controller: _titleController,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: 8월 신작 이벤트'),
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
              const SizedBox(height: 4),
              Text(
                '팝업 이미지를 탭했을 때 이동할 스토리팩이에요. 안 고르면 탭해도 아무 일도 안 일어나요.',
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledField(
                      label: '시작일 (선택)',
                      child: _DateField(
                        date: _startDate,
                        onTap: () => _pickDate(isStart: true),
                        onClear: () => setState(() => _startDate = null),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: '종료일 (선택)',
                      child: _DateField(
                        date: _endDate,
                        onTap: () => _pickDate(isStart: false),
                        onClear: () => setState(() => _endDate = null),
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
