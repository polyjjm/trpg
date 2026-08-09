/// type이 move인 선택지가 다음 노드를 고정으로 지정하는지, 확률 가중 랜덤으로
/// 여러 후보 중 고르는지.
enum MoveMode { fixed, random }

extension MoveModeJson on MoveMode {
  String get wireValue => name;

  static MoveMode fromWire(String? value) {
    return MoveMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => MoveMode.fixed,
    );
  }
}
