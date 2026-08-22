import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../widgets/admin_theme.dart';
import '../widgets/labeled_field.dart';

enum _SearchMode { name, uid }

/// 결제내역/코인사용내역 탭이 공유하는 필터 바 — 기간(시작일/종료일),
/// 이름 또는 uid 검색, (결제내역 전용) 결제금액 범위. "적용"을 눌러야
/// [onApply]가 불린다(키 입력마다 네트워크 조회가 나가지 않도록) — 날짜는
/// 고르는 즉시 반영한다(달력 다이얼로그 자체가 이미 명시적인 확정 동작이라
/// 별도 적용 버튼이 필요 없다).
class BillingFilterBar extends StatefulWidget {
  final bool showAmountFilter;
  final ValueChanged<AdminBillingFilter> onApply;

  const BillingFilterBar({
    super.key,
    required this.onApply,
    this.showAmountFilter = false,
  });

  @override
  State<BillingFilterBar> createState() => _BillingFilterBarState();
}

class _BillingFilterBarState extends State<BillingFilterBar> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();

  _SearchMode _searchMode = _SearchMode.name;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _searchController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
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
        _startDate = DateTime(picked.year, picked.month, picked.day);
      } else {
        // 종료일은 그날 끝까지 포함해야 하니 23:59:59.999로 맞춘다 —
        // createdAt <= endDate 비교가 종료일 당일 거래도 포함하게 하려고.
        _endDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
      }
    });
    _apply();
  }

  void _apply() {
    final searchText = _searchController.text.trim();
    final minAmount = int.tryParse(_minAmountController.text.trim());
    final maxAmount = int.tryParse(_maxAmountController.text.trim());
    widget.onApply(
      AdminBillingFilter(
        startDate: _startDate,
        endDate: _endDate,
        uidQuery: _searchMode == _SearchMode.uid && searchText.isNotEmpty ? searchText : null,
        nameQuery: _searchMode == _SearchMode.name && searchText.isNotEmpty ? searchText : null,
        minAmountKRW: widget.showAmountFilter ? minAmount : null,
        maxAmountKRW: widget.showAmountFilter ? maxAmount : null,
      ),
    );
  }

  void _reset() {
    setState(() {
      _searchController.clear();
      _minAmountController.clear();
      _maxAmountController.clear();
      _startDate = null;
      _endDate = null;
      _searchMode = _SearchMode.name;
    });
    widget.onApply(AdminBillingFilter.empty);
  }

  String _fmt(DateTime? d) => d == null
      ? '(선택 안 함)'
      : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 220,
          child: LabeledField(
            label: '검색',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _apply(),
                    style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                    decoration: adminInputDecoration(
                      hintText: _searchMode == _SearchMode.name ? '표시 이름' : 'uid',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                DropdownButton<_SearchMode>(
                  value: _searchMode,
                  dropdownColor: AdminColors.inputDropdownMenuBg,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: AdminColors.inputText, fontSize: 12),
                  items: const [
                    DropdownMenuItem(value: _SearchMode.name, child: Text('이름')),
                    DropdownMenuItem(value: _SearchMode.uid, child: Text('uid')),
                  ],
                  onChanged: (mode) {
                    if (mode != null) setState(() => _searchMode = mode);
                  },
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 150,
          child: LabeledField(
            label: '시작일',
            child: _DateChip(label: _fmt(_startDate), onTap: () => _pickDate(isStart: true)),
          ),
        ),
        SizedBox(
          width: 150,
          child: LabeledField(
            label: '종료일',
            child: _DateChip(label: _fmt(_endDate), onTap: () => _pickDate(isStart: false)),
          ),
        ),
        if (widget.showAmountFilter) ...[
          SizedBox(
            width: 120,
            child: LabeledField(
              label: '최소 결제금액',
              child: TextField(
                controller: _minAmountController,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _apply(),
                style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                decoration: adminInputDecoration(hintText: '0'),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: LabeledField(
              label: '최대 결제금액',
              child: TextField(
                controller: _maxAmountController,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _apply(),
                style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                decoration: adminInputDecoration(hintText: '(제한 없음)'),
              ),
            ),
          ),
        ],
        ElevatedButton(
          onPressed: _apply,
          style: ElevatedButton.styleFrom(
            backgroundColor: AdminColors.gold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('검색', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: _reset,
          child: Text('초기화', style: TextStyle(color: AdminColors.muted)),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
        child: Text(
          label,
          style: TextStyle(fontSize: 13, color: AdminColors.inputText),
        ),
      ),
    );
  }
}
