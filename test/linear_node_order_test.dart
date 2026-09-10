import 'package:flutter_test/flutter_test.dart';
import 'package:sotry_trpg/admin/data/linear_node_order.dart';
import 'package:sotry_trpg/admin/data/node_edit_session_cache.dart';
import 'package:sotry_trpg/admin/data/node_id_suggestion.dart';
import 'package:sotry_trpg/admin/models/admin_story_node.dart';

void main() {
  test('C,A,B display order yields C→A→B→null without changing input', () {
    final original = ['A', 'B', 'C'];
    final ids = reorderLinearNodeIds(original, 2, 0);
    expect(original, ['A', 'B', 'C']);
    expect(linearNodePositions(ids), [
      (id: 'C', order: 0, nextNodeId: 'A'),
      (id: 'A', order: 1, nextNodeId: 'B'),
      (id: 'B', order: 2, nextNodeId: null),
    ]);
  });

  test(
    'moving first, middle, last and no-op positions preserves one chain',
    () {
      for (final move in [(0, 3), (1, 0), (2, 1), (1, 3), (0, 0), (1, 2)]) {
        final ids = reorderLinearNodeIds(['A', 'B', 'C'], move.$1, move.$2);
        final nodes = linearNodePositions(ids);
        expect(diagnoseLinearNodeOrder(nodes), isEmpty);
        expect(nodes.map((n) => n.id).toSet(), {'A', 'B', 'C'});
        expect(nodes.last.nextNodeId, isNull);
      }
    },
  );

  test(
    'three unsaved additions merge cache and survive serialization/reopen',
    () {
      final cache = NodeEditSessionCache();
      final saved = linearNodePositions(['A']);
      for (var i = 0; i < 3; i++) {
        final displayed = mergeLinearNodeOrder(saved, [
          for (final id in cache.nodeIdsForPack('pack'))
            (
              id: id,
              order: cache.get('pack', id)!.order,
              nextNodeId: cache.get('pack', id)!.nextNodeId,
            ),
        ]);
        final ids = displayed.map((n) => n.id).toList();
        ids.add(suggestSequentialNodeIds(ids, 1).first);
        for (final p in linearNodePositions(ids)) {
          final node = cache.get('pack', p.id) ?? AdminStoryNode(id: p.id);
          node.order = p.order;
          node.nextNodeId = p.nextNodeId;
          cache.put('pack', node);
        }
      }
      final documents = {
        for (final id in cache.nodeIdsForPack('pack'))
          id: cache.get('pack', id)!.toFirestoreJson(),
      };
      final reopened = [
        for (final entry in documents.entries)
          AdminStoryNode.fromFirestore(entry.key, entry.value),
      ];
      final displayed = mergeLinearNodeOrder([
        for (final n in reopened.reversed)
          (id: n.id, order: n.order, nextNodeId: n.nextNodeId),
      ], const []);
      expect(displayed, hasLength(4));
      expect(displayed.map((n) => n.id), cache.nodeIdsForPack('pack'));
      expect(diagnoseLinearNodeOrder(displayed), isEmpty);
      expect(cache.nodeIdsForPack('other-pack'), isEmpty);
    },
  );

  test(
    'cache overrides persisted order and links; equal order uses stable ID',
    () {
      expect(
        mergeLinearNodeOrder(
          linearNodePositions(['A', 'B', 'C']),
          linearNodePositions(['C', 'A', 'B']),
        ),
        linearNodePositions(['C', 'A', 'B']),
      );
      expect(
        mergeLinearNodeOrder([
          (id: 'B', order: 0, nextNodeId: null),
          (id: 'A', order: 0, nextNodeId: null),
        ], const []).map((n) => n.id),
        ['A', 'B'],
      );
    },
  );

  test(
    'missing targets, cycles including disconnected cycles, and orphans diagnosed',
    () {
      final nodes = [
        (id: 'A', order: 0, nextNodeId: 'missing'),
        (id: 'B', order: 1, nextNodeId: 'C'),
        (id: 'C', order: 2, nextNodeId: 'B'),
      ];
      final issues = diagnoseLinearNodeOrder(nodes).join('\n');
      expect(issues, contains('없는 다음 노드 missing'));
      expect(issues, contains('순환 연결'));
      expect(issues, contains('B: 시작점에서 도달 불가'));
      expect(issues, contains('C: 시작점에서 도달 불가'));
      expect(nodes.first.nextNodeId, 'missing');
      expect(diagnoseLinearNodeOrder(linearNodePositions(['A'])), isEmpty);
      expect(diagnoseLinearNodeOrder([]), isEmpty);
    },
  );

  test('duplicate/empty IDs are rejected and duplicate order is diagnosed', () {
    expect(() => linearNodePositions(['A', 'A']), throwsArgumentError);
    expect(() => linearNodePositions(['']), throwsArgumentError);
    expect(
      diagnoseLinearNodeOrder([
        (id: 'A', order: 0, nextNodeId: 'B'),
        (id: 'B', order: 0, nextNodeId: null),
      ]).join(),
      contains('중복 순서'),
    );
  });
}
