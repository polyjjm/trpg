/// ttsVoiceCache/typecast 문서 안의 voices 배열 항목 하나 — Typecast가
/// 관리하는 실제 보이스 카탈로그를 그대로 옮긴 값이라, sfxLibrary/bgmLibrary
/// 처럼 이 프로젝트가 별도 문서로 관리하는 라이브러리가 아니다(각자 고유
/// Firestore 문서 id가 없다 — Typecast의 voice_id를 그대로 [id]로 쓴다).
class AdminTtsVoice {
  final String id;
  final String name;

  const AdminTtsVoice({required this.id, required this.name});

  factory AdminTtsVoice.fromJson(Map<String, dynamic> json) {
    return AdminTtsVoice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}
