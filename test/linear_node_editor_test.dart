import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotry_trpg/admin/data/admin_tts_voice_repository.dart';
import 'package:sotry_trpg/admin/models/admin_story_node.dart';
import 'package:sotry_trpg/admin/models/story_pack_type.dart';
import 'package:sotry_trpg/admin/widgets/node_choice_editor.dart';
import 'package:sotry_trpg/admin/widgets/node_editor.dart';

class _UnusedTtsRepository implements AdminTtsVoiceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget editor(AdminStoryNode node, StoryPackType type) => MaterialApp(
  home: Scaffold(
    body: NodeEditor(
      node: node,
      dirty: true,
      isIdEditable: true,
      images: const [],
      sfxLibrary: const [],
      bgmLibrary: const [],
      ttsVoices: const [],
      onRefreshTtsVoices: () {},
      refreshingTtsVoices: false,
      ttsVoiceRepository: _UnusedTtsRepository(),
      packId: 'pack',
      defaultTtsVoiceId: null,
      packType: type,
      candidates: const [],
      inheritedBackgroundImageId: null,
      onChanged: () {},
      onSaveDraft: () {},
      onCancelDeleteRequest: () {},
    ),
  ),
);

Finder fieldWithValue(String value) => find.byWidgetPredicate(
  (w) => w is TextFormField && w.initialValue == value,
);

void main() {
  testWidgets('linear ID, numeric order and next node are read only', (
    tester,
  ) async {
    final node = AdminStoryNode(id: 'chapter_1', nextNodeId: 'chapter_2');
    await tester.pumpWidget(editor(node, StoryPackType.linear));
    expect(fieldWithValue('chapter_1'), findsNothing);
    expect(fieldWithValue('0'), findsNothing);
    expect(find.byType(NodeChoiceEditor), findsNothing);
    expect(find.text('다음 페이지: chapter_2 · 목록 순서로 자동 연결'), findsOneWidget);
    expect(find.text('전체 임시저장 (나만 보임)'), findsOneWidget);
    expect(node.id, 'chapter_1');
    expect(node.nextNodeId, 'chapter_2');
  });

  testWidgets('interactive keeps editable ID/order and choice editor', (
    tester,
  ) async {
    final node = AdminStoryNode(id: 'chapter_1');
    await tester.pumpWidget(editor(node, StoryPackType.interactive));
    expect(find.byType(NodeChoiceEditor), findsOneWidget);
    await tester.enterText(fieldWithValue('chapter_1'), 'renamed');
    await tester.enterText(fieldWithValue('0'), '7');
    expect(node.id, 'renamed');
    expect(node.order, 7);
    expect(find.text('임시저장 (나만 보임)'), findsOneWidget);
  });
}
