import 'package:flutter/material.dart';

import '../../core/audio/audio_service.dart';
import '../data/admin_tts_voice_repository.dart';
import '../models/admin_bgm.dart';
import '../models/admin_node_block.dart';
import '../models/admin_sfx.dart';
import '../models/admin_tts_voice.dart';
import '../models/node_effects.dart';
import 'admin_theme.dart';
import 'bgm_picker_field.dart';
import 'labeled_field.dart';
import 'sfx_picker_field.dart';
import 'tts_voice_picker_field.dart';

/// "연출 효과" 섹션 — 프리셋 전용 5종(암전/화면 흔들림/효과음/화면 플래시/
/// 진동)에 배경음악 전환/TTS 내레이션 커스터마이즈를 더 다룬다 — 배경음악은
/// 프리셋 드롭다운이 아니라 "이전과 동일/트랙 선택/무음 전환" 3지선다다
/// (_BgmEffectRow 참고), TTS는 체크박스 하나로 "팩 기본값 그대로" ↔
/// "이 노드만 보이스/감정/피치/템포 재정의"를 오간다(_TtsEffectRow 참고,
/// _SfxEffectRow와 같은 "체크박스 + 펼쳐지는 상세 컨트롤" 레이아웃). 자유
/// 설정이 없어서 비개발자 작가도 무슨 값을 넣어야 할지 고민할 필요가
/// 없다는 원칙은 그대로다(감정 프리셋도 자유 입력이 아니라 정해진 목록
/// 중에서 고른다).
///
/// 접고 펴는 건 이 위젯 바깥(node_editor.dart의 "연출 효과" 필/토글)이
/// 맡는다 — 예전엔 여기 자체가 ExpansionTile이었는데, 노드 에디터 전체를
/// 통 카드로 다시 짠 뒤로는 그 바깥 토글과 겹쳐 접었다 펴는 UI가 두 겹이
/// 되는 게 이상해서, 그 껍데기(제목 줄 + 화살표)만 걷어내고 효과별 행들은
/// 그대로 옮겨왔다 — 실제 편집 로직/각 행의 모양은 손대지 않았다.
class NodeEffectsEditor extends StatelessWidget {
  final NodeEffects effects;
  final List<AdminSfx> sfxLibrary;
  final List<AdminBgm> bgmLibrary;
  final List<AdminTtsVoice> ttsVoices;
  final VoidCallback onRefreshTtsVoices;
  final bool refreshingTtsVoices;

  /// "미리듣기" 버튼(_TtsEffectRow 안)이 previewNodeTts를 부르는 데 필요한
  /// 값들 — 팩/노드 id, 지금 화면의(아직 저장 전일 수도 있는) 본문 블록,
  /// 팩 기본 보이스. Cloud Function이 liveSnapshot이 아니라 이 값들을 그대로
  /// 받아 생성하므로(node_tts_repository.dart의 synthesizeNodeTts와 다른
  /// 점), 여기서 직접 실어 보낸다.
  final AdminTtsVoiceRepository ttsVoiceRepository;
  final String packId;
  final String nodeId;
  final List<AdminNodeBlock> blocks;
  final String? defaultTtsVoiceId;

  final ValueChanged<NodeEffects> onChanged;

