import 'package:flutter/material.dart';

import '../data/billing_repository.dart';
import '../models/revenue_snapshot.dart';
import '../widgets/admin_theme.dart';

enum _RangePreset { last7Days, last30Days, thisMonth, custom }

/// "정산내역" 탭 — revenueSnapshots(일별 사전 집계)만 읽는다. 매일 KST
/// 00:20에 도는 computeDailyRevenueSnapshot이 "그 직전 하루"를 채우므로,
/// 오늘 날짜는 항상 비어 있는 게 정상이다(아래 안내 문구로 명시한다).
class SettlementTab extends StatefulWidget {
  final AdminBillingRepository repository;

  const SettlementTab({super.key, required this.repository});

  @override
  State<SettlementTab> createState() => _SettlementTabState();
}

class _SettlementTabState extends State<SettlementTab> {
  _RangePreset _preset = _RangePreset.last7Days;
  DateTime? _customStart;
  DateTime? _customEnd;

  List<AdminRevenueSnapshot>? _snapshots;
  bool _isLoading = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _RangePreset.last7Days:
        return (today.subtract(const Duration(days: 6)), today);
      case _RangePreset.last30Days:
        return (today.subtract(const Duration(days: 29)), today);
      case _RangePreset.thisMonth:
        return (DateTime(today.year, today.month, 1), today);
      case _RangePreset.custom:
        return (_customStart ?? today.subtract(const Duration(days: 6)), _customEnd ?? today);
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final (start, end) = _resolveRange();
      final snapshots = await widget.repository.fetchRevenueRange(start, end);
      if (!mounted) return;
      setState(() => _snapshots = snapshots);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: _customStart ?? now.subtract(const Duration(days: 6)),
        end: _customEnd ?? now,
      ),
    );
    if (picked == null) return;
    setState(() {
      _preset = _RangePreset.custom;
      _customStart = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _customEnd = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRangeSelector(),
          const SizedBox(height: 4),
          Text(
            '오늘 데이터는 다음날 새벽에 집계돼요 — 방금 지난 하루까지만 보여요.',
            style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
          ),
          const SizedBox(height: 20),
          if (_loadError != null)
            SelectableText(
              '정산 데이터를 불러오지 못했어요: $_loadError',
              style: const TextStyle(fontSize: 12, color: AdminColors.danger),
            )
          else if (_isLoading && _snapshots == null)
            Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted))
          else
            _buildContent(_snapshots ?? const []),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _PresetChip(
          label: '최근 7일',
          selected: _preset == _RangePreset.last7Days,
          onTap: () {
            setState(() => _preset = _RangePreset.last7Days);
            _load();
          },
        ),
        _PresetChip(
          label: '최근 30일',
          selected: _preset == _RangePreset.last30Days,
          onTap: () {
            setState(() => _preset = _RangePreset.last30Days);
            _load();
          },
        ),
        _PresetChip(
          label: '이번 달',
          selected: _preset == _RangePreset.thisMonth,
          onTap: () {
            setState(() => _preset = _RangePreset.thisMonth);
            _load();
          },
        ),
        _PresetChip(
          label: '직접 지정',
          selected: _preset == _RangePreset.custom,
          onTap: _pickCustomRange,
        ),
      ],
    );
  }

  Widget _buildContent(List<AdminRevenueSnapshot> snapshots) {
    final totalRevenue = snapshots.fold<int>(0, (sum, s) => sum + s.revenueKRW);
    final totalCharges = snapshots.fold<int>(0, (sum, s) => sum + s.chargeCount);
    final totalCoinsGranted = snapshots.fold<int>(0, (sum, s) => sum + s.coinsGranted);
    final totalCoinsSpent = snapshots.fold<int>(0, (sum, s) => sum + s.coinsSpent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(label: '기간 매출', value: '${_formatNumber(totalRevenue)}원'),
            _SummaryCard(label: '충전 건수', value: '${_formatNumber(totalCharges)}건'),
            _SummaryCard(label: '지급 코인', value: '${_formatNumber(totalCoinsGranted)}코인'),
            _SummaryCard(
              label: '코인 사용량',
              value: '${_formatNumber(totalCoinsSpent)}코인',
              caption: '매출과 별개 지표예요',
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (snapshots.isEmpty)
          Text('이 기간엔 집계된 데이터가 없어요.', style: TextStyle(fontSize: 13, color: AdminColors.muted))
        else ...[
          Text('일별 매출 vs 코인 사용량', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.ivory)),
          const SizedBox(height: 12),
          _DailyChart(snapshots: snapshots),
          const SizedBox(height: 24),
          Text('일별 상세', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.ivory)),
          const SizedBox(height: 12),
          _buildDailyTable(snapshots),
        ],
      ],
    );
  }

  Widget _buildDailyTable(List<AdminRevenueSnapshot> snapshots) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AdminColors.panel2),
        columns: const [
          DataColumn(label: Text('날짜')),
          DataColumn(label: Text('매출(KRW)')),
          DataColumn(label: Text('충전 건수')),
          DataColumn(label: Text('지급 코인')),
          DataColumn(label: Text('코인 사용량')),
          DataColumn(label: Text('환불(KRW)')),
        ],
        rows: [
          for (final s in snapshots.reversed)
            DataRow(cells: [
              DataCell(Text(s.dateKey)),
              DataCell(Text('${_formatNumber(s.revenueKRW)}원')),
              DataCell(Text('${s.chargeCount}')),
              DataCell(Text('${s.coinsGranted}')),
              DataCell(Text('${s.coinsSpent}')),
              DataCell(Text(s.refundedKRW > 0 ? '${_formatNumber(s.refundedKRW)}원' : '-')),
            ]),
        ],
      ),
    );
  }

  static String _formatNumber(int n) {
    final digits = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold.withOpacity(0.15) : AdminColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AdminColors.gold : AdminColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? AdminColors.gold : AdminColors.ivory,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;

  const _SummaryCard({required this.label, required this.value, this.caption});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: AdminColors.muted)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdminColors.ivory)),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: TextStyle(fontSize: 10, color: AdminColors.muted)),
          ],
        ],
      ),
    );
  }
}

