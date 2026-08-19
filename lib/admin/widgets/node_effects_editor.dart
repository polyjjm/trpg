import 'package:flutter/material.dart';

import '../models/node_effects.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';

/// "연출 효과" 섹션 — 프리셋 전용 4종(암전/화면 흔들림/효과음/진동)만
/// 다룬다 — 자유 설정이 없어서 비개발자 작가도 무슨 값을 넣어야 할지 고민할
/// 필요가 없다. 실제 재생(사운드 파일, 진동 API)은 아직 안 붙어 있다 —
/// 여기서 고른 값은 지금은 그냥 기록만 되고, 리더가 실제로 재생하게 만드는
/// 건 에셋이 준비된 다음 패스의 몫이다.
///
/// 접고 펴는 건 이 위젯 바깥(node_editor.dart의 "연출 효과" 필/토글)이
/// 맡는다 — 예전엔 여기 자체가 ExpansionTile이었는데, 노드 에디터 전체를
/// 통 카드로 다시 짠 뒤로는 그 바깥 토글과 겹쳐 접었다 펴는 UI가 두 겹이
/// 되는 게 이상해서, 그 껍데기(제목 줄 + 화살표)만 걷어내고 효과별 행들은
/// 그대로 옮겨왔다 — 실제 편집 로직/각 행의 모양은 손대지 않았다.
class NodeEffectsEditor extends StatelessWidget {
  final NodeEffects effects;
  final ValueChanged<NodeEffects> onChanged;

  const NodeEffectsEditor({
    super.key,
    required this.effects,
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
        _EffectRow<SfxPreset>(
          label: '효과음',
          description: '프리셋 효과음 중 하나를 골라요',
          enabled: effects.sfx.enabled,
          onEnabledChanged: (value) => onChanged(
            effects.copyWith(sfx: effects.sfx.copyWith(enabled: value)),
          ),
          presetValue: effects.sfx.preset,
          presetOptions: SfxPreset.values,
          presetLabel: (p) => p.label,
          onPresetChanged: (preset) => onChanged(
            effects.copyWith(sfx: effects.sfx.copyWith(preset: preset)),
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
