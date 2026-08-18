/// StoryNode.blocks 원소 하나의 종류.
enum NodeBlockType { paragraph, beat, image }

extension NodeBlockTypeJson on NodeBlockType {
  String get wireValue => name;

  static NodeBlockType fromWire(String? value) {
    return NodeBlockType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => NodeBlockType.paragraph,
    );
  }
}