  const NodeEffectsEditor({
    super.key,
    required this.effects,
    required this.sfxLibrary,
    required this.bgmLibrary,
    required this.ttsVoices,
    required this.onRefreshTtsVoices,
    required this.refreshingTtsVoices,
    required this.ttsVoiceRepository,
    required this.packId,
    required this.nodeId,
    required this.blocks,
    required this.defaultTtsVoiceId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EffectRow<BlackoutDurationPreset>(
          label: '암전 (블랙아웃)',
          description: '텍스트 나오기 전 화면이 잠깐 검게 변해요',
          enabled: effects.blackout.enabled,
          onEnabledChanged: (value) => onChanged(
            effects.copyWith(
              blackout: effects.blackout.copyWith(enabled: value),
            ),
          ),
          presetValue: effects.blackout.durationPreset,
          presetOptions: BlackoutDurationPreset.values,
          presetLabel: (p) => p.label,
          onPresetChanged: (preset) => onChanged(
            effects.copyWith(
              blackout: effects.blackout.copyWith(durationPreset: preset),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _EffectRow<ShakeIntensityPreset>(
          label: '화면 흔들림',
          description: '텍스트 등장과 함께 화면이 짧게 흔들려요',
          enabled: effects.shake.enabled,
          onEnabledChanged: (value) => onChanged(
            effects.copyWith(shake: effects.shake.copyWith(enabled: value)),
          ),
          presetValue: effects.shake.intensityPreset,
          presetOptions: ShakeIntensityPreset.values,
          presetLabel: (p) => p.label,
          onPresetChanged: (preset) => onChanged(
            effects.copyWith(
              shake: effects.shake.copyWith(intensityPreset: preset),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _SfxEffectRow(
          sfx: effects.sfx,
          sfxLibrary: sfxLibrary,
          onEnabledChanged: (value) => onChanged(
            effects.copyWith(sfx: effects.sfx.copyWith(enabled: value)),
          ),
          onSfxIdChanged: (sfxId) => onChanged(
            effects.copyWith(
              sfx: sfxId == null
                  ? effects.sfx.copyWith(clearSfxId: true)
                  : effects.sfx.copyWith(sfxId: sfxId),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _FlashEffectRow(
          flash: effects.flash,
          onEnabledChanged: (value) => onChanged(
            effects.copyWith(flash: effects.flash.copyWith(enabled: value)),
          ),
          onColorChanged: (preset) => onChanged(
            effects.copyWith(
              flash: effects.flash.copyWith(colorPreset: preset),
            ),
          ),
          onDurationChanged: (preset) => onChanged(
            effects.copyWith(
              flash: effects.flash.copyWith(durationPreset: preset),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _BgmEffectRow(
          bgm: effects.bgm,
          bgmLibrary: bgmLibrary,
          onChanged: (bgm) => onChanged(
            bgm == null
                ? effects.copyWith(clearBgm: true)
                : effects.copyWith(bgm: bgm),
          ),
        ),
        const SizedBox(height: 14),
        _TtsEffectRow(
          tts: effects.tts,
          voices: ttsVoices,
          onRefreshVoices: onRefreshTtsVoices,
          refreshingVoices: refreshingTtsVoices,
          ttsVoiceRepository: ttsVoiceRepository,
          packId: packId,
          nodeId: nodeId,
          blocks: blocks,
          defaultTtsVoiceId: defaultTtsVoiceId,
          onChanged: (tts) => onChanged(
            tts == null
                ? effects.copyWith(clearTts: true)
                : effects.copyWith(tts: tts),
          ),
        ),
        const SizedBox(height: 14),
        _EffectRow<HapticDurationPreset>(
          label: '진동 (모바일)',
          description: '모바일 기기에서만 재생돼요',
          enabled: effects.haptic.enabled,
          onEnabledChanged: (value) => onChanged(
            effects.copyWith(haptic: effects.haptic.copyWith(enabled: value)),
          ),
          presetValue: effects.haptic.durationPreset,
          presetOptions: HapticDurationPreset.values,
          presetLabel: (p) => p.label,
          onPresetChanged: (preset) => onChanged(
            effects.copyWith(
              haptic: effects.haptic.copyWith(durationPreset: preset),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '체크한 효과는 이 노드의 텍스트가 나타나기 시작할 때 함께 재생돼요.',
          style: TextStyle(fontSize: 11, color: AdminColors.muted),
        ),
      ],
    );
  }
}

/// "효과음" 행 전용 — 나머지 세 행(_EffectRow<T>)은 고정 프리셋 목록 중
/// 하나를 고르는 좁은 드롭다운이면 충분하지만, 효과음은 라이브러리에서
/// 카테고리로 좁혀가며 고르고 미리 들어볼 수 있어야 해서(SfxPickerField)
/// 체크박스 줄 아래에 그 피커를 통째로 펼쳐 넣는 별도 레이아웃을 쓴다 —
/// _BackgroundSection이 ImagePickerField를 펼쳐 넣는 방식과 같다.
class _SfxEffectRow extends StatelessWidget {
  final SfxEffect sfx;
  final List<AdminSfx> sfxLibrary;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String?> onSfxIdChanged;

  const _SfxEffectRow({
    required this.sfx,
    required this.sfxLibrary,
    required this.onEnabledChanged,
    required this.onSfxIdChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: sfx.enabled,
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AdminColors.gold
                      : AdminColors.checkboxUncheckedFill,
                ),
                checkColor: AdminColors.checkboxCheckColor,
                side: BorderSide(
                  color: AdminColors.checkboxUncheckedBorder,
                  width: 1.5,
                ),
                onChanged: (checked) => onEnabledChanged(checked ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '효과음',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.ivory,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '효과음 라이브러리에 올린 파일 중 하나를 골라요',
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (sfx.enabled) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: SfxPickerField(
              currentId: sfx.sfxId,
              sfxLibrary: sfxLibrary,
              onChanged: onSfxIdChanged,
            ),
          ),
        ],
      ],
    );
  }
}

enum _BgmMode { inherit, track, silence }

/// "배경음악" 행 전용 — 나머지 행들과 달리 켜짐/꺼짐 체크박스가 아니라
/// "이전과 동일(기본값)/트랙 선택/무음으로 전환" 3지선다다(effects.bgm이
/// null/트랙 지정/silence=true 셋 중 하나로 표현되는 것과 정확히 대응 —
/// node_effects.dart의 BgmEffect doc 참고). "트랙 선택"을 골랐을 때만 그
/// 아래에 BgmPickerField를 펼친다 — _SfxEffectRow가 체크박스 아래 SfxPickerField를
/// 펼치는 것과 같은 레이아웃 관례다.
class _BgmEffectRow extends StatelessWidget {
  final BgmEffect? bgm;
  final List<AdminBgm> bgmLibrary;
  final ValueChanged<BgmEffect?> onChanged;

  const _BgmEffectRow({
    required this.bgm,
    required this.bgmLibrary,
    required this.onChanged,
  });

  _BgmMode get _mode {
    final effect = bgm;
    if (effect == null) return _BgmMode.inherit;
    if (effect.silence) return _BgmMode.silence;
    return _BgmMode.track;
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 체크박스가 없는 행이지만, 다른 행들의 라벨 인덴트(체크박스
            // 24px + 간격 8px)와 맞춰야 세로로 훑을 때 글자가 어긋나 보이지
            // 않는다.
            const SizedBox(width: 32),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '배경음악',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.ivory,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '안 고르면(기본값) 이전 노드의 배경음악이 그대로 이어져요',
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _BgmModeChip(
                label: '이전과 동일(기본값)',
                selected: mode == _BgmMode.inherit,
                onTap: () => onChanged(null),
              ),
              _BgmModeChip(
                label: '트랙 선택',
                selected: mode == _BgmMode.track,
                onTap: () => onChanged(
                  BgmEffect(
                    bgmId: bgm?.bgmId,
                    silence: false,
                    volume: bgm?.volume ?? 1.0,
                  ),
                ),
              ),
              _BgmModeChip(
                label: '무음으로 전환',
                selected: mode == _BgmMode.silence,
                onTap: () => onChanged(const BgmEffect(silence: true)),
              ),
            ],
          ),
        ),
        if (mode == _BgmMode.track) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: BgmPickerField(
              currentId: bgm?.bgmId,
              bgmLibrary: bgmLibrary,
              onChanged: (id) => onChanged(
                BgmEffect(
                  bgmId: id,
                  silence: false,
                  volume: bgm?.volume ?? 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: _BgmVolumeSlider(
              // mode == track이면 bgm은 항상 non-null이다(_mode getter 참고).
              volume: bgm!.volume,
              onChanged: (value) => onChanged(bgm!.copyWith(volume: value)),
            ),
          ),
        ],
      ],
    );
  }
}

/// "트랙 선택" 상태일 때만 보이는 볼륨 슬라이더 — 0%(무음)~100%(원본
/// 그대로), 기본 100%. 같은 트랙을 여러 노드에 걸쳐 이어 쓰되 대사가 많은
/// 장면에서만 볼륨을 낮추는 용도라, "이전과 동일"/"무음으로 전환"에는
/// 노출하지 않는다(볼륨 자체가 의미 없는 상태라서).
class _BgmVolumeSlider extends StatelessWidget {
  final double volume;
  final ValueChanged<double> onChanged;

  const _BgmVolumeSlider({required this.volume, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('볼륨', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AdminColors.gold,
              thumbColor: AdminColors.gold,
              inactiveTrackColor: AdminColors.panel2,
              trackHeight: 3,
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(volume * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: AdminColors.ivory),
          ),
        ),
      ],
    );
  }
}

class _BgmModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BgmModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : AdminColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

/// "TTS 내레이션" 행 전용 — bgm처럼 3지선다가 아니라 sfx처럼 "체크박스 +
/// 펼쳐지는 상세 컨트롤"이다. 체크 해제(기본값)면 [TtsEffect] 자체가
/// null이라 팩 기본 보이스 + Typecast Smart Emotion(자동 감정) + 중립
/// 피치/템포로 생성된다 — 체크하면 그 순간부터 이 노드만의 값을 하나씩
/// 재정의할 수 있다.
class _TtsEffectRow extends StatelessWidget {
  final TtsEffect? tts;
  final List<AdminTtsVoice> voices;
  final VoidCallback onRefreshVoices;
  final bool refreshingVoices;
  final AdminTtsVoiceRepository ttsVoiceRepository;
  final String packId;
  final String nodeId;
  final List<AdminNodeBlock> blocks;
  final String? defaultTtsVoiceId;

  /// null을 넘기면 "재정의 없음(체크 해제)"으로 되돌린다.
  final ValueChanged<TtsEffect?> onChanged;

  const _TtsEffectRow({
    required this.tts,
    required this.voices,
    required this.onRefreshVoices,
    required this.refreshingVoices,
    required this.ttsVoiceRepository,
    required this.packId,
    required this.nodeId,
    required this.blocks,
    required this.defaultTtsVoiceId,
    required this.onChanged,
  });

  bool get _customized => tts != null;

  @override
  Widget build(BuildContext context) {
    final current = tts ?? const TtsEffect();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _customized,
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AdminColors.gold
                      : AdminColors.checkboxUncheckedFill,
                ),
                checkColor: AdminColors.checkboxCheckColor,
                side: BorderSide(
                  color: AdminColors.checkboxUncheckedBorder,
                  width: 1.5,
                ),
                onChanged: (checked) =>
                    onChanged(checked == true ? const TtsEffect() : null),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TTS 내레이션',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.ivory,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '안 고르면(기본값) 팩 기본 보이스 + 자동 감정으로 낭독돼요',
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
            ),
            _TtsPreviewButton(
              repository: ttsVoiceRepository,
              packId: packId,
              nodeId: nodeId,
              blocks: blocks,
              effectsTts: tts,
              defaultTtsVoiceId: defaultTtsVoiceId,
            ),
          ],
        ),
        if (_customized) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '보이스 재정의',
                  style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                ),
                const SizedBox(height: 6),
                TtsVoicePickerField(
                  currentId: current.voiceId,
                  voices: voices,
                  onRefresh: onRefreshVoices,
                  refreshing: refreshingVoices,
                  noSelectionLabel: '(선택 안 함) 팩 기본 보이스',
                  onChanged: (id) => onChanged(
                    current.copyWith(voiceId: id, clearVoiceId: id == null),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '감정',
                  style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                ),
                const SizedBox(height: 6),
                TtsEmotionDropdown(
                  value: current.emotion,
                  onChanged: (preset) => onChanged(
                    preset == null
                        ? current.copyWith(clearEmotion: true)
                        : current.copyWith(emotion: preset),
                  ),
                ),
                if (current.emotion != null) ...[
                  const SizedBox(height: 14),
                  TtsSlider(
                    label: '감정 강도',
                    valueLabel: current.emotionIntensity.toStringAsFixed(1),
                    value: current.emotionIntensity,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    onChanged: (v) =>
                        onChanged(current.copyWith(emotionIntensity: v)),
                  ),
                ],
                const SizedBox(height: 14),
                TtsSlider(
                  label: '피치',
                  valueLabel: current.pitch.toStringAsFixed(0),
                  value: current.pitch,
                  min: -12,
                  max: 12,
                  divisions: 24,
                  onChanged: (v) => onChanged(current.copyWith(pitch: v)),
                ),
                const SizedBox(height: 14),
                TtsSlider(
                  label: '템포',
                  valueLabel: '${current.tempo.toStringAsFixed(2)}x',
                  value: current.tempo,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  onChanged: (v) => onChanged(current.copyWith(tempo: v)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "미리듣기" 버튼 — previewNodeTts를 불러 지금 화면의(임시저장 전일 수도
/// 있는) 본문+TTS 설정으로 오디오를 만들고, 받은 URL을 바로 재생한다(요청
/// 사양 Part 1-1). 재생 자체는 AudioService.playSfx를 재사용한다 —
/// SfxLibraryTab의 미리듣기 버튼과 똑같은 "1회성 URL 재생" 용도라 새 재생기를
/// 따로 만들 이유가 없다. 여러 번 다시 눌러도 된다 — 설정이 안 바뀌었으면
/// Cloud Function이 캐시를 그대로 돌려주고, 바뀌었으면 그 값으로 다시
/// 생성한다.
class _TtsPreviewButton extends StatefulWidget {
  final AdminTtsVoiceRepository repository;
  final String packId;
  final String nodeId;
  final List<AdminNodeBlock> blocks;
  final TtsEffect? effectsTts;
  final String? defaultTtsVoiceId;

  const _TtsPreviewButton({
    required this.repository,
    required this.packId,
    required this.nodeId,
    required this.blocks,
    required this.effectsTts,
    required this.defaultTtsVoiceId,
  });

  @override
  State<_TtsPreviewButton> createState() => _TtsPreviewButtonState();
}

class _TtsPreviewButtonState extends State<_TtsPreviewButton> {
  bool _loading = false;

  Future<void> _handlePreview() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final url = await widget.repository.previewNodeTts(
        packId: widget.packId,
        nodeId: widget.nodeId,
        blocks: widget.blocks,
        effectsTts: widget.effectsTts,
        defaultTtsVoiceId: widget.defaultTtsVoiceId,
      );
      await AudioService.instance.playSfx(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('미리듣기 생성에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _loading ? null : _handlePreview,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: _loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AdminColors.muted,
              ),
            )
          : Icon(Icons.volume_up_rounded, size: 16, color: AdminColors.gold),
      label: Text(
        _loading ? '생성 중…' : '미리듣기',
        style: TextStyle(fontSize: 12, color: AdminColors.gold),
      ),
    );
  }
}

/// 감정 프리셋 드롭다운 — "자동(Smart Emotion)"이 곧 `value == null`이다.
/// 위의 범용 [_PresetDropdown]은 항목이 전부 non-null이라는 전제로
/// "null이면 콜백을 안 부른다"는 가드를 이미 갖고 있어서(다른 프리셋
/// 드롭다운에서는 문제없다 — 거긴 정말로 null이 될 일이 없다), null 자체가
/// 유효한 선택지인 이 자리에는 재사용할 수 없다 — 그래서 이 위젯만 따로 둔다.
class TtsEmotionDropdown extends StatelessWidget {
  final TtsEmotionPreset? value;
  final ValueChanged<TtsEmotionPreset?> onChanged;

  const TtsEmotionDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TtsEmotionPreset?>(
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: adminInputDecoration(),
      dropdownColor: AdminColors.inputDropdownMenuBg,
      style: TextStyle(color: AdminColors.inputText, fontSize: 12.5),
      items: [
        const DropdownMenuItem<TtsEmotionPreset?>(
          value: null,
          child: Text('자동(Smart Emotion)'),
        ),
        for (final preset in TtsEmotionPreset.values)
          DropdownMenuItem<TtsEmotionPreset?>(
            value: preset,
            child: Text(preset.label),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// 감정 강도/피치/템포 슬라이더 — 셋 다 같은 "라벨 + 슬라이더 + 값 배지"
/// 모양이라 하나로 공유한다.
class TtsSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const TtsSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AdminColors.gold,
              thumbColor: AdminColors.gold,
              inactiveTrackColor: AdminColors.panel2,
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: AdminColors.ivory),
          ),
        ),
      ],
    );
  }
}

/// "화면 플래시" 행 전용 — 나머지 프리셋 행(_EffectRow<T>)은 축 하나(지속
/// 시간 또는 강도)만 고르면 되지만, 플래시는 색(FlashColorPreset)과 지속
/// 시간(FlashDurationPreset) 두 축을 동시에 골라야 해서 드롭다운을 두 개
/// 나란히 놓는다 — 그 점만 빼면 체크박스+라벨 구조는 _EffectRow와 같다.
class _FlashEffectRow extends StatelessWidget {
  final FlashEffect flash;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<FlashColorPreset> onColorChanged;
  final ValueChanged<FlashDurationPreset> onDurationChanged;

