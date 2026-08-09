import '../models/barter_offer.dart';

/// 상인과의 물물교환 표.
/// giveItemId를 건네면 receiveItemId를 하나 받는다. 아이템 id는
/// lib/features/battle/inventory/data/item_catalog.dart의 카탈로그와 동일한 것을 쓴다.
/// 한 아이템은 하나의 교환처만 갖는다(giveItemId 기준으로 첫 항목만 사용).
final List<BarterOffer> barterOffers = [
  // 통조림(체력 회복 5) → 붕대(체력 회복 10): 상인 쪽이 손해를 보는 척, 실제로는 통조림이
  // 더 흔하다는 설정이라 플레이어에게 이득인 교환.
  BarterOffer(giveItemId: 'food_01', receiveItemId: 'bandage_01'),
  // 붕대 → 칼: 소모품을 포기하고 장비를 얻는 교환.
  BarterOffer(giveItemId: 'bandage_01', receiveItemId: 'knife_01'),
];
