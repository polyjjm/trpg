import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../data/point_package_repository.dart';
import '../models/point_package.dart';
import '../models/wallet_transaction.dart';
import '../widgets/admin_theme.dart';
import 'billing_filter_bar.dart';
import 'refund_dialog.dart';

/// "결제내역" 탭 — collectionGroup('transactions')의 type == 'charge'만.
/// 환불 액션은 refundStatus != 'full'인 행에서만 보여준다(완전 환불된
/// 행은 "환불됨" 배지만, 부분 환불된 행은 "부분환불" 배지 + 환불 버튼
/// 둘 다 — 수학적으로 더 환불할 여지가 있으면 계속 허용한다).
class PaymentHistoryTab extends StatefulWidget {
  final AdminBillingRepository repository;
  final AdminPointPackageRepository pointPackageRepository;

  const PaymentHistoryTab({
    super.key,
    required this.repository,
    required this.pointPackageRepository,
  });

  @override
  State<PaymentHistoryTab> createState() => _PaymentHistoryTabState();
}

class _PaymentHistoryTabState extends State<PaymentHistoryTab> {
  late final Stream<List<AdminPointPackage>> _packagesStream = widget
      .pointPackageRepository
      .watchAllPackages();

  AdminBillingFilter _filter = AdminBillingFilter.empty;

  // 페이지 커서 스택 — 0번째는 항상 null(첫 페이지). "다음"을 누르면
  // 방금 페이지의 마지막 문서를 push하고, "이전"을 누르면 pop해서 그
  // 이전 커서로 다시 조회한다. Firestore 커서 페이지네이션은 임의
  // 페이지로 바로 점프할 수 없어서(건너뛴 페이지를 전부 읽어야 함),
  // 이전/다음만 지원한다 — "간단한 페이지 번호 버튼"의 가장 현실적인
  // 형태다.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _cursorStack = [
    null,
  ];
  int _pageIndex = 0;

  BillingPage<AdminChargeTransaction>? _page;
  bool _isLoading = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final page = await widget.repository.fetchCharges(
        filter: _filter,
        startAfter: _cursorStack[_pageIndex],
      );
      if (!mounted) return;
      setState(() => _page = page);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter(AdminBillingFilter filter) {
    setState(() {
      _filter = filter;
      _cursorStack
        ..clear()
        ..add(null);
      _pageIndex = 0;
    });
    _load();
  }

  void _nextPage() {
    final page = _page;
    if (page == null || !page.hasMore || page.lastDoc == null) return;
    setState(() {
      if (_cursorStack.length == _pageIndex + 1) {
        _cursorStack.add(page.lastDoc);
      }
      _pageIndex++;
    });
    _load();
  }

  void _prevPage() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminPointPackage>>(
      stream: _packagesStream,
      builder: (context, packagesSnapshot) {
        final packageNameById = {
          for (final p in packagesSnapshot.data ?? const <AdminPointPackage>[])
            p.id: p.name,
        };

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BillingFilterBar(showAmountFilter: true, onApply: _applyFilter),
              const SizedBox(height: 16),
              Expanded(child: _buildBody(packageNameById)),
              const SizedBox(height: 12),
              _buildPager(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(Map<String, String> packageNameById) {
    if (_loadError != null) {
      return SelectableText(
        '결제내역을 불러오지 못했어요: $_loadError',
        style: const TextStyle(fontSize: 12, color: AdminColors.danger),
      );
    }
    if (_isLoading && _page == null) {
      return Center(
        child: Text(
          '불러오는 중...',
          style: TextStyle(fontSize: 13, color: AdminColors.muted),
        ),
      );
    }
    final items = _page?.items ?? const <AdminChargeTransaction>[];
    if (items.isEmpty) {
      return Center(
        child: Text(
          '조건에 맞는 결제내역이 없어요.',
          style: TextStyle(fontSize: 13, color: AdminColors.muted),
        ),
      );
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AdminColors.panel2),
          columns: const [
            DataColumn(label: Text('일시')),
            DataColumn(label: Text('사용자')),
            DataColumn(label: Text('상품명')),
            DataColumn(label: Text('결제금액')),
            DataColumn(label: Text('지급 코인')),
            DataColumn(label: Text('주문번호/paymentKey')),
            DataColumn(label: Text('환불')),
          ],
          rows: [
            for (final tx in items)
              DataRow(
                cells: [
                  DataCell(Text(_formatDate(tx.createdAt))),
                  DataCell(_UserCell(displayName: tx.displayName, uid: tx.uid)),
                  DataCell(Text(packageNameById[tx.packageId] ?? tx.packageId)),
                  DataCell(Text('${tx.amountKRW}원')),
                  DataCell(Text('${tx.coinAmount}')),
                  DataCell(
                    SelectableText(
                      tx.relatedPaymentKey ?? '-',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  DataCell(_buildRefundCell(tx)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundCell(AdminChargeTransaction tx) {
    if (tx.refundStatus == AdminRefundStatus.full) {
      return const _StatusPill(text: '환불됨', danger: true);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tx.refundStatus == AdminRefundStatus.partial) ...[
          const _StatusPill(text: '부분환불', danger: true),
          const SizedBox(width: 6),
        ],
        if (tx.canRefund)
          TextButton(
            onPressed: () =>
                showRefundDialog(context, charge: tx, onRefunded: _load),
            child: const Text(
              '환불',
              style: TextStyle(fontSize: 12, color: AdminColors.danger),
            ),
          ),
      ],
    );
  }

  Widget _buildPager() {
    final page = _page;
    return Row(
      children: [
        Text(
          '페이지 ${_pageIndex + 1}',
          style: TextStyle(fontSize: 12, color: AdminColors.muted),
        ),
        const Spacer(),
        TextButton(
          onPressed: _pageIndex > 0 && !_isLoading ? _prevPage : null,
          child: Text(
            '이전',
            style: TextStyle(
              color: _pageIndex > 0 ? AdminColors.gold : AdminColors.muted,
            ),
          ),
        ),
        TextButton(
          onPressed: (page?.hasMore ?? false) && !_isLoading ? _nextPage : null,
          child: Text(
            '다음',
            style: TextStyle(
              color: (page?.hasMore ?? false)
                  ? AdminColors.gold
                  : AdminColors.muted,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _UserCell extends StatelessWidget {
  final String displayName;
  final String uid;

  const _UserCell({required this.displayName, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName.isEmpty ? '(이름 없음)' : displayName,
          style: TextStyle(color: AdminColors.ivory, fontSize: 13),
        ),
        Text(uid, style: TextStyle(color: AdminColors.muted, fontSize: 10.5)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final bool danger;

  const _StatusPill({required this.text, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: danger ? AdminColors.statusDraftBg : AdminColors.badgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: danger ? AdminColors.statusDraftText : AdminColors.gold,
        ),
      ),
    );
  }
}
