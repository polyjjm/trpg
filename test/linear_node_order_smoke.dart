// Firebase/Flutter-free checks: dart test/linear_node_order_smoke.dart
import 'dart:convert';
import '../lib/admin/data/linear_node_order.dart';
import '../lib/admin/data/node_id_suggestion.dart';

void main() {
  var checks = 0;
  void check(bool value, String message) {
    if (!value) throw StateError(message);
    checks++;
  }

  final original = ['A', 'B', 'C'];
  final moved = linearNodePositions(reorderLinearNodeIds(original, 2, 0));
  check(moved.map((n) => n.id).join(',') == 'C,A,B', 'C,A,B order');
  check(moved.map((n) => n.nextNodeId).join(',') == 'A,B,null', 'C→A→B→null');
  check(original.join(',') == 'A,B,C', 'input unchanged');
  for (var old = 0; old < 3; old++) {
    for (var target = 0; target <= 3; target++) {
      check(
        diagnoseLinearNodeOrder(
          linearNodePositions(reorderLinearNodeIds(original, old, target)),
        ).isEmpty,
        'move $old → $target',
      );
    }
  }
  final saved = linearNodePositions(['A']);
  var cache = <LinearNodePosition>[];
  for (var i = 0; i < 3; i++) {
    final ids = mergeLinearNodeOrder(saved, cache).map((n) => n.id).toList();
    cache = linearNodePositions([
      ...ids,
      suggestSequentialNodeIds(ids, 1).first,
    ]);
    check(
      cache.length == i + 2 && diagnoseLinearNodeOrder(cache).isEmpty,
      'unsaved addition $i',
    );
  }
  final json =
      jsonDecode(
            jsonEncode([
              for (final n in cache)
                {'id': n.id, 'order': n.order, 'nextNodeId': n.nextNodeId},
            ]),
          )
          as List;
  final reopened = mergeLinearNodeOrder([
    for (final n in json.reversed)
      (
        id: n['id'] as String,
        order: n['order'] as int,
        nextNodeId: n['nextNodeId'] as String?,
      ),
  ], const []);
  check(reopened.toString() == cache.toString(), 'serialization/reopen order');
  check(diagnoseLinearNodeOrder(reopened).isEmpty, 'reopen chain');
  check(
    mergeLinearNodeOrder(linearNodePositions(original), moved).toString() ==
        moved.toString(),
    'cache overrides saved',
  );
  final issues = diagnoseLinearNodeOrder([
    (id: 'A', order: 0, nextNodeId: 'missing'),
    (id: 'B', order: 0, nextNodeId: 'C'),
    (id: 'C', order: 2, nextNodeId: 'B'),
  ]).join();
  for (final message in ['없는 다음 노드', '순환 연결', '고아 노드', '중복 순서', '불일치']) {
    check(issues.contains(message), message);
  }
  check(diagnoseLinearNodeOrder([]).isEmpty, 'empty story');
  check(
    diagnoseLinearNodeOrder(linearNodePositions(['A'])).isEmpty,
    'single node',
  );
  for (final invalid in [
    ['A', 'A'],
    [''],
  ]) {
    var rejected = false;
    try {
      linearNodePositions(invalid);
    } on ArgumentError {
      rejected = true;
    }
    check(rejected, 'invalid IDs');
  }
  print('PASS: $checks checks (no Flutter or Firebase)');
}
