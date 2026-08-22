import 'package:flutter/material.dart';

import '../data/point_package_repository.dart';
import '../models/point_package.dart';
import '../widgets/admin_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/labeled_field.dart';

/// "포인트 상품 관리" — pointPackages 컬렉션을 콘솔 대신 여기서 만들고
/// 고친다. GenreManagementSection과 같은 급의 설정 섹션이지만, 가격/할인
/// 필드가 있고 삭제도 지원한다(다른 문서를 참조당하는 자원이 아니라서 —
/// homeBanners와 같은 이유). 여기 저장한 값이 충전 화면(ChargePage)의
/// 상품 카드와, 결제 승인 시점에 서버(confirmCoinCharge Cloud Function)가
/// 다시 읽어 검증하는 "진짜 가격"의 유일한 원천이다.
class PointPackageManagementSection extends StatefulWidget {
  final AdminPointPackageRepository repository;

  const PointPackageManagementSection({super.key, required this.repository});

  @override
  State<PointPackageManagementSection> createState() =>
      _PointPackageManagementSectionState();
}

class _PointPackageManagementSectionState
    extends State<PointPackageManagementSection> {
  late final Stream<List<AdminPointPackage>> _packagesStream =
      widget.repository.watchAllPackages();

  Future<void> _openCreateDialog() async {
    final result = await showDialog<_PackageFormResult>(
      context: context,
      builder: (_) => const _PackageFormDialog(existing: null),
    );
    if (result == null) return;

    await widget.repository.createPackage(
      name: result.name,
      coinAmount: result.coinAmount,
      bonusCoins: result.bonusCoins,
      originalPriceKRW: result.originalPriceKRW,
      salePriceKRW: result.salePriceKRW,
      discountStartAt: result.discountStartAt,
      discountEndAt: result.discountEndAt,
      active: result.active,
      sortOrder: result.sortOrder,
      platform: result.platform,
    );
  }

  Future<void> _openEditDialog(AdminPointPackage package) async {
    final result = await showDialog<_PackageFormResult>(
      context: context,
      builder: (_) => _PackageFormDialog(existing: package),
    );
    if (result == null) return;

    await widget.repository.updatePackage(
      package.id,
      name: result.name,
      coinAmount: result.coinAmount,
      bonusCoins: result.bonusCoins,
      originalPriceKRW: result.originalPriceKRW,
      salePriceKRW: result.salePriceKRW,
      discountStartAt: result.discountStartAt,
      discountEndAt: result.discountEndAt,
      active: result.active,
      sortOrder: result.sortOrder,
      platform: result.platform,
    );
  }

  Future<void> _toggleActive(AdminPointPackage package) async {
    await widget.repository.updatePackage(
      package.id,
      name: package.name,
      coinAmount: package.coinAmount,
      bonusCoins: package.bonusCoins,
      originalPriceKRW: package.originalPriceKRW,
      salePriceKRW: package.salePriceKRW,
      discountStartAt: package.discountStartAt,
      discountEndAt: package.discountEndAt,
      active: !package.active,
      sortOrder: package.sortOrder,
      platform: package.platform,
    );
  }

  Future<void> _delete(AdminPointPackage package) async {
    final confirmed = await showConfirmDialog(
      context,
      '"${package.name}" 상품을 삭제할까요? 이미 이 상품으로 결제한 내역에는 영향이 없어요.',
    );
    if (!confirmed) return;
    await widget.repository.deletePackage(package.id);
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
                    '포인트 상품 관리',
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
                    '+ 새 상품',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '여기서 만들고 고친 상품이 충전 화면의 코인 상품 카드로 바로 나타나요. '
              '할인가/기간을 정해두면 결제 시점에 서버가 자동으로 판단해요. '
              '삭제하면 목록에서 즉시 사라지지만, 이미 결제된 내역/지급된 코인에는 영향이 없어요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<AdminPointPackage>>(
              stream: _packagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText(
                    '상품 목록을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(fontSize: 12, color: AdminColors.danger),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text(
                    '불러오는 중...',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                final packages = snapshot.data ?? const <AdminPointPackage>[];
                if (packages.isEmpty) {
                  return Text(
                    '등록된 상품이 없어요. "+ 새 상품"으로 첫 상품을 만들어보세요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                return Column(
                  children: [
                    for (final package in packages)
                      _PackageRow(
                        package: package,
                        onEdit: () => _openEditDialog(package),
                        onToggleActive: () => _toggleActive(package),
                        onDelete: () => _delete(package),
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

class _PackageRow extends StatelessWidget {
  final AdminPointPackage package;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _PackageRow({
    required this.package,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !package.active;
    final hasDiscount = package.salePriceKRW != null;

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
                        package.name.isEmpty ? '(이름 없음)' : package.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AdminColors.ivory,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Chip(text: package.platform.label),
                      if (dimmed) ...[
                        const SizedBox(width: 6),
                        const _Chip(text: '비활성', danger: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '코인 ${package.coinAmount}'
                    '${package.bonusCoins > 0 ? ' + 보너스 ${package.bonusCoins}' : ''}'
                    ' · 정렬 ${package.sortOrder}',
                    style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasDiscount
                        ? '₩${package.originalPriceKRW} → ₩${package.salePriceKRW}'
                            '${_formatWindow(package.discountStartAt, package.discountEndAt)}'
                        : '₩${package.originalPriceKRW}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: hasDiscount ? AdminColors.gold : AdminColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: package.active,
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

class _PackageFormResult {
  final String name;
  final int coinAmount;
  final int bonusCoins;
  final int originalPriceKRW;
  final int? salePriceKRW;
  final DateTime? discountStartAt;
  final DateTime? discountEndAt;
  final bool active;
  final int sortOrder;
  final AdminPointPackagePlatform platform;

  const _PackageFormResult({
    required this.name,
    required this.coinAmount,
    required this.bonusCoins,
    required this.originalPriceKRW,
    required this.salePriceKRW,
    required this.discountStartAt,
    required this.discountEndAt,
    required this.active,
    required this.sortOrder,
    required this.platform,
  });
}

/// 새 상품 만들기/기존 상품 편집을 같은 폼으로 처리한다.
class _PackageFormDialog extends StatefulWidget {
  final AdminPointPackage? existing;

  const _PackageFormDialog({required this.existing});

  @override
  State<_PackageFormDialog> createState() => _PackageFormDialogState();
}

class _PackageFormDialogState extends State<_PackageFormDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _coinController =
      TextEditingController(text: '${widget.existing?.coinAmount ?? 0}');
  late final TextEditingController _bonusController =
      TextEditingController(text: '${widget.existing?.bonusCoins ?? 0}');
  late final TextEditingController _priceController =
      TextEditingController(text: '${widget.existing?.originalPriceKRW ?? 0}');
  late final TextEditingController _salePriceController = TextEditingController(
    text: widget.existing?.salePriceKRW != null
        ? '${widget.existing!.salePriceKRW}'
        : '',
  );
  late final TextEditingController _sortOrderController =
      TextEditingController(text: '${widget.existing?.sortOrder ?? 0}');

  late bool _active = widget.existing?.active ?? true;
  late DateTime? _discountStartAt = widget.existing?.discountStartAt;
  late DateTime? _discountEndAt = widget.existing?.discountEndAt;
  late AdminPointPackagePlatform _platform =
      widget.existing?.platform ?? AdminPointPackagePlatform.web;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.dispose();
    _coinController.dispose();
    _bonusController.dispose();
    _priceController.dispose();
    _salePriceController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      (int.tryParse(_priceController.text.trim()) ?? 0) > 0;

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

  void _submit() {
    final salePriceText = _salePriceController.text.trim();
    Navigator.pop(
      context,
      _PackageFormResult(
        name: _nameController.text.trim(),
        coinAmount: int.tryParse(_coinController.text.trim()) ?? 0,
        bonusCoins: int.tryParse(_bonusController.text.trim()) ?? 0,
        originalPriceKRW: int.tryParse(_priceController.text.trim()) ?? 0,
        salePriceKRW: salePriceText.isEmpty ? null : int.tryParse(salePriceText),
        discountStartAt: _discountStartAt,
        discountEndAt: _discountEndAt,
        active: _active,
        sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
        platform: _platform,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(
        isEditing ? '상품 편집' : '새 상품',
        style: TextStyle(color: AdminColors.ivory),
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                label: '상품명',
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: 코인 500개'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledField(
                      label: '기본 코인',
                      child: TextField(
                        controller: _coinController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                        decoration: adminInputDecoration(hintText: '500'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: '보너스 코인',
                      child: TextField(
                        controller: _bonusController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                        decoration: adminInputDecoration(hintText: '0'),
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
                      label: '정가 (원)',
                      child: TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                        decoration: adminInputDecoration(hintText: '5500'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: '할인가 (원, 선택)',
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
              Row(
                children: [
                  Expanded(
                    child: LabeledField(
                      label: '플랫폼',
                      child: DropdownButtonFormField<AdminPointPackagePlatform>(
                        initialValue: _platform,
                        decoration: adminInputDecoration(),
                        dropdownColor: AdminColors.inputDropdownMenuBg,
                        style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                        items: [
                          for (final platform in AdminPointPackagePlatform.values)
                            DropdownMenuItem(
                              value: platform,
                              child: Text(platform.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _platform = value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: '정렬 순서',
                      child: TextField(
                        controller: _sortOrderController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                        decoration: adminInputDecoration(hintText: '0'),
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
