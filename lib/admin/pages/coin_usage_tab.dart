import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/admin_story_repository.dart';
import '../data/billing_repository.dart';
import '../data/pack_bundle_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/pack_bundle.dart';
import '../models/wallet_transaction.dart';
import '../widgets/admin_theme.dart';
import 'billing_filter_bar.dart';

/// "코인사용내역" 탭 — collectionGroup('transactions')의 type == 'purchase'만.
/// 환불 정책이 "미사용 코인 충전 환불"만 다루므로(코인을 써서 이미 소유한
/// 팩은 환불 대상이 아니다), 이 탭에는 환불 액션이 없다.
class CoinUsageTab extends StatefulWidget {
  final AdminBillingRepository repository;
  final AdminStoryRepository storyRepository;
  final AdminPackBundleRepository bundleRepository;

  const CoinUsageTab({
    super.key,
    required this.repository,
    required this.storyRepository,
    required this.bundleRepository,
  });

  @override
  State<CoinUsageTab> createState() => _CoinUsageTabState();
}

class _CoinUsageTabState extends State<CoinUsageTab> {
  late final Stream<List<AdminStoryPack>> _packsStream = widget.storyRepository.watchPacks();
  late final Stream<List<AdminPackBundle>> _bundlesStream = widget.bundleRepository.watchAllBundles();

  AdminBillingFilter _filter = AdminBillingFilter.empty;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _cursorStack = [null];
  int _pageIndex = 0;

  BillingPage<AdminPurchaseTransaction>? _page;
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
      final page = await widget.repository.fetchPurchases(
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
    return StreamBuilder<List<AdminStoryPack>>(
      stream: _packsStream,
      builder: (context, packsSnapshot) {
        final packTitleById = {
          for (final p in packsSnapshot.data ?? const <AdminStoryPack>[]) p.id: p.title,
        };
        return StreamBuilder<List<AdminPackBundle>>(
          stream: _bundlesStream,
          builder: (context, bundlesSnapshot) {
            final bundleNameById = {
              for (final b in bundlesSnapshot.data ?? const <AdminPackBundle>[]) b.id: b.name,
            };

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BillingFilterBar(onApply: _applyFilter),
                  const SizedBox(height: 16),
                  Expanded(child: _buildBody(packTitleById, bundleNameById)),
                  const SizedBox(height: 12),
                  _buildPager(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(Map<String, String> packTitleById, Map<String, String> bundleNameById) {
    if (_loadError != null) {
      return SelectableText(
        '코인사용내역을 불러오지 못했어요: $_loadError',
        style: const TextStyle(fontSize: 12, color: AdminColors.danger),
      );
    }
    if (_isLoading && _page == null) {
      return Center(child: Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted)));
    }
    final items = _page?.items ?? const <AdminPurchaseTransaction>[];
    if (items.isEmpty) {
      return Center(
        child: Text('조건에 맞는 사용내역이 없어요.', style: TextStyle(fontSize: 13, color: AdminColors.muted)),
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
            DataColumn(label: Text('구매 항목')),
            DataColumn(label: Text('구분')),
            DataColumn(label: Text('사용 코인')),
          ],
          rows: [
            for (final tx in items)
              DataRow(
                cells: [
                  DataCell(Text(_formatDate(tx.createdAt))),
                  DataCell(_UserCell(displayName: tx.displayName, uid: tx.uid)),
                  DataCell(_buildItemLabel(tx, packTitleById, bundleNameById)),
                  DataCell(
                    _StatusPill(text: tx.isBundle ? '번들' : '개별 팩', accent: tx.isBundle),
                  ),
                  DataCell(Text('${tx.coins}')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemLabel(
    AdminPurchaseTransaction tx,
    Map<String, String> packTitleById,
    Map<String, String> bundleNameById,
  ) {
    if (tx.isBundle) {
      final bundleName = bundleNameById[tx.bundleId] ?? '(삭제된 번들)';
      final includedTitles = tx.bundlePackIds.map((id) => packTitleById[id] ?? id).join(', ');
      return SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bundleName, style: TextStyle(color: AdminColors.ivory, fontSize: 13)),
            if (includedTitles.isNotEmpty)
              Text(
                includedTitles,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AdminColors.muted, fontSize: 10.5),
              ),
          ],
        ),
      );
    }
    final title = packTitleById[tx.packId] ?? tx.packId ?? '(삭제된 팩)';
    return Text(title, style: TextStyle(color: AdminColors.ivory, fontSize: 13));
  }

  Widget _buildPager() {
    final page = _page;
    return Row(
      children: [
        Text('페이지 ${_pageIndex + 1}', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
        const Spacer(),
        TextButton(
          onPressed: _pageIndex > 0 && !_isLoading ? _prevPage : null,
          child: Text('이전', style: TextStyle(color: _pageIndex > 0 ? AdminColors.gold : AdminColors.muted)),
        ),
        TextButton(
          onPressed: (page?.hasMore ?? false) && !_isLoading ? _nextPage : null,
          child: Text(
            '다음',
            style: TextStyle(color: (page?.hasMore ?? false) ? AdminColors.gold : AdminColors.muted),
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
        Text(displayName.isEmpty ? '(이름 없음)' : displayName, style: TextStyle(color: AdminColors.ivory, fontSize: 13)),
        Text(uid, style: TextStyle(color: AdminColors.muted, fontSize: 10.5)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final bool accent;

  const _StatusPill({required this.text, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? AdminColors.imageCategoryChoiceBg : AdminColors.badgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, color: accent ? AdminColors.imageCategoryChoiceText : AdminColors.gold),
      ),
    );
  }
}
