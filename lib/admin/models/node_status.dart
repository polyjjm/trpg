/// 스토리 노드의 발행 상태.
enum NodeStatus { draft, published }

extension NodeStatusJson on NodeStatus {
  String get wireValue => name;

  static NodeStatus fromWire(String? value) {
    return NodeStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => NodeStatus.draft,
    );
  }
}
