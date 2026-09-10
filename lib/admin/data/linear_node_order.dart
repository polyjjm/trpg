/// A display-order snapshot, independent of Flutter and persistence.
typedef LinearNodePosition = ({String id, int order, String? nextNodeId});

/// Cached entries override saved entries, including their position and edges.
List<LinearNodePosition> mergeLinearNodeOrder(
  Iterable<LinearNodePosition> saved,
  Iterable<LinearNodePosition> cached,
) {
  final byId = {for (final node in saved) node.id: node};
  for (final node in cached) {
    byId[node.id] = node;
  }
  return byId.values.toList()..sort((a, b) {
    final order = a.order.compareTo(b.order);
    return order != 0 ? order : a.id.compareTo(b.id);
  });
}

/// The supplied display order is the only source of both persisted fields.
List<LinearNodePosition> linearNodePositions(List<String> ids) {
  if (ids.toSet().length != ids.length || ids.any((id) => id.isEmpty)) {
    throw ArgumentError('Node IDs must be nonempty and unique.');
  }
  return [
    for (var i = 0; i < ids.length; i++)
      (
        id: ids[i],
        order: i,
        nextNodeId: i + 1 < ids.length ? ids[i + 1] : null,
      ),
  ];
}

/// Uses ReorderableListView's insertion index convention without mutating input.
List<String> reorderLinearNodeIds(
  List<String> ids,
  int oldIndex,
  int newIndex,
) {
  final result = List<String>.of(ids);
  if (oldIndex < newIndex) newIndex--;
  result.insert(newIndex, result.removeAt(oldIndex));
  return result;
}

/// Diagnostics never repair existing documents implicitly.
List<String> diagnoseLinearNodeOrder(List<LinearNodePosition> displayed) {
  final problems = <String>[];
  final byId = {for (final n in displayed) n.id: n};
  final orders = <int>{};
  for (var i = 0; i < displayed.length; i++) {
    final n = displayed[i];
    if (!orders.add(n.order)) problems.add('${n.id}: 중복 순서 ${n.order}');
    final expected = i + 1 < displayed.length ? displayed[i + 1].id : null;
    if (n.order != i || n.nextNodeId != expected) {
      problems.add('${n.id}: 표시 순서와 order/nextNodeId 불일치');
    }
    if (n.nextNodeId != null && !byId.containsKey(n.nextNodeId)) {
      problems.add('${n.id}: 없는 다음 노드 ${n.nextNodeId}');
    }
  }
  final checked = <String>{};
  for (final start in displayed) {
    final path = <String>{};
    String? id = start.id;
    while (id != null && byId.containsKey(id) && !checked.contains(id)) {
      if (!path.add(id)) {
        problems.add('$id: 순환 연결');
        break;
      }
      id = byId[id]!.nextNodeId;
    }
    checked.addAll(path);
  }
  final reachable = <String>{};
  String? id = displayed.isEmpty ? null : displayed.first.id;
  while (id != null && byId.containsKey(id) && reachable.add(id)) {
    id = byId[id]!.nextNodeId;
  }
  for (final n in displayed) {
    if (!reachable.contains(n.id)) problems.add('${n.id}: 시작점에서 도달 불가 (고아 노드)');
  }
  return problems;
}