  const _FlashEffectRow({
    required this.flash,
    required this.onEnabledChanged,
    required this.onColorChanged,
    required this.onDurationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: flash.enabled,
            fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AdminColors.gold
                  : AdminColors.checkboxUncheckedFill,
            ),
            checkColor: AdminColors.checkboxCheckColor,
            side: BorderSide(
              color: AdminColors.checkboxUncheckedBorder,
              width: 1.5,
            ),
            onChanged: (checked) => onEnabledChanged(checked ?? false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '화면 플래시',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.ivory,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '화면 전체가 짧게 색으로 번쩍여요 (피격/섬광/냉기)',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 128,
              child: _PresetDropdown<FlashColorPreset>(
                value: flash.colorPreset,
                options: FlashColorPreset.values,
                optionLabel: (p) => p.label,
                enabled: flash.enabled,
                onChanged: onColorChanged,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 128,
              child: _PresetDropdown<FlashDurationPreset>(
                value: flash.durationPreset,
                options: FlashDurationPreset.values,
                optionLabel: (p) => p.label,
                enabled: flash.enabled,
                onChanged: onDurationChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// _EffectRow<T>의 드롭다운 부분만 떼어낸 것 — _FlashEffectRow가 한 행에
/// 드롭다운을 두 개(색/지속 시간) 세로로 쌓아야 해서 재사용한다.
class _PresetDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) optionLabel;
  final bool enabled;
  final ValueChanged<T> onChanged;

  const _PresetDropdown({
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: adminInputDecoration(),
      dropdownColor: AdminColors.inputDropdownMenuBg,
      style: TextStyle(
        color: enabled ? AdminColors.inputText : AdminColors.muted,
        fontSize: 12.5,
      ),
      selectedItemBuilder: (context) => [
        for (final option in options)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              optionLabel(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
      ],
      items: [
        for (final option in options)
          DropdownMenuItem<T>(
            value: option,
            child: Text(
              optionLabel(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null) onChanged(value);
            }
          : null,
    );
  }
}

class _EffectRow<T> extends StatelessWidget {
  final String label;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final T presetValue;
  final List<T> presetOptions;
  final String Function(T) presetLabel;
  final ValueChanged<T> onPresetChanged;

  const _EffectRow({
    super.key,
    required this.label,
    required this.description,
    required this.enabled,
    required this.onEnabledChanged,
    required this.presetValue,
    required this.presetOptions,
    required this.presetLabel,
    required this.onPresetChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: enabled,
            fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AdminColors.gold
                  : AdminColors.checkboxUncheckedFill,
            ),
            checkColor: AdminColors.checkboxCheckColor,
            side: BorderSide(
              color: AdminColors.checkboxUncheckedBorder,
              width: 1.5,
            ),
            onChanged: (checked) => onEnabledChanged(checked ?? false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.ivory,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          // "문 여는 소리"(효과음 프리셋 중 가장 긴 라벨)이 안 잘리고 들어갈
          // 만큼 넉넉하게 잡는다. isExpanded/ellipsis는 그래도 안전망으로
          // 같이 둔다 — 폰트/브라우저에 따라 실제 렌더링 폭이 달라질 수 있어서.
          width: 144,
          child: DropdownButtonFormField<T>(
            initialValue: presetValue,
            isDense: true,
            // 기본값(false)이면 드롭다운이 부모가 준 폭을 무시하고 내용물
            // 크기로 스스로를 재려고 해서, 좁은 SizedBox 안에서 텍스트가
            // 옆으로 넘치다 못해 세로로 찌그러져 그려지는 오버플로가
            // 났었다(실제로 겪은 버그) — true로 두면 주어진 폭을 그대로
            // 받아들이고 Text의 overflow 처리가 정상적으로 먹힌다.
            isExpanded: true,
            decoration: adminInputDecoration(),
            dropdownColor: AdminColors.inputDropdownMenuBg,
            style: TextStyle(
              color: enabled ? AdminColors.inputText : AdminColors.muted,
              fontSize: 12.5,
            ),
            selectedItemBuilder: (context) => [
              for (final option in presetOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    presetLabel(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
            ],
            items: [
              for (final option in presetOptions)
                DropdownMenuItem<T>(
                  value: option,
                  child: Text(
                    presetLabel(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) onPresetChanged(value);
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