/// 매출(KRW)과 코인 사용량을 나란히 그리는 막대 그래프 — 외부 차트
/// 패키지를 추가하는 대신(이 프로젝트에 차트 라이브러리 의존성이 아직
/// 없다) CustomPainter로 직접 그린다(TELO 로고 마크와 같은 접근).
/// 두 지표는 단위가 완전히 달라서(원화 vs 코인 개수) 절대값을 같은
/// 축에 놓고 비교하는 건 의미가 없다 — 각 계열을 자기 자신의 최댓값
/// 기준으로 정규화해서, "그날 상대적으로 얼마나 높았는지" 추세만
/// 비교하는 용도로 그린다(막대 높이를 계열 간 직접 비교하면 안 된다).
class _DailyChart extends StatelessWidget {
  final List<AdminRevenueSnapshot> snapshots;

  const _DailyChart({required this.snapshots});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: AdminColors.gold, label: '매출(KRW, 계열 내 상대값)'),
            const SizedBox(width: 16),
            _LegendDot(color: AdminColors.accent, label: '코인 사용량(계열 내 상대값)'),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: CustomPaint(
            painter: _DualBarChartPainter(
              revenue: snapshots.map((s) => s.revenueKRW).toList(),
              coinsSpent: snapshots.map((s) => s.coinsSpent).toList(),
              revenueColor: AdminColors.gold,
              coinsColor: AdminColors.accent,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(snapshots.first.dateKey, style: TextStyle(fontSize: 10, color: AdminColors.muted)),
            const Spacer(),
            Text(snapshots.last.dateKey, style: TextStyle(fontSize: 10, color: AdminColors.muted)),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: AdminColors.muted)),
      ],
    );
  }
}

class _DualBarChartPainter extends CustomPainter {
  final List<int> revenue;
  final List<int> coinsSpent;
  final Color revenueColor;
  final Color coinsColor;

  _DualBarChartPainter({
    required this.revenue,
    required this.coinsSpent,
    required this.revenueColor,
    required this.coinsColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = revenue.length;
    if (n == 0) return;

    final maxRevenue = revenue.fold<int>(0, (m, v) => v > m ? v : m);
    final maxCoins = coinsSpent.fold<int>(0, (m, v) => v > m ? v : m);

    final groupWidth = size.width / n;
    final barWidth = (groupWidth * 0.32).clamp(1.0, 18.0);
    final gap = (groupWidth * 0.06).clamp(1.0, 8.0);

    final revenuePaint = Paint()..color = revenueColor;
    final coinsPaint = Paint()..color = coinsColor;

    for (var i = 0; i < n; i++) {
      final groupLeft = groupWidth * i;
      final centerX = groupLeft + groupWidth / 2;

      final revenueHeight = maxRevenue == 0 ? 0.0 : (revenue[i] / maxRevenue) * size.height;
      final coinsHeight = maxCoins == 0 ? 0.0 : (coinsSpent[i] / maxCoins) * size.height;

      final revenueRect = Rect.fromLTWH(
        centerX - gap / 2 - barWidth,
        size.height - revenueHeight,
        barWidth,
        revenueHeight,
      );
      final coinsRect = Rect.fromLTWH(
        centerX + gap / 2,
        size.height - coinsHeight,
        barWidth,
        coinsHeight,
      );

      canvas.drawRect(revenueRect, revenuePaint);
      canvas.drawRect(coinsRect, coinsPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DualBarChartPainter oldDelegate) {
    return oldDelegate.revenue != revenue || oldDelegate.coinsSpent != coinsSpent;
  }
}
