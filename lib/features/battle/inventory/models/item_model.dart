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