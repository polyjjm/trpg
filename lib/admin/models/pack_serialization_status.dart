/// storyPacks/{packId}.serializationStatus — "이 팩이 독자 라이브러리에
/// 존재를 드러내도 되는가"를 가르는 1단계 승인. 개별 노드 콘텐츠 승인
/// (NodeStatus/PendingAction)과는 완전히 별개의, 더 위 단계의 게이트다.
enum PackSerializationStatus { draft, pending, approved, rejected }

extension PackSerializationStatusJson on PackSerializationStatus {
  String get wireValue => name;

  static PackSerializationStatus fromWire(String? value) {
    return PackSerializationStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => PackSerializationStatus.draft,
    );
  }
}
