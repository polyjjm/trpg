import 'package:cloud_functions/cloud_functions.dart';

/// synthesizeNodeTts Cloud Function을 부르는 얇은 래퍼 — Typecast API 키는
/// Functions 시크릿(TYPECAST_API_KEY)에만 있고, 클라이언트는 이 함수를 통해서만
/// 오디오 URL을 받는다(functions/src/index.ts 참고). 캐시 히트/미스 판단은
/// 함수가 알아서 한다 — 첫 방문자가 생성을 트리거하고 나면 그 뒤로는 저장된
/// ttsAudioUrl을 즉시 돌려주므로, 리더 쪽은 캐시 여부를 신경 쓰지 않고 매번
/// 그냥 이 함수를 부르면 된다.
class NodeTtsRepository {
  NodeTtsRepository({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> synthesize({
    required String packId,
    required String nodeId,
  }) async {
    final result = await _functions.httpsCallable('synthesizeNodeTts').call({
      'packId': packId,
      'nodeId': nodeId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final url = data['audioUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('synthesizeNodeTts가 오디오 URL을 돌려주지 않았어요.');
    }
    return url;
  }
}
