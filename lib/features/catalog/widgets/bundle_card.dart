import 'package:flutter/material.dart';

import '../../../core/state/game_state_scope.dart';
import '../models/pack_bundle.dart';
import '../models/story_pack.dart';
import 'bundle_purchase_flow.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);
const Color _coral = Color(0xFFE2703A);

/// 홈 탭 "번들 상품" 섹션과 스토리팩 상세 화면의 "이 팩이 포함된 번들"이
/// 공유하는 카드 — PointPackageCard와 같은 시각 언어(할인 중이면 정가에
/// 취소선 + 할인가 + 할인율 배지)를 코인 가격 번들에 맞춰 쓴다. 이미 일부
/// 팩을 보유 중이면 "이미 N개 보유 — X코인만 더 내면돼요"를 보여준다 —
/// 실제 청구액의 유일한 원천은 서버(purchaseBundle Cloud Function)지만,
/// [PackBundle.amountToChargeFor]가 정확히 같은 계산을 미리 보여준다.
class BundleCard extends StatelessWidget {
  final PackBundle bundle;

  /// 포함된 팩의 표지/제목을 다시 조회하지 않고, 호출부가 이미 구독 중인
  /// 전체 팩 목록에서 바로 찾아 쓴다(HeroBannerSection의 allPacks와 같은
  /// 패턴).
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
      borderRadius: BorderRadius.circular(14),
      onTap: () => showBundlePurchaseDialog(context, bundle: bundle, allPacks: allPacks),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _gold.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverStack(coverUrls: included.map((p) => p.coverImageUrl).toList()),
            const SizedBox(height: 10),
            Text(
              bundle.name.isEmpty ? '번들 상품' : bundle.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ivory),
            ),
            const SizedBox(height: 2),
            Text(
              '팩 $totalCount개 포함',
              style: TextStyle(fontSize: 11.5, color: _ivory.withOpacity(0.6)),
            ),
            const SizedBox(height: 8),
            if (!canPurchase)
              Text(
                '이미 전부 보유 중이에요',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF3FA66B)),
              )
            else ...[
              if (hasDiscount)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _coral, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '${_discountPercent(bundle)}%',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${bundle.price}코인',
                      style: TextStyle(
                        fontSize: 11,
                        color: _ivory.withOpacity(0.45),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
              if (hasDiscount) const SizedBox(height: 2),
              Text(
                '$amountToCharge코인',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _gold),
              ),
              if (ownedCount > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '이미 $ownedCount개 보유 — $amountToCharge코인만 더',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: _ivory.withOpacity(0.6)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static int _discountPercent(PackBundle bundle) {
    if (bundle.price <= 0 || bundle.salePrice == null) return 0;
    return (((bundle.price - bundle.salePrice!) / bundle.price) * 100).round().clamp(0, 100);
  }
}

/// 포함된 팩 표지를 최대 3장까지 겹쳐 보여준다 — 카드 하나에 팩 표지가
/// 여러 장 섞여 있다는 인상을 주는 용도라 개별 표지를 또렷이 보여줄
/// 필요는 없다.
class _CoverStack extends StatelessWidget {
  final List<String?> coverUrls;

  const _CoverStack({required this.coverUrls});

  // 고정 높이(AspectRatio 대신) — 카드 폭이 얼마든 이 섹션의 높이가 항상
  // 같아야 카드 전체 높이를 예측 가능하게 유지할 수 있다(호출부가 가로
  // 스크롤 행 높이를 고정값으로 주기 때문).
  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    final shown = coverUrls.take(3).toList();
    if (shown.isEmpty) {
      return const SizedBox(height: _height, child: _CoverThumb(url: null));
    }

    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 18.0,
              top: 0,
              bottom: 0,
              width: 60,
              child: _CoverThumb(url: shown[i]),
            ),
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black.withOpacity(0.4), width: 1.5),
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
      decoration: BoxDecoration(color: Color(0xFFE2703A)),
    );
  }
}
