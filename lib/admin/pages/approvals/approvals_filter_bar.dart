import 'package:flutter/material.dart';

import '../../widgets/admin_theme.dart';
import 'approval_filter.dart';

/// 승인 대기함 상단의 검색 + 요청 유형 + 기간 + 정렬 바.
///
/// 칩을 드롭다운이 아니라 나열한 이유: 유형 4개·기간 4개가 전부라 펼치는
/// 동작 없이 현재 상태가 그대로 보이는 편이 하루 종일 쓰는 화면에서 낫다.
/// "직접 지정"을 골랐을 때만 날짜 입력 두 칸이 아래로 펼쳐진다.
class ApprovalsFilterBar extends StatelessWidget {
  final ApprovalFilter filter;
  final ValueChanged<ApprovalFilter> onChanged;

  /// 헤더에 같이 보여줄 요약 — "12건 대기 · 가장 오래 기다린 요청 3일".
  final String summary;

  const ApprovalsFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.summary,
  });

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final initial =
        (isFrom ? filter.from : filter.to) ??
        DateTime.now().subtract(Duration(days: isFrom ? 7 : 0));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AdminColors.gold,
            brightness: AdminTheme.isDark ? Brightness.dark : Brightness.light,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    onChanged(
      isFrom ? filter.copyWith(from: picked) : filter.copyWith(to: picked),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '승인 대기함',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.ivory,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    summary,
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final status in ApprovalStatusFilter.values)
                _Chip(
                  label: status.label,
                  selected: filter.status == status,
                  onTap: () => onChanged(filter.copyWith(status: status)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (value) =>
                      onChanged(filter.copyWith(query: value)),
                  style: TextStyle(fontSize: 12, color: AdminColors.ivory),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    hintText: '작가 · 작품 · 노드 ID 검색',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: AdminColors.muted,
                    ),
                    filled: true,
                    fillColor: AdminColors.panel,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AdminColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AdminColors.gold),
                    ),
                  ),
                ),
              ),
              // 요청 유형(등록/수정/삭제)은 대기 목록에만 있는 개념이라
              // "처리됨" 전용 모드에서는 숨긴다(요청 사양: 처리 이력엔 검색·
              // 기간 필터만 걸린다) — "전체"는 대기 목록도 같이 보이므로
              // 그대로 둔다.
              if (filter.status != ApprovalStatusFilter.handled) ...[
                for (final kind in ApprovalKindFilter.values)
                  _Chip(
                    label: kind.label,
                    selected: filter.kind == kind,
                    onTap: () => onChanged(filter.copyWith(kind: kind)),
                  ),
                _Divider(),
              ],
              for (final range in ApprovalDateRange.values)
                _Chip(
                  label: range.label,
                  selected: filter.range == range,
                  onTap: () => onChanged(filter.copyWith(range: range)),
                ),
              _Divider(),
              _Chip(
                label: filter.sort == ApprovalSort.oldestFirst
                    ? '오래된 순 ↑'
                    : '최신 순 ↓',
                selected: false,
                onTap: () => onChanged(
                  filter.copyWith(
                    sort: filter.sort == ApprovalSort.oldestFirst
                        ? ApprovalSort.newestFirst
                        : ApprovalSort.oldestFirst,
                  ),
                ),
              ),
            ],
          ),
          if (filter.range == ApprovalDateRange.custom) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _DateButton(
                  label: filter.from == null
                      ? '시작일'
                      : formatRequestedDate(filter.from),
                  onTap: () => _pickDate(context, isFrom: true),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '—',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                ),
                _DateButton(
                  label: filter.to == null
                      ? '종료일'
                      : formatRequestedDate(filter.to),
                  onTap: () => _pickDate(context, isFrom: false),
                ),
                const SizedBox(width: 10),
                Text(
                  '요청일 기준',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 20, color: AdminColors.border);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : Colors.transparent,
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AdminColors.panel,
          border: Border.all(color: AdminColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: AdminColors.ivory),
        ),
      ),
    );
  }
}
