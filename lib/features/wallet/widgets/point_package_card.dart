import 'package:flutter/material.dart';

import '../models/point_package.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);
const Color _coral = Color(0xFFFF6B4A);

/// 천 단위 콤마가 들어간 원화 표기. 예: 11000 -> '11,000'. 코인 상품(원화로
/// 결제)에서만 쓴다 — 이야기 팩 가격은 코인 단위라 이 포맷을 쓰지 않는다.
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

/// 충전 화면에 표시되는 코인 상품 카드 — 할인 중이면 정가에 취소선을 긋고
/// 할인가 + 할인율 배지를 보여주고, 보너스 코인이 있으면 별도 pill로
/// 강조한다. 탭하면 선택 상태가 되고([selected]), 선택된 카드만 테두리가
/// 골드로 강조된다 — 여러 카드 중 결제할 상품 하나를 고르는 화면이라
/// 라디오 버튼 대신 카드 자체를 selectable하게 만들었다.
class PointPackageCard extends StatelessWidget {
  final PointPackage package;
  final bool selected;
  final VoidCallback onTap;

  const PointPackageCard({
    super.key,
    required this.package,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = package.hasActiveDiscount;
    final hasBonus = package.bonusCoins > 0;
    final discountPercent = hasDiscount
        ? (((package.originalPriceKRW - package.salePriceKRW!) /
                      package.originalPriceKRW *
                      100)
                  .round())
              .clamp(0, 100)
        : 0;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _gold.withOpacity(0.10) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _gold : _gold.withOpacity(0.25),
            width: selected ? 1.5 : 1,
          ),
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
                  Row(
                    children: [
                      Text(
                        package.name.isEmpty ? '${package.coinAmount}코인' : package.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ivory,
                        ),
                      ),
                      if (hasBonus) ...[
                        const SizedBox(width: 8),
                        _BonusPill(bonusCoins: package.bonusCoins),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '코인 ${package.coinAmount}${hasBonus ? ' + 보너스 ${package.bonusCoins}' : ''}',
                    style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.65)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasDiscount) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _coral,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$discountPercent%',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '₩${formatWon(package.originalPriceKRW)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _ivory.withOpacity(0.45),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  '₩${formatWon(package.currentPriceKRW)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _gold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BonusPill extends StatelessWidget {
  final int bonusCoins;

  const _BonusPill({required this.bonusCoins});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withOpacity(0.4)),
      ),
      child: Text(
        '+$bonusCoins 보너스',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _gold),
      ),
    );
  }
}
