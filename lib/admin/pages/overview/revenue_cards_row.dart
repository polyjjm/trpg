import 'package:flutter/material.dart';

import '../../data/billing_repository.dart';
import '../../data/overview_revenue.dart';
import '../../widgets/admin_theme.dart';
import 'admin_card_grid.dart';

/// 개요의 매출 카드 행 — 숫자 카드(코랄)보다 한 단계 낮은 위계로,
/// panel2 배경 + ivory 숫자를 쓴다(목업과 동일). 값은 전부 기존
/// revenueSnapshots 문서에서 나오므로 새 집계가 필요 없다.
///
/// 스트림이 아니라 [Future]다 — revenueSnapshots는 하루에 한 번만 바뀌므로
/// 화면을 열 때 한 번 읽으면 충분하다(실시간 구독은 읽기 비용만 늘린다).
class RevenueCardsRow extends StatefulWidget {
  final AdminBillingRepository billingRepository;

  const RevenueCardsRow({super.key, required this.billingRepository});

  @override
  State<RevenueCardsRow> createState() => _RevenueCardsRowState();
}

class _RevenueCardsRowState extends State<RevenueCardsRow> {
  /// build()마다 새로 부르면 FutureBuilder가 매번 로딩으로 되돌아간다 —
  /// 다른 탭들이 스트림을 State에 한 번만 만드는 것과 같은 이유.
  late final Future<OverviewRevenue> _future = widget.billingRepository
      .fetchOverviewRevenue();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OverviewRevenue>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SelectableText(
            '매출 요약을 불러오지 못했어요: ${snapshot.error}',
            style: const TextStyle(fontSize: 12, color: AdminColors.danger),
          );
        }

        final data = snapshot.data;
        final yesterday = data?.yesterday;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminCardGrid(
              children: [
                _RevenueCard(
                  label: '최근 7일 결제액',
                  value: data == null ? null : _won(data.weekRevenueKRW),
                ),
                _RevenueCard(
                  label: '어제 소비 포인트',
                  value: yesterday == null ? null : _num(yesterday.coinsSpent),
                ),
                _RevenueCard(
                  label: '어제 환불액',
                  value: yesterday == null ? null : _won(yesterday.refundedKRW),
                ),
                _RevenueCard(
                  label: '어제 결제 건수',
                  value: yesterday == null
                      ? null
                      : '${_num(yesterday.chargeCount)}건',
                ),
              ],
            ),
            if (data != null && yesterday == null) ...[
              const SizedBox(height: 8),
              Text(
                '어제 집계는 매일 0시 20분(KST)에 만들어져요. 아직 없으면 잠시 후 다시 확인해 주세요.',
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final String label;

  /// null이면 아직 로딩 중이거나 집계 전 — MetricCard와 같은 규칙으로 '-'.
  final String? value;

  const _RevenueCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value ?? '-',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AdminColors.ivory,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: AdminColors.muted)),
        ],
      ),
    );
  }
}

String _num(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _won(int value) => '₩${_num(value)}';
