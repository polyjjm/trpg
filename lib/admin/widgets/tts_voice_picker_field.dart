import 'package:flutter/material.dart';

import '../models/admin_tts_voice.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';

/// Typecast 보이스 선택 드롭다운 + "새로고침" 버튼 — 팩 설정의 "기본
/// 내레이터 보이스"와 노드 연출 효과의 "보이스 재정의" 둘 다 이 위젯을 그대로
/// 쓴다(BgmPickerField/SfxPickerField와 같은 공유 패턴). sfxLibrary/
/// bgmLibrary와 달리 미리듣기 재생 버튼이 없다 — Typecast의 GET /v2/voices
/// 응답(voice_id/voice_name/gender/age/voice_type/use_cases/models, 문서
/// 대조로 확인함)에 재생 가능한 샘플 URL 필드가 아예 없어서, 1차 버전에서는
/// 이름만 보여준다(미리듣기를 넣으려면 별도로 이 보이스로 짧은 샘플 문장을
/// 합성해 재생해야 한다 — 지금은 범위 밖).
class TtsVoicePickerField extends StatelessWidget {
  final String? currentId;
  final List<AdminTtsVoice> voices;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRefresh;
  final bool refreshing;

  /// 드롭다운의 "선택 안 함" 항목에 보여줄 문구 — 팩 설정(기본 보이스 자체를
  /// 안 정할 수도 있음)과 노드 재정의("(선택 안 함) = 팩 기본값 사용")가
  /// 서로 다른 문구를 쓴다.
  final String noSelectionLabel;

  const TtsVoicePickerField({
    super.key,
    required this.currentId,
    required this.voices,
    required this.onChanged,
    required this.onRefresh,
    required this.refreshing,
    this.noSelectionLabel = '(선택 안 함)',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue:
                    currentId != null && voices.any((v) => v.id == currentId)
                    ? currentId
                    : null,
                decoration: adminInputDecoration(hintText: noSelectionLabel),
                dropdownColor: AdminColors.inputDropdownMenuBg,
                style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(noSelectionLabel),
                  ),
                  ...voices.map(
                    (v) => DropdownMenuItem<String>(
                      value: v.id,
                      child: Text(v.name),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: '보이스 목록 새로고침',
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AdminColors.muted,
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: AdminColors.muted,
                      ),
              ),
            ),
          ],
        ),
        if (voices.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '→ 보이스 목록이 비어 있어요. 새로고침을 눌러보세요.',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        ],
      ],
    );
  }
}
