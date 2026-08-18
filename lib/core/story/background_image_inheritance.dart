/// 노드가 배경 이미지를 명시적으로 고르지 않았을 때 실제로 보여줄 값을
/// 계산한다 — order 오름차순 상 targetOrder보다 앞선 노드 중, 명시적
/// backgroundImage를 가진 "가장 최근" 것을 찾는다. 그런 노드가 없으면
/// [packDefaultBackgroundImage]로 폴백한다.
///
/// 읽기 시점(read-time) 계산이다 — 값을 어딘가에 저장해 두지 않고 필요할
/// 때마다 다시 계산한다. 작가가 노드 순서를 바꾸거나 앞쪽 노드의 배경을
/// 나중에 바꿔도, 그 뒤를 잇는 모든 노드가 굳이 다시 저장되지 않아도 자동으로
/// 새 값을 반영하게 하려는 의도다(쓰기 시점에 값을 확정해 버리면, 나중에
/// 앞쪽 노드를 고쳐도 이미 저장된 뒤쪽 노드들은 낡은 값을 계속 들고 있게 되어
/// "다시 고르지 않아도 이어진다"는 기능의 취지 자체가 깨진다).
///
/// 작가 편집기(NodeEditor의 인계 안내 문구)와 리더(Task 3/4에서 노드를 렌더링할
/// 때)가 같은 규칙을 공유한다.
///
/// order가 같은 노드가 여럿이면(작가가 순서를 안 챙긴 경우) 어느 쪽이
/// "앞선" 노드인지는 정의하지 않는다 — 입력 리스트의 순서를 그대로 따른다.
///
/// [backgroundAppliesForward]가 false인 노드(편집기의 "이후 노드부터 배경이
/// 바뀔 때까지 자동으로 이어서 적용" 체크 해제)는 자기 자신에게만 배경을
/// 적용하고 인계 체인에는 아무 영향을 주지 않는다 — 즉 그 노드는 체인 계산에서
/// 있으나 없으나 마찬가지로 취급되고, 그 앞에서 이어져 오던 값(또는 그런 값이
/// 없었으면 팩 기본값)이 그 노드를 건너뛰어 그대로 이어진다.
String? resolveInheritedBackgroundImage({
  required Iterable<({int order, String? backgroundImage, bool backgroundAppliesForward})> nodes,
  required int targetOrder,
  required String? packDefaultBackgroundImage,
}) {
  final earlierNodes = nodes.where((n) => n.order < targetOrder).toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  String? active = packDefaultBackgroundImage;
  for (final node in earlierNodes) {
    if (node.backgroundImage == null) continue;
    if (node.backgroundAppliesForward) active = node.backgroundImage;
    // backgroundAppliesForward == false면 이 노드는 건너뛴다 — active를
    // 바꾸지 않아 그 앞까지 이어져 오던 값이 그대로 유지된다.
  }
  return active;
}
