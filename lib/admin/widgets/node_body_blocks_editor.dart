import 'package:flutter/material.dart';

import '../models/admin_node_block.dart';
import '../models/admin_tts_voice.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';
import 'node_effects_editor.dart' show TtsEmotionDropdown, TtsSlider;
import 'tts_voice_picker_field.dart';

/// "본문" 섹션 — 블록마다 따로 자라나는(auto-grow) 텍스트 필드 하나씩,
/// 세로로 쌓아 보여준다. 예전엔 문단 사이에 빈 줄을 넣어 구분하는 텍스트
/// 필드 하나(NodeBodyEditor, bodyText → applyBodyTextToBlocks)였는데,
/// "글쓰기에 더 가깝게" 만들기 위해 Firestore에 실제로 저장되는 blocks
/// 배열을 편집 중에도 그대로 직접 건드리는 방식으로 되돌렸다 — 저장 시점에
/// 따로 나눌 필요가 없다.
class NodeBodyBlocksEditor extends StatelessWidget {
  final List<AdminNodeBlock> blocks;
  final VoidCallback onChanged;

  /// interactive 팩에서만 블록별 "보이스 설정"(다중 화자 대사 지원, 요청
  /// 사양 Part 3)을 보여준다 — linear 팩은 이 복잡도를 볼 필요가 없다는
  /// 판단이다("Scope this UI to interactive-type packs only"). 데이터
  /// 모델(AdminNodeBlock의 ttsVoiceId 등) 자체는 막지 않는다 — UI만 숨긴다.
  final bool showTtsOverride;
  final List<AdminTtsVoice> ttsVoices;
  final VoidCallback onRefreshTtsVoices;
  final bool refreshingTtsVoices;

  const NodeBodyBlocksEditor({
    super.key,
    required this.blocks,
    required this.onChanged,
    required this.showTtsOverride,
    required this.ttsVoices,
    required this.onRefreshTtsVoices,
    required this.refreshingTtsVoices,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BlockField(
              key: ObjectKey(blocks[i]),
              block: blocks[i],
              onChanged: onChanged,
              onDelete: blocks.length <= 1
                  ? null
                  : () {
                      blocks.removeAt(i);
                      onChanged();
                    },
              showTtsOverride: showTtsOverride,
              ttsVoices: ttsVoices,
              onRefreshTtsVoices: onRefreshTtsVoices,
              refreshingTtsVoices: refreshingTtsVoices,
            ),
          ),
        TextButton.icon(
          onPressed: () {
            blocks.add(AdminNodeBlock());
            onChanged();
          },
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('문단 추가', style: TextStyle(fontSize: 12.5)),
          style: TextButton.styleFrom(foregroundColor: AdminColors.gold),
        ),
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              '아직 문단이 없어요. "문단 추가"로 시작하세요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
          ),
      ],
    );
  }
}

/// 블록 하나 — hover/focus 중일 때만 우측 상단에 삭제 아이콘이 뜬다. 텍스트
/// 필드 아래에(interactive 팩만) 접힌 "보이스 설정" 섹션이 따라온다.
class _BlockField extends StatefulWidget {
  final AdminNodeBlock block;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;
  final bool showTtsOverride;
  final List<AdminTtsVoice> ttsVoices;
  final VoidCallback onRefreshTtsVoices;
  final bool refreshingTtsVoices;

  const _BlockField({
    required super.key,
    required this.block,
    required this.onChanged,
    required this.onDelete,
    required this.showTtsOverride,
    required this.ttsVoices,
    required this.onRefreshTtsVoices,
    required this.refreshingTtsVoices,
  });

  @override
  State<_BlockField> createState() => _BlockFieldState();
}

class _BlockFieldState extends State<_BlockField> {
  final _focusNode = FocusNode();
  bool _hovering = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showDelete = widget.onDelete != null && (_hovering || _focused);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Stack(
            children: [
              TextFormField(
                focusNode: _focusNode,
                initialValue: widget.block.text,
                minLines: 2,
                maxLines: null,
                style: TextStyle(
                  color: AdminColors.inputText,
                  fontSize: 13.5,
                  height: 1.6,
                ),
                decoration: adminInputDecoration(hintText: '문단을 입력하세요.')
                    .copyWith(
                      contentPadding: const EdgeInsets.fromLTRB(10, 10, 34, 10),
                    ),
                onChanged: (value) {
                  widget.block.text = value;
                  widget.onChanged();
                },
              ),
              if (showDelete)
                Positioned(
                  top: 4,
                  right: 4,
                  child: InkWell(
                    onTap: widget.onDelete,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AdminColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.showTtsOverride)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _BlockTtsOverrideSection(
              block: widget.block,
              onChanged: widget.onChanged,
              ttsVoices: widget.ttsVoices,
              onRefreshTtsVoices: widget.onRefreshTtsVoices,
              refreshingTtsVoices: widget.refreshingTtsVoices,
            ),
          ),
      ],
    );
  }
}

