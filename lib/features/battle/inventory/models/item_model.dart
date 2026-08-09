import 'item_effect_type.dart';

class ItemModel {
  final String id;
  final String name;
  final ItemEffectType effectType;
  final int value;
  final bool battleUsable;

  const ItemModel({
    required this.id,
    required this.name,
    required this.effectType,
    required this.value,
    required this.battleUsable,
  });
}

/// 아이템 효과를 사람이 읽을 수 있는 설명 문구로 변환한다.
/// 인벤토리 화면·전투 아이템 선택창 등 여러 곳에서 공용으로 사용한다.
extension ItemModelDescription on ItemModel {
  String get description {
    switch (effectType) {
      case ItemEffectType.heal:
        return '체력을 $value 회복한다.';
      case ItemEffectType.damage:
        return '적에게 $value의 피해를 입힌다.';
      case ItemEffectType.buff:
        return '전투 중 능력치를 일시적으로 강화한다.';
      case ItemEffectType.escapeBoost:
        return '도망 성공 확률을 높인다.';
    }
  }
}