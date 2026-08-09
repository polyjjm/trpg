import 'package:flutter/material.dart';

import '../../../core/monetization/cash_package.dart';
import '../../../core/monetization/monetization_service.dart';
import '../../../core/monetization/no_op_monetization_service.dart';
import '../../../core/state/game_state_scope.dart';
import '../data/cash_packages.dart';
import '../widgets/cash_package_card.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 캐시 충전 화면. 실제 결제 SDK가 붙기 전까지 [NoOpMonetizationService]를 통해
/// 구매를 시도하며, 항상 실패로 처리된다 — 성공 분기는 SDK 연동 시 그대로 동작하도록
/// 미리 작성해 두었다.
class ChargePage extends StatelessWidget {
  const ChargePage({super.key});

  static const MonetizationService _monetizationService = NoOpMonetizationService();

  @override
  Widget build(BuildContext context) {
    final gameState = GameStateScope.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '캐시 충전',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _ivory,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildBalanceCard(gameState.cashBalance),
              const SizedBox(height: 26),
              const Text(
                '충전 상품',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: cashPackages.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final package = cashPackages[index];
                    return CashPackageCard(
                      package: package,
                      onTap: () => _handlePurchase(context, package),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(int cashBalance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on_rounded, color: _gold, size: 26),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '보유 캐시',
                style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.70)),
              ),
              const SizedBox(height: 2),
              Text(
                '$cashBalance캐시',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handlePurchase(BuildContext context, CashPackage package) async {
    final gameState = GameStateScope.of(context);
    final result = await _monetizationService.purchaseCashPackage(package);

    if (!context.mounted) return;

    if (result == CashPurchaseResult.success) {
      gameState.addCash(package.totalCashAmount);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${package.totalCashAmount}캐시가 충전되었습니다.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('결제 시스템은 준비 중입니다')),
    );
  }
}
