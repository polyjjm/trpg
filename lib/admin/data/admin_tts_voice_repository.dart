import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/admin_node_block.dart';
import '../models/admin_tts_voice.dart';
import '../models/node_effects.dart';

/// ttsVoiceCache/typecast 문서 하나를 읽는다(+ 수동 새로고침 트리거) —
/// Typecast의 보이스 목록은 이 프로젝트가 개별 문서로 관리하는 sfxLibrary/
/// bgmLibrary와 달리 "그쪽 서비스가 갖고 있는 카탈로그를 그대로 캐시해 둔
/// 것"이다. 그래서 컬렉션이 아니라 문서 하나(고정 id `typecast`)에 배열로
/// 들어있고, 클라이언트는 이 문서를 절대 직접 쓰지 않는다(firestore.rules가
/// write를 아예 막아 둔다) — 실제 값은 Cloud Functions의
/// refreshTypecastVoiceCacheScheduled(매일 자동)/refreshTypecastVoices
/// (수동 새로고침 버튼)만 채운다.
class AdminTtsVoiceRepository {
  AdminTtsVoiceRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> get _cacheDoc =>
      _firestore.collection('ttsVoiceCache').doc('typecast');

  /// 문서가 아직 없으면(최초 배포 직후, 예약 실행/수동 새로고침을 한 번도
  /// 안 탄 상태) 빈 목록을 흘려보낸다 — [refreshVoices]로 채울 수 있다.
  Stream<List<AdminTtsVoice>> watchVoices() {
    return _cacheDoc.snapshots().map((doc) {
      final data = doc.data();
      final raw = data?['voices'] as List<dynamic>?;
      if (raw == null) return const <AdminTtsVoice>[];
      return raw
          .map((v) => AdminTtsVoice.fromJson(v as Map<String, dynamic>))
          .toList();
    });
  }

  /// refreshTypecastVoices Cloud Function을 불러 캐시를 즉시 새로고침한다 —
  /// author/admin 누구나 부를 수 있다(오디오 생성이 아니라 저비용 메타데이터
  /// 조회라 admin 전용으로 좁힐 필요가 없다는 판단, functions/src/index.ts
  /// 참고).
  Future<void> refreshVoices() async {
    await _functions.httpsCallable('refreshTypecastVoices').call();
  }

  /// 노드 편집기의 "미리듣기" 버튼이 부른다 — synthesizeNodeTts와 달리 지금
  /// 화면에 있는(아직 임시저장도 안 했을 수 있는) 초안 blocks/effects.tts를
  /// 그대로 실어 보낸다(functions/src/index.ts의 previewNodeTts 참고). 결과
  /// 오디오는 리더용 ttsAudioUrl이 아니라 ttsPreviewAudioUrl에 잠정 캐시된다.
  Future<String> previewNodeTts({
    required String packId,
    required String nodeId,
    required List<AdminNodeBlock> blocks,
    required TtsEffect? effectsTts,
    required String? defaultTtsVoiceId,
  }) async {
    final result = await _functions.httpsCallable('previewNodeTts').call({
      'packId': packId,
      'nodeId': nodeId,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'effectsTts': effectsTts?.toJson(),
      'defaultTtsVoiceId': defaultTtsVoiceId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final url = data['audioUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('previewNodeTts가 오디오 URL을 돌려주지 않았어요.');
    }
    return url;
  }
}
