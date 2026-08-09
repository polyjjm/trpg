/// 노드에 걸려 있는 승인 대기 작업. null이면 대기 중인 작업이 없다는 뜻.
enum PendingAction { create, edit, delete }

extension PendingActionJson on PendingAction {
  String get wireValue => name;
}

PendingAction? pendingActionFromWire(String? value) {
  if (value == null) return null;
  for (final action in PendingAction.values) {
    if (action.name == value) return action;
  }
  return null;
}
