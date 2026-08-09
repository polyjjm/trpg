/// 선택지가 게임에서 실제로 트리거하는 동작 종류.
/// StoryChoice(lib/features/story/models/story_choice.dart)의 4가지 트리거
/// (battle/merchant/encounter/일반 이동) + 아이템 획득을 편집기에서 다루기 위한 대응 값.
enum ChoiceType { move, battle, encounter, merchant, item }

extension ChoiceTypeLabel on ChoiceType {
  String get label => switch (this) {
        ChoiceType.move => '단순 이동',
        ChoiceType.battle => '전투',
        ChoiceType.encounter => '돌발 조우',
        ChoiceType.merchant => '상인',
        ChoiceType.item => '아이템 획득',
      };

  String get wireValue => name;

  static ChoiceType fromWire(String? value) {
    return ChoiceType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => ChoiceType.move,
    );
  }
}
