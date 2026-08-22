import 'package:flutter/material.dart';

import '../data/admin_story_repository.dart';
import '../data/billing_repository.dart';
import '../data/pack_bundle_repository.dart';
import '../data/point_package_repository.dart';
import '../widgets/admin_theme.dart';
import 'coin_usage_tab.dart';
import 'payment_history_tab.dart';
import 'settlement_tab.dart';

/// "결제·정산 관리" — 결제내역/코인사용내역/정산내역 세 탭을 하나의
/// 화면으로 묶는다. 예전엔 사이드바에 "결제 내역"과 "매출 대시보드"가
/// 서로 다른 placeholder 항목으로 따로 있었는데, 실제로 만들고 보니 셋
/// 다(결제·사용·정산) 같은 데이터 원천(collectionGroup('transactions')/
/// revenueSnapshots)을 다른 각도로 보여주는 한 화면이라 자연스럽게
/// 합쳤다 — "매출 대시보드" 항목은 이 화면의 정산내역 탭으로 흡수됐다.
class BillingDashboardSection extends StatefulWidget {
  final AdminBillingRepository billingRepository;
  final AdminPointPackageRepository pointPackageRepository;
  final AdminStoryRepository storyRepository;
  final AdminPackBundleRepository bundleRepository;

  const BillingDashboardSection({
    super.key,
    required this.billingRepository,
    required this.pointPackageRepository,
    required this.storyRepository,
    required this.bundleRepository,
  });

  @override
  State<BillingDashboardSection> createState() => _BillingDashboardSectionState();
}

class _BillingDashboardSectionState extends State<BillingDashboardSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Text(
            '결제·정산 관리',
            style: TextStyle(fontSize: 16, color: AdminColors.ivory, fontWeight: FontWeight.w700),
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AdminColors.gold,
          unselectedLabelColor: AdminColors.muted,
          indicatorColor: AdminColors.gold,
          tabs: const [
            Tab(text: '결제내역'),
            Tab(text: '코인사용내역'),
            Tab(text: '정산내역'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              PaymentHistoryTab(
                repository: widget.billingRepository,
                pointPackageRepository: widget.pointPackageRepository,
              ),
              CoinUsageTab(
                repository: widget.billingRepository,
                storyRepository: widget.storyRepository,
                bundleRepository: widget.bundleRepository,
              ),
              SettlementTab(repository: widget.billingRepository),
            ],
          ),
        ),
      ],
    );
  }
}
