/// move + random 모드 선택지의 후보 노드 하나 — 확률(pct, 0~100 정수)로 가중된다.
/// 같은 선택지 안의 모든 후보 pct 합은 저장 시점에 100이어야 한다.
class RandomMoveCandidate {
  String node;
  int pct;

  RandomMoveCandidate({this.node = '', this.pct = 0});

  factory RandomMoveCandidate.fromJson(Map<String, dynamic> json) {
    return RandomMoveCandidate(
      node: json['node'] as String? ?? '',
      pct: (json['pct'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'node': node, 'pct': pct};
}
