import 'package:flutter/material.dart';

import '../../core/audio/audio_service.dart';
import '../data/admin_tts_voice_repository.dart';
import '../models/admin_node_block.dart';
import '../models/admin_tts_voice.dart';
import '../models/node_effects.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';

/// 보이스 미리듣기에 쓰는 샘플 문장 — 어떤 보이스를 골라도 같은 문장을 읽게
/// 해서 목소리끼리 비교가 되게 한다. 짧아야 생성이 빠르고, 인사말이라 억양이
/// 잘 드러난다.
const String kTtsVoiceSampleText = '안녕하세요. TTS 음성 샘플입니다.';

/// 보이스 미리듣기를 하려면 previewNodeTts를 부를 맥락(팩/노드)이 필요하다 —
/// 그 함수가 팩/노드 단위로 결과를 캐시하기 때문이다. 이 값을 넘기지 않으면
/// 재생 버튼 자체가 안 나온다(예: 아직 노드가 정해지지 않은 자리).
class TtsVoiceSampleContext {
  final AdminTtsVoiceRepository repository;
  final String packId;
  final String nodeId;

  const TtsVoiceSampleContext({
    required this.repository,
    required this.packId,
    required this.nodeId,
  });
}

/// Typecast 보이스 선택 드롭다운 + "새로고침" + **미리듣기**.
///
/// Typecast의 GET /v2/voices 응답에는 재생 가능한 샘플 URL 필드가 없다 —
/// 그래서 예전엔 이름만 보여줬고, 작가는 "차분한 여성" 같은 이름만 보고
/// 골라야 했다. 지금은 고른 보이스로 [kTtsVoiceSampleText]를 즉석에서 합성해
/// 들려준다(previewNodeTts 재사용) — 실제 본문이 아니라 이 한 문장만 보내므로
/// 노드 내용과 무관하게 목소리만 비교할 수 있다.
class TtsVoicePickerField extends StatefulWidget {
  final String? currentId;
  final List<AdminTtsVoice> voices;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRefresh;
  final bool refreshing;

  /// 드롭다운의 "선택 안 함" 항목에 보여줄 문구 — 팩 설정(기본 보이스 자체를
  /// 안 정할 수도 있음)과 노드 재정의("(선택 안 함) = 팩 기본값 사용")가
  /// 서로 다른 문구를 쓴다.
  final String noSelectionLabel;

  /// null이면 미리듣기 버튼을 그리지 않는다.
  final TtsVoiceSampleContext? sampleContext;

  const TtsVoicePickerField({
    super.key,
    required this.currentId,
    required this.voices,
    required this.onChanged,
    required this.onRefresh,
    required this.refreshing,
    this.noSelectionLabel = '(선택 안 함)',
    this.sampleContext,
  });

  @override
  State<TtsVoicePickerField> createState() => _TtsVoicePickerFieldState();
}

class _TtsVoicePickerFieldState extends State<TtsVoicePickerField> {
  bool _playing = false;

  /// 지금 고른 보이스로 샘플 문장을 합성해 재생한다.
  ///
  /// 노드의 실제 본문 대신 [kTtsVoiceSampleText] 한 문단만 보낸다 — 목소리를
  /// 비교하려는 것이지 이 노드를 들어보려는 게 아니고, 짧아서 생성도 빠르다.
  /// 감정/피치/템포는 일부러 기본값으로 둔다(보이스 자체의 소리를 듣는 게
  /// 목적이라, 여기에 재정의를 섞으면 무엇 때문에 다르게 들리는지 알 수 없다).
  Future<void> _playSample() async {
    final ctx = widget.sampleContext;
    final voiceId = widget.currentId;
    if (ctx == null || voiceId == null || _playing) return;

    setState(() => _playing = true);
    try {
      final url = await ctx.repository.previewNodeTts(
        packId: ctx.packId,
        nodeId: ctx.nodeId,
        blocks: [AdminNodeBlock()..text = kTtsVoiceSampleText],
        effectsTts: TtsEffect(voiceId: voiceId),
        defaultTtsVoiceId: voiceId,
      );
      await AudioService.instance.playSfx(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('샘플 재생에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSample = widget.sampleContext != null && widget.currentId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue:
                    widget.currentId != null &&
                        widget.voices.any((v) => v.id == widget.currentId)
                    ? widget.currentId
                    : null,
                decoration: adminInputDecoration(
                  hintText: widget.noSelectionLabel,
                ),
                dropdownColor: AdminColors.inputDropdownMenuBg,
                style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(widget.noSelectionLabel),
                  ),
                  ...widget.voices.map(
                    (v) => DropdownMenuItem<String>(
                      value: v.id,
                      child: Text(v.name),
                    ),
                  ),
                ],
                onChanged: widget.onChanged,
              ),
            ),
            if (widget.sampleContext != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: canSample ? '이 보이스로 샘플 듣기' : '먼저 보이스를 고르세요',
                  onPressed: (!canSample || _playing) ? null : _playSample,
                  icon: _playing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AdminColors.muted,
                          ),
                        )
                      : Icon(
                          Icons.play_circle_outline_rounded,
                          size: 20,
                          color: canSample
                              ? AdminColors.gold
                              : AdminColors.inputDisabledBorder,
                        ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: '보이스 목록 새로고침',
                onPressed: widget.refreshing ? null : widget.onRefresh,
                icon: widget.refreshing
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
        if (widget.sampleContext != null && canSample) ...[
          const SizedBox(height: 6),
          Text(
            '샘플 문장: "$kTtsVoiceSampleText"',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        ],
        if (widget.voices.isEmpty) ...[
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
