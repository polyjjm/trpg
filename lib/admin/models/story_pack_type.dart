/// storyPacks/{packId}.type — 생성 시 한 번 정해지고 이후 바뀌지 않는다.
/// 인터랙티브(노드 그래프)와 선형(챕터 순서) 두 타입은 하위 콘텐츠 구조 자체가
/// 달라서, 도중에 바꾸면 이미 만든 콘텐츠가 갈 곳을 잃는다.
enum StoryPackType { interactive, linear }

extension StoryPackTypeJson on StoryPackType {
  String get wireValue => name;

  static StoryPackType fromWire(String? value) {
    return StoryPackType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => StoryPackType.interactive,
    );
  }
}