/// 블록 하나의 TTS 재정의 — 접힌 채로 시작한다(요청 사양: "collapsed state
/// just shows '노드 기본값 사용'"). 이미 뭔가 재정의돼 있는 블록(예: 승인
/// 대기 중이던 노드를 다시 열었을 때)만 펼친 채로 시작해서 뭐가 재정의됐는지
/// 바로 보이게 한다. 다섯 필드 전부 개별 폴백이라(admin_node_block.dart
/// 참고) 이 중 몇 개만 건드리고 나머지는 비워 둬도 된다 — 노드 기본값을
/// 그대로 물려받는다.
class _BlockTtsOverrideSection extends StatefulWidget {
  final AdminNodeBlock block;
  final VoidCallback onChanged;
  final List<AdminTtsVoice> ttsVoices;
  final VoidCallback onRefreshTtsVoices;
  final bool refreshingTtsVoices;

  const _BlockTtsOverrideSection({
    required this.block,
    required this.onChanged,
    required this.ttsVoices,
    required this.onRefreshTtsVoices,
    required this.refreshingTtsVoices,
  });

  @override
  State<_BlockTtsOverrideSection> createState() =>
      _BlockTtsOverrideSectionState();
}

class _BlockTtsOverrideSectionState extends State<_BlockTtsOverrideSection> {
  late bool _expanded = widget.block.hasTtsOverride;

  void _clearOverride() {
    widget.block
      ..ttsVoiceId = null
      ..ttsEmotion = null
      ..ttsEmotionIntensity = null
      ..ttsPitch = null
      ..ttsTempo = null;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final overridden = block.hasTtsOverride;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: AdminColors.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  overridden ? '보이스 설정: 재정의됨' : '보이스 설정: 노드 기본값 사용',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: overridden ? AdminColors.gold : AdminColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '보이스',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
                const SizedBox(height: 4),
                TtsVoicePickerField(
                  currentId: block.ttsVoiceId,
                  voices: widget.ttsVoices,
                  onRefresh: widget.onRefreshTtsVoices,
                  refreshing: widget.refreshingTtsVoices,
                  noSelectionLabel: '(선택 안 함) 노드 기본값',
                  onChanged: (id) {
                    block.ttsVoiceId = id;
                    widget.onChanged();
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  '감정',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
                const SizedBox(height: 4),
                TtsEmotionDropdown(
                  value: block.ttsEmotion,
                  onChanged: (preset) {
                    block.ttsEmotion = preset;
                    widget.onChanged();
                  },
                ),
                if (block.ttsEmotion != null) ...[
                  const SizedBox(height: 10),
                  TtsSlider(
                    label: '감정 강도',
                    valueLabel: (block.ttsEmotionIntensity ?? 1.0)
                        .toStringAsFixed(1),
                    value: block.ttsEmotionIntensity ?? 1.0,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    onChanged: (v) {
                      block.ttsEmotionIntensity = v;
                      widget.onChanged();
                    },
                  ),
                ],
                const SizedBox(height: 10),
                TtsSlider(
                  label: '피치',
                  valueLabel: (block.ttsPitch ?? 0).toStringAsFixed(0),
                  value: block.ttsPitch ?? 0,
                  min: -12,
                  max: 12,
                  divisions: 24,
                  onChanged: (v) {
                    block.ttsPitch = v;
                    widget.onChanged();
                  },
                ),
                const SizedBox(height: 10),
                TtsSlider(
                  label: '템포',
                  valueLabel: '${(block.ttsTempo ?? 1.0).toStringAsFixed(2)}x',
                  value: block.ttsTempo ?? 1.0,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  onChanged: (v) {
                    block.ttsTempo = v;
                    widget.onChanged();
                  },
                ),
                if (overridden) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _clearOverride,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '노드 기본값으로 되돌리기',
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
