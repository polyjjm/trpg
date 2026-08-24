import 'package:flutter/material.dart';

import '../../../core/state/game_state_scope.dart';
import '../models/pack_bundle.dart';
import '../models/story_pack.dart';
import 'bundle_purchase_flow.dart';

const Color _ivory = Color(0xFFE7E2DA);
const Color _muted = Color(0xFF8E8A84);
const Color _orange = Color(0xFFF47A2A);
const Color _orangeSoft = Color(0x33F47A2A);
const Color _green = Color(0xFF67B97A);

/// 홈 번들 캐러셀과 상세 화면에서 공용으로 쓰는 현대적인 가로형 번들 카드.
/// 번들이 여러 개여도 한 화면에 2~3개가 자연스럽게 보이고, 포함 작품 표지를
/// 최대 세 장까지 나란히 보여줘 카드 하나만 봐도 구성품을 바로 이해할 수 있다.
class BundleCard extends StatelessWidget {
  final PackBundle bundle;
  final List<StoryPack> allPacks;

  const BundleCard({super.key, required this.bundle, required this.allPacks});

  @override
  Widget build(BuildContext context) {
    final ownedPackIds = GameStateScope.of(context).ownedPackIds;
    final included = allPacks.where((p) => bundle.packIds.contains(p.id)).toList();
    final ownedCount = bundle.ownedCountAmong(ownedPackIds);
    final totalCount = bundle.packIds.length;
    final canPurchase = bundle.canPurchaseGiven(ownedPackIds);
    final amountToCharge = bundle.amountToChargeFor(ownedPackIds);
    final hasDiscount = bundle.hasActiveDiscount;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showBundlePurchaseDialog(
        context,
        bundle: bundle,
        allPacks: allPacks,
      ),
      child: Container(
        width: 430,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.09)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF151515), Color(0xFF0E0E0E)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _orangeSoft,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: _orange.withOpacity(0.30)),
                    ),
                    child: const Text(
                      'BUNDLE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                        color: _orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    bundle.name.isEmpty ? '번들 상품' : bundle.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ivory,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '스토리 $totalCount개 포함',
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                  const Spacer(),
                  if (!canPurchase)
                    const Text(
                      '이미 전부 보유 중이에요',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _green,
                      ),
                    )
                  else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$amountToCharge코인',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _orange,
                          ),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '${bundle.price}코인',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_discountPercent(bundle)}% 할인',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _orange,
                          ),
                        ),
                      ),
                    ],
                    if (ownedCount > 0) ...[
                      const SizedBox(height: 5),
                      Text(
                        '이미 $ownedCount개 보유 · 차액만 결제',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: _muted),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            _CoverStrip(
              coverUrls: included.map((p) => p.coverImageUrl).toList(),
            ),
          ],
        ),
      ),
    );
  }

  static int _discountPercent(PackBundle bundle) {
    if (bundle.price <= 0 || bundle.salePrice == null) return 0;
    return (((bundle.price - bundle.salePrice!) / bundle.price) * 100)
        .round()
        .clamp(0, 100);
  }
}

/// 포함 작품을 최대 세 장까지 나란히 보여준다.
class _CoverStrip extends StatelessWidget {
  final List<String?> coverUrls;

  const _CoverStrip({required this.coverUrls});

  @override
  Widget build(BuildContext context) {
    final shown = coverUrls.take(3).toList();
    if (shown.isEmpty) shown.add(null);

    return SizedBox(
      width: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            SizedBox(
              width: shown.length == 1 ? 72 : 44,
              height: 92,
              child: _CoverThumb(url: shown[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final String? url;

  const _CoverThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: url != null && url!.isNotEmpty
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _CoverThumbFallback(),
              )
            : const _CoverThumbFallback(),
      ),
    );
  }
}

class _CoverThumbFallback extends StatelessWidget {
  const _CoverThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF47A2A), Color(0xFFB54818)],
        ),
      ),
      child: Center(
        child: Icon(Icons.auto_stories_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
