/// 팩에 이미 있는 노드 id들에서 "접두사 + 숫자" 패턴을 찾아 그 패턴을 이어서
/// 다음 id(들)를 제안한다("chapter_3"가 있으면 "chapter_4", "chapter_5", ...).
/// 일치하는 패턴이 없으면(팩이 비어 있거나 id 규칙이 제각각이면) 'node_1'부터
/// 시작하는 기본 접두사로 떨어진다.
///
/// "+ 새 스토리 노드"(단건, story_tab_view.dart의 _handleAddNode)와 "한 번에
/// 쓰기"(다건, bulk_node_writer.dart) 양쪽이 공유한다 — 한쪽만 따로 구현하면
/// 두 흐름에서 서로 다른 id 모양이 나올 수 있다.
List<String> suggestSequentialNodeIds(Iterable<String> existingIds, int count) {
  final pattern = RegExp(r'^(.*?)(\d+)$');

  String prefix = 'node_';
  var next = 1;

  String? matchedPrefix;
  var maxNumber = 0;
  for (final id in existingIds) {
    final match = pattern.firstMatch(id);
    if (match == null) continue;
    final candidatePrefix = match.group(1)!;
    final number = int.tryParse(match.group(2)!);
    if (number == null) continue;
    matchedPrefix ??= candidatePrefix;
    if (candidatePrefix == matchedPrefix && number > maxNumber) {
      maxNumber = number;
    }
  }
  if (matchedPrefix != null) {
    prefix = matchedPrefix;
    next = maxNumber + 1;
  }

  final taken = existingIds.toSet();
  final result = <String>[];
  while (result.length < count) {
    final candidate = '$prefix$next';
    next += 1;
    if (taken.contains(candidate) || result.contains(candidate)) continue;
    result.add(candidate);
  }
  return result;
}
