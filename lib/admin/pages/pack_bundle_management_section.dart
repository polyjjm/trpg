import 'package:flutter/material.dart';

import '../data/pack_bundle_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/pack_bundle.dart';
import '../widgets/admin_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/labeled_field.dart';

/// "번들 상품 관리" — packBundles 컬렉션을 여기서 만들고 고치고 순서를
/// 바꾼다. PointPackageManagementSection과 같은 급의 설정 섹션이지만,
/// 상품 하나가 기존 스토리팩 여러 개를 참조한다는 점만 다르다(제목으로
/// 검색해서 체크박스로 고른다).
class PackBundleManagementSection extends StatefulWidget {
  final AdminPackBundleRepository repository;
  final Stream<List<AdminStoryPack>> packsStream;

  const PackBundleManagementSection({
    super.key,
    required this.repository,
    required this.packsStream,
  });

  @override
  State<PackBundleManagementSection> createState() =>
      _PackBundleManagementSectionState();
}

class _PackBundleManagementSectionState
    extends State<PackBundleManagementSection> {
  late final Stream<List<AdminPackBundle>> _bundlesStream =
      widget.repository.watchAllBundles();

  Future<void> _openCreateDialog(List<AdminStoryPack> packs, int nextSortOrder) async {
    final result = await showDialog<_BundleFormResult>(
      context: context,
      builder: (_) => _BundleFormDialog(existing: null, packs: packs),
    );
    if (result == null) return;

    await widget.repository.createBundle(
      name: result.name,
      packIds: result.packIds,
      price: result.price,
      salePrice: result.salePrice,
      discountStartAt: result.discountStartAt,
      discountEndAt: result.discountEndAt,
      active: result.active,
      sortOrder: nextSortOrder,
    );
  }

  Future<void> _openEditDialog(AdminPackBundle bundle, List<AdminStoryPack> packs) async {
    final result = await showDialog<_BundleFormResult>(
      context: context,
      builder: (_) => _BundleFormDialog(existing: bundle, packs: packs),
    );
    if (result == null) return;

    await widget.repository.updateBundle(
      bundle.id,
      name: result.name,
      packIds: result.packIds,
      price: result.price,
      salePrice: result.salePrice,
      discountStartAt: result.discountStartAt,
      discountEndAt: result.discountEndAt,
      active: result.active,
      sortOrder: bundle.sortOrder,
    );
  }

  Future<void> _toggleActive(AdminPackBundle bundle) async {
    await widget.repository.updateBundle(
      bundle.id,
      name: bundle.name,
      packIds: bundle.packIds,
      price: bundle.price,
      salePrice: bundle.salePrice,
      discountStartAt: bundle.discountStartAt,
      discountEndAt: bundle.discountEndAt,
      active: !bundle.active,
      sortOrder: bundle.sortOrder,
    );
  }

  Future<void> _delete(AdminPackBundle bundle) async {
    final confirmed = await showConfirmDialog(
      context,
      '"${bundle.name}" 번들을 삭제할까요? 이미 이 번들로 구매한 내역(소유한 팩)에는 영향이 없어요.',
    );
    if (!confirmed) return;
    await widget.repository.deleteBundle(bundle.id);
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
                StreamBuilder<List<AdminPackBundle>>(
                  stream: _bundlesStream,
                  builder: (context, snapshot) {
                    final bundles = snapshot.data ?? const <AdminPackBundle>[];
                    final nextSortOrder = bundles.isEmpty
                        ? 0
                        : bundles.map((b) => b.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            '번들 상품 관리',
                            style: TextStyle(
                              fontSize: 16,
                              color: AdminColors.ivory,
                              fontWeight: FontWeight.w700,
                            ),
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
                          child: const Text('+ 새 번들', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  '여기서 만든 번들이 홈 화면 "번들 상품" 섹션과 포함된 팩의 상세 화면에 바로 나타나요. '
                  '구매자가 이미 갖고 있는 팩이 섞여 있으면, 서버가 자동으로 아직 없는 팩 개수만큼만 '
                  '가격을 나눠서 청구해요 — 전부 이미 갖고 있으면 구매가 막혀요.',
                  style: TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<AdminPackBundle>>(
                  stream: _bundlesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SelectableText(
                        '번들 목록을 불러오지 못했어요: ${snapshot.error}',
                        style: const TextStyle(fontSize: 12, color: AdminColors.danger),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                    }

                    final bundles = snapshot.data ?? const <AdminPackBundle>[];
                    if (bundles.isEmpty) {
                      return Text(
                        '등록된 번들이 없어요. "+ 새 번들"로 첫 번들을 만들어보세요.',
                        style: TextStyle(fontSize: 13, color: AdminColors.muted),
                      );
                    }

                    return ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final reordered = [...bundles];
                        final moved = reordered.removeAt(oldIndex);
                        reordered.insert(newIndex, moved);
                        widget.repository.reorder(reordered.map((b) => b.id).toList());
                      },
                      children: [
                        for (var i = 0; i < bundles.length; i++)
                          _BundleRow(
                            key: ValueKey(bundles[i].id),
                            index: i,
                            bundle: bundles[i],
                            packTitles: packTitles,
                            onEdit: () => _openEditDialog(bundles[i], packs),
                            onToggleActive: () => _toggleActive(bundles[i]),
                            onDelete: () => _delete(bundles[i]),
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

class _BundleRow extends StatelessWidget {
  final int index;
  final AdminPackBundle bundle;
  final Map<String, String> packTitles;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _BundleRow({
    required super.key,
    required this.index,
    required this.bundle,
    required this.packTitles,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !bundle.active;
    final hasDiscount = bundle.salePrice != null;
    final includedTitles = bundle.packIds
        .map((id) => packTitles[id] ?? '(삭제된 팩)')
        .join(', ');

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
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.drag_indicator_rounded, color: AdminColors.muted, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        bundle.name.isEmpty ? '(이름 없음)' : bundle.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AdminColors.ivory,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Chip(text: '팩 ${bundle.packIds.length}개'),
                      if (dimmed) ...[
                        const SizedBox(width: 6),
                        const _Chip(text: '비활성', danger: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    includedTitles.isEmpty ? '(포함된 팩 없음)' : includedTitles,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasDiscount
                        ? '${bundle.price}코인 → ${bundle.salePrice}코인'
                            '${_formatWindow(bundle.discountStartAt, bundle.discountEndAt)}'
                        : '${bundle.price}코인',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: hasDiscount ? AdminColors.gold : AdminColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: bundle.active,
              onChanged: (_) => onToggleActive(),
              activeThumbColor: AdminColors.gold,
            ),
            const SizedBox(width: 4),
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

  static String _formatWindow(DateTime? start, DateTime? end) {
    if (start == null && end == null) return '';
    String fmt(DateTime? d) => d == null
        ? '(없음)'
        : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return ' (${fmt(start)} ~ ${fmt(end)})';
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool danger;

  const _Chip({required this.text, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: danger ? AdminColors.statusDraftBg : AdminColors.badgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: danger ? AdminColors.statusDraftText : AdminColors.gold,
        ),
      ),
    );
  }
}

class _BundleFormResult {
  final String name;
  final List<String> packIds;
  final int price;
  final int? salePrice;
  final DateTime? discountStartAt;
  final DateTime? discountEndAt;
  final bool active;

  const _BundleFormResult({
    required this.name,
    required this.packIds,
    required this.price,
    required this.salePrice,
    required this.discountStartAt,
    required this.discountEndAt,
    required this.active,
  });
}

/// 새 번들 만들기/기존 번들 편집을 같은 폼으로 처리한다. 포함할 팩은
/// 제목으로 검색해서 체크박스로 고른다(전체 팩 목록이 많아질 수 있어서
/// 드롭다운 대신 검색 가능한 체크박스 목록을 쓴다).
class _BundleFormDialog extends StatefulWidget {
  final AdminPackBundle? existing;
  final List<AdminStoryPack> packs;

  const _BundleFormDialog({required this.existing, required this.packs});

  @override
  State<_BundleFormDialog> createState() => _BundleFormDialogState();
}

class _BundleFormDialogState extends State<_BundleFormDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _priceController =
      TextEditingController(text: '${widget.existing?.price ?? 0}');
  late final TextEditingController _salePriceController = TextEditingController(
    text: widget.existing?.salePrice != null ? '${widget.existing!.salePrice}' : '',
  );
  final TextEditingController _packSearchController = TextEditingController();

  late bool _active = widget.existing?.active ?? true;
  late DateTime? _discountStartAt = widget.existing?.discountStartAt;
  late DateTime? _discountEndAt = widget.existing?.discountEndAt;
  late final Set<String> _selectedPackIds = {...?widget.existing?.packIds};

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onChanged);
    _priceController.addListener(_onChanged);
    _packSearchController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _salePriceController.dispose();
    _packSearchController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      (int.tryParse(_priceController.text.trim()) ?? 0) > 0 &&
      _selectedPackIds.length >= 2;

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _discountStartAt : _discountEndAt) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _discountStartAt = picked;
      } else {
        _discountEndAt = picked;
      }
    });
  }

  void _togglePack(String packId) {
    setState(() {
      if (!_selectedPackIds.remove(packId)) {
        _selectedPackIds.add(packId);
      }
    });
  }

  void _submit() {
    final salePriceText = _salePriceController.text.trim();
    Navigator.pop(
      context,
      _BundleFormResult(
        name: _nameController.text.trim(),
        packIds: _selectedPackIds.toList(),
        price: int.tryParse(_priceController.text.trim()) ?? 0,
        salePrice: salePriceText.isEmpty ? null : int.tryParse(salePriceText),
        discountStartAt: _discountStartAt,
        discountEndAt: _discountEndAt,
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final query = _packSearchController.text.trim().toLowerCase();
    final filteredPacks = query.isEmpty
        ? widget.packs
        : widget.packs.where((p) => p.title.toLowerCase().contains(query)).toList();

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(
        isEditing ? '번들 편집' : '새 번들',
        style: TextStyle(color: AdminColors.ivory),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                label: '번들명',
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: 공포 3부작 세트'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledField(
                      label: '정가 (코인)',
                      child: TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                        decoration: adminInputDecoration(hintText: '900'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: '할인가 (코인, 선택)',
                      child: TextField(
                        controller: _salePriceController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                        decoration: adminInputDecoration(hintText: '(할인 없음)'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledField(
                      label: '할인 시작일 (선택)',
                      child: _DateField(
                        date: _discountStartAt,
                        onTap: () => _pickDate(isStart: true),
                        onClear: () => setState(() => _discountStartAt = null),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: '할인 종료일 (선택)',
                      child: _DateField(
                        date: _discountEndAt,
                        onTap: () => _pickDate(isStart: false),
                        onClear: () => setState(() => _discountEndAt = null),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: '포함할 팩 (2개 이상, 제목으로 검색)',
                child: TextField(
                  controller: _packSearchController,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '제목 검색'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_selectedPackIds.length}개 선택됨',
                style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
              ),
              const SizedBox(height: 4),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: AdminColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: filteredPacks.isEmpty
                    ? Center(
                        child: Text(
                          '검색 결과가 없어요',
                          style: TextStyle(fontSize: 12, color: AdminColors.muted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredPacks.length,
                        itemBuilder: (context, index) {
                          final pack = filteredPacks[index];
                          final selected = _selectedPackIds.contains(pack.id);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            onChanged: (_) => _togglePack(pack.id),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AdminColors.gold,
                            title: Text(
                              pack.title,
                              style: TextStyle(fontSize: 13, color: AdminColors.ivory),
                            ),
                          );
                        },
                      ),
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
          child: Text(
            isEditing ? '저장' : '만들기',
            style: const TextStyle(color: AdminColors.gold),
          ),
        ),
      ],
    );
  }
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
