import '../models/item_effect_type.dart';
import '../models/item_model.dart';

/// 아이템 id → [ItemModel] 카탈로그.
/// battle_configs.dart의 드랍 테이블, 인벤토리 화면, 전투 내 아이템 사용 등
/// 아이템 id를 참조하는 모든 곳이 이 맵을 단일 출처로 사용한다.
final Map<String, ItemModel> itemCatalog = {
  'bandage_01': const ItemModel(
    id: 'bandage_01',
    name: '붕대',
    effectType: ItemEffectType.heal,
    value: 10,
    battleUsable: true,
  ),
  'food_01': const ItemModel(
    id: 'food_01',
    name: '통조림',
    effectType: ItemEffectType.heal,
    value: 5,
    battleUsable: true,
  ),
  'knife_01': const ItemModel(
    id: 'knife_01',
    name: '칼',
    effectType: ItemEffectType.buff,
    value: 3,
    battleUsable: false,
  ),
};
