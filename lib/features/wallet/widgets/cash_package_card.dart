import 'package:flutter/material.dart';

import '../../../core/monetization/cash_package.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 천 단위 콤마가 들어간 원화 표기. 예: 11000 -> '11,000'.
String formatWon(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 충전 화면에 표시되는 캐시 패키지 카드.
class CashPackageCard extends StatelessWidget {
  final CashPackage package;
  final VoidCallback onTap;

  const CashPackageCard({
    super.key,
    required this.package,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBonus = package.bonusCashAmount > 0;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _gold.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monetization_on_rounded, color: _gold, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${package.totalCashAmount}캐시',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ivory,
                    ),
                  ),
                  if (hasBonus) ...[
                    const SizedBox(height: 2),
                    Text(
                      '기본 ${package.cashAmount} + 보너스 ${package.bonusCashAmount}',
                      style: TextStyle(fontSize: 12, color: _gold.withOpacity(0.85)),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '₩${formatWon(package.priceWon)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
