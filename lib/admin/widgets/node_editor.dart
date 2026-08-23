import 'package:flutter/material.dart';

import '../data/admin_tts_voice_repository.dart';
import '../models/admin_bgm.dart';
import '../models/admin_image.dart';
import '../models/admin_image_category.dart';
import '../models/admin_sfx.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_tts_voice.dart';
import '../models/pending_action.dart';
import '../models/story_pack_type.dart';
import 'admin_theme.dart';
import 'choice_target_picker.dart';
import 'image_picker_field.dart';
import 'info_banner.dart';
import 'labeled_field.dart';
import 'node_body_blocks_editor.dart';
import 'node_choice_editor.dart';
import 'node_effects_editor.dart';

/// 데스크톱 폭 기준 — 이 폭 이상에서 배경/연출 효과를 접힘 필이 아니라
/// 나란한 2단으로 펼쳐 둔다.
const double _nodeEditorWideBreakpoint = 1000;

/// 배경 카드 폭(2단 왼쪽). 오른쪽 연출 효과 칩들이 남는 폭을 쓴다.
const double _backgroundColumnWidth = 320;

/// 본문 읽기 폭 — 예전엔 680이었는데, 데스크톱에서 배경/연출 효과를 2단으로
/// 놓으려면 한 줄에 두 블록이 들어갈 폭이 필요하다. 본문 자체는 여전히
/// 한 줄이 너무 길어지지 않는 선에서 멈춘다.
const double _nodeEditorMaxWidth = 840;

/// main — 선택된 노드 한 편을 편집하는 하나로 이어진 "쓰기 카드": 헤더 →
/// 본문 문단 → 선택지/다음 노드 → 배경 + 연출 효과 → 저장 바.
///
/// [packType]에 따라 분기 UI가 갈린다 — interactive면 선택지 목록, linear면
/// "다음 노드" 선택기 한 줄만.
///
/// 배경/연출 효과의 표현이 폭에 따라 갈린다:
///
/// - 좁은 폭: 예전 그대로 "배경 ⌄" / "연출 효과 ⌄" 접힘 필. 폭이 없으니
///   펼쳐 두면 본문이 밀려 내려간다.
/// - 데스크톱([_nodeEditorWideBreakpoint] 이상): 접지 않고 **나란한 2단으로
///   항상 펼쳐 둔다** — 왼쪽에 배경 카드(썸네일 + 이름), 오른쪽에 연출 효과를
///   칩 묶음으로. 켜진 효과만 코랄로 도드라지므로, 접힌 필에 점 하나로
///   "뭔가 있다"고만 알려주던 것과 달리 **무엇이 켜져 있는지** 한눈에 읽힌다.
///   칩을 누르면 그 효과의 상세(NodeEffectsEditor)가 아래에 펼쳐진다.
///
/// 순서도 바뀌었다 — 선택지/다음 노드가 배경·연출 효과보다 위로 올라왔다.
/// 이야기가 어디로 이어지는지가 연출보다 먼저 결정되는 일이라서다.
class NodeEditor extends StatefulWidget {
  final AdminStoryNode node;
  final bool dirty;
  final bool isIdEditable;
  final List<AdminImage> images;
  final List<AdminSfx> sfxLibrary;
  final List<AdminBgm> bgmLibrary;
  final List<AdminTtsVoice> ttsVoices;
  final VoidCallback onRefreshTtsVoices;
  final bool refreshingTtsVoices;

  /// "미리듣기" 버튼(NodeEffectsEditor 안)이 previewNodeTts를 부르는 데
  /// 필요하다 — packId는 이 노드가 속한 팩, defaultTtsVoiceId는 그 팩의
  /// 기본 내레이터 보이스(팩 설정에서 승인된 값).
  final AdminTtsVoiceRepository ttsVoiceRepository;
  final String packId;
  final String? defaultTtsVoiceId;

  final StoryPackType packType;

  /// 이동 대상 후보(선택지/다음 노드 선택기용) — 저장된 노드 + 세션 캐시
  /// 초안을 합친 목록(story_tab_view.dart의 displaySummaries).
  final List<AdminStoryNodeSummary> candidates;

  /// 이 노드가 배경 이미지를 명시적으로 안 골랐을 때 실제로 쓰일 값
  /// (lib/core/story/background_image_inheritance.dart로 미리 계산해 전달됨).
  /// null이면 이어받을 값도 없다는 뜻.
  final String? inheritedBackgroundImageId;

  /// 스토리맵에서 "+" 드래그로 빈 캔버스에 놓아 방금 만들어진 노드를 열었을
  /// 때만 값이 있다 — 그 출발 노드의 id.
  final String? creationSourceId;

  final VoidCallback onChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onCancelDeleteRequest;

  const NodeEditor({
    super.key,
    required this.node,
    required this.dirty,
    required this.isIdEditable,
    required this.images,
    required this.sfxLibrary,
    required this.bgmLibrary,
    required this.ttsVoices,
    required this.onRefreshTtsVoices,
    required this.refreshingTtsVoices,
    required this.ttsVoiceRepository,
    required this.packId,
    required this.defaultTtsVoiceId,
    required this.packType,
    required this.candidates,
    required this.inheritedBackgroundImageId,
    this.creationSourceId,
    required this.onChanged,
    required this.onSaveDraft,
    required this.onCancelDeleteRequest,
  });

  @override
  State<NodeEditor> createState() => _NodeEditorState();
}

class _NodeEditorState extends State<NodeEditor> {
  // 좁은 폭 전용 접힘 상태 — 데스크톱에서는 쓰지 않는다(항상 펼침).
  bool _backgroundExpanded = false;
  bool _effectsExpanded = false;

  /// 데스크톱에서 연출 효과 칩을 눌러 상세를 펼쳤는지.
  bool _effectDetailExpanded = false;

  AdminStoryNode get node => widget.node;

  @override
  Widget build(BuildContext context) {
    if (node.pendingAction == PendingAction.delete) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const InfoBanner(
                style: InfoBannerStyle.dirty,
                text:
                '이 노드는 삭제 요청이 들어가 있어요. 상위 관리자 승인을 기다리는 중이고, '
                    '그동안 플레이어에게는 계속 원래 내용이 보여요.',
              ),
              OutlinedButton(
                onPressed: widget.onCancelDeleteRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.muted,
                  side: BorderSide(color: AdminColors.border),
                ),
                child: const Text('삭제 요청 취소하기'),
              ),
            ],
          ),
        ),
      );
    }

    final isWide =
        MediaQuery.sizeOf(context).width >= _nodeEditorWideBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _nodeEditorMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildBanners(),
            _Header(node: node, creationSourceId: widget.creationSourceId),
            const SizedBox(height: 4),
            _MetaRow(
              node: node,
              isIdEditable: widget.isIdEditable,
              onChanged: widget.onChanged,
            ),
            const SizedBox(height: 22),
            _SectionLabel(
              '본문',
              trailing: '문단 ${node.blocks.length}',
            ),
            const SizedBox(height: 10),
            NodeBodyBlocksEditor(
              blocks: node.blocks,
              onChanged: widget.onChanged,
              showTtsOverride: widget.packType == StoryPackType.interactive,
              ttsVoices: widget.ttsVoices,
              onRefreshTtsVoices: widget.onRefreshTtsVoices,
              refreshingTtsVoices: widget.refreshingTtsVoices,
            ),
            const SizedBox(height: 20),
            Divider(color: AdminColors.border, height: 1),
            const SizedBox(height: 20),
            if (widget.packType == StoryPackType.interactive)
              NodeChoiceEditor(
                choices: node.choices,
                candidates: widget.candidates,
                onChanged: widget.onChanged,
              )
            else
              SizedBox(
                width: 400,
                child: LabeledField(
                  label: '다음 페이지',
                  child: ChoiceTargetPicker(
                    selectedId: node.nextNodeId,
                    candidates: widget.candidates
                        .where((c) => c.id != node.id)
                        .toList(),
                    onSelected: (id) {
                      node.nextNodeId = id;
                      widget.onChanged();
                    },
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Divider(color: AdminColors.border, height: 1),
            const SizedBox(height: 20),
            if (isWide) ..._buildWideStagingSections() else ..._buildNarrowStagingSections(),
            const SizedBox(height: 20),
            _SaveBar(onSaveDraft: widget.onSaveDraft),
          ],
        ),
      ),
    );
  }

  /// 데스크톱 — 배경(왼쪽 고정폭) | 연출 효과 칩(오른쪽)을 나란히, 항상 펼친
  /// 상태로 둔다. 칩을 누르면 아래에 NodeEffectsEditor가 펼쳐진다.
  List<Widget> _buildWideStagingSections() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _backgroundColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('배경'),
                const SizedBox(height: 10),
                _BackgroundSection(
                  node: node,
                  images: widget.images,
                  inheritedBackgroundImageId: widget.inheritedBackgroundImageId,
                  onChanged: widget.onChanged,
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('연출 효과'),
                const SizedBox(height: 10),
                _EffectChipRow(
                  node: node,
                  expanded: _effectDetailExpanded,
                  onToggle: () => setState(
                        () => _effectDetailExpanded = !_effectDetailExpanded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (_effectDetailExpanded) ...[
        const SizedBox(height: 16),
        _buildEffectsEditor(),
      ],
    ];
  }

  /// 좁은 폭 — 예전 그대로 접힘 필 두 개.
  List<Widget> _buildNarrowStagingSections() {
    final hasBackground = node.backgroundImageId != null;
    final hasEffect = _hasAnyEffect(node);

    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SectionPill(
            label: '배경',
            expanded: _backgroundExpanded,
            filled: hasBackground,
            onTap: () =>
                setState(() => _backgroundExpanded = !_backgroundExpanded),
          ),
          _SectionPill(
            label: '연출 효과',
            expanded: _effectsExpanded,
            filled: hasEffect,
            onTap: () => setState(() => _effectsExpanded = !_effectsExpanded),
          ),
        ],
      ),
      if (_backgroundExpanded) ...[
        const SizedBox(height: 12),
        _BackgroundSection(
          node: node,
          images: widget.images,
          inheritedBackgroundImageId: widget.inheritedBackgroundImageId,
          onChanged: widget.onChanged,
        ),
      ],
      if (_effectsExpanded) ...[
        const SizedBox(height: 12),
        _buildEffectsEditor(),
      ],
    ];
  }

  Widget _buildEffectsEditor() {
    return NodeEffectsEditor(
      effects: node.effects,
      sfxLibrary: widget.sfxLibrary,
      bgmLibrary: widget.bgmLibrary,
      ttsVoices: widget.ttsVoices,
      onRefreshTtsVoices: widget.onRefreshTtsVoices,
      refreshingTtsVoices: widget.refreshingTtsVoices,
      ttsVoiceRepository: widget.ttsVoiceRepository,
      packId: widget.packId,
      nodeId: node.id,
      blocks: node.blocks,
      defaultTtsVoiceId: widget.defaultTtsVoiceId,
      onChanged: (effects) {
        node.effects = effects;
        widget.onChanged();
      },
    );
  }

  List<Widget> _buildBanners() {
    final banners = <Widget>[];

    // 반려 사유는 dirty/승인대기 상태와 별개로 항상 먼저 보여준다 — 반려된
    // 노드를 고치는 중(dirty)이어도 "왜 반려됐는지"를 계속 볼 수 있어야
    // 한다. 재제출하면 이 필드가 지워지므로, 반려 사유가 남아 있다는 것
    // 자체가 "아직 안 고쳐서 다시 안 보냈다"는 뜻이다.
    final rejectionReason = node.rejectionReason;
    if (rejectionReason != null && rejectionReason.isNotEmpty) {
      banners.add(
        InfoBanner(
          style: InfoBannerStyle.rejected,
          text:
          '반려됐어요: $rejectionReason\n'
              '고친 뒤 임시저장하고, 상단의 "변경사항 전체 승인요청"으로 다시 제출해주세요.',
        ),
      );
    }

    if (widget.dirty) {
      banners.add(
        const InfoBanner(
          style: InfoBannerStyle.dirty,
          text:
          '저장하지 않은 변경사항이 있어요. "임시저장"을 눌러야 다음에 다시 열었을 때 남아있고, '
              '상단의 "변경사항 전체 승인요청"을 보내야 상위 관리자 검토 후 플레이어에게 반영돼요.',
        ),
      );
    } else if (node.pendingAction == PendingAction.edit ||
        node.pendingAction == PendingAction.create) {
      final actionLabel = node.pendingAction == PendingAction.create
          ? '신규 등록'
          : '수정';
      final visibility = node.liveSnapshot != null
          ? '플레이어에게는 이전 버전이 그대로 보여요.'
          : '플레이어에게는 아직 안 보여요.';
      banners.add(
        InfoBanner(
          style: InfoBannerStyle.dirty,
          text:
          '$actionLabel 승인 요청을 보냈어요. 상위 관리자가 검토 중이에요 — 승인 전까지 $visibility',
        ),
      );
    }

    if (node.liveSnapshot != null &&
        node.pendingAction != PendingAction.edit &&
        node.pendingAction != PendingAction.create) {
      banners.add(
        const InfoBanner(
          style: InfoBannerStyle.live,
          text:
          '이 노드는 현재 연재 중이에요. 지금 여기서 수정하면 바로 반영되는 게 아니라, '
              '상단의 "변경사항 전체 승인요청"을 보내서 상위 관리자가 승인해야 실제 반영돼요.',
        ),
      );
    }

    if (banners.isNotEmpty) banners.add(const SizedBox(height: 4));
    return banners;
  }
}

bool _hasAnyEffect(AdminStoryNode node) {
  return node.effects.blackout.enabled ||
      node.effects.shake.enabled ||
      node.effects.sfx.enabled ||
      node.effects.haptic.enabled ||
      node.effects.bgm != null ||
      node.effects.tts != null;
}

/// 섹션 제목 — "본문" / "배경" / "연출 효과". 예전엔 배경/연출 효과가 접힘
/// 필이라 제목이 없었다.
class _SectionLabel extends StatelessWidget {
  final String label;
  final String? trailing;

  const _SectionLabel(this.label, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AdminColors.ivory,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing,
            style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
          ),
        ],
      ],
    );
  }
}

/// 연출 효과 여섯 개를 칩 한 줄로 — 켜진 것만 코랄 테두리 + 옅은 코랄 채움에
/// 현재 값을 함께 적는다(예: 암전 0.8s, 배경음악 이전과 동일). 접힌 필에
/// 점 하나로 "뭔가 있다"고만 알려주던 예전과 달리, 무엇이 켜져 있는지 여기서
/// 바로 읽힌다.
///
/// 칩은 개별 토글이 아니라 상세 편집기를 여는 입구다 — 효과마다 값이 여러
/// 개라(암전은 길이, 효과음은 어떤 소리, BGM은 트랙/무음 등) 칩 하나로
/// 켜고 끌 수 있는 게 아니다.
class _EffectChipRow extends StatelessWidget {
  final AdminStoryNode node;
  final bool expanded;
  final VoidCallback onToggle;

  const _EffectChipRow({
    required this.node,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final effects = node.effects;

    // 길이는 자유 숫자가 아니라 프리셋 enum(BlackoutDurationPreset 등)이라
    // 칩에 값으로 적기엔 이름이 길다 — 켜졌는지만 표시하고, 구체적인 값은
    // "효과 설정 열기"로 펼친 NodeEffectsEditor에서 본다.
    final chips = <Widget>[
      _EffectChip(
        icon: Icons.brightness_2_rounded,
        label: '암전',
        value: effects.blackout.enabled ? '켜짐' : null,
        onTap: onToggle,
      ),
      _EffectChip(
        icon: Icons.vibration_rounded,
        label: '화면 흔들림',
        value: effects.shake.enabled ? '켜짐' : null,
        onTap: onToggle,
      ),
      _EffectChip(
        icon: Icons.smartphone_rounded,
        label: '진동',
        value: effects.haptic.enabled ? '켜짐' : null,
        onTap: onToggle,
      ),
      _EffectChip(
        icon: Icons.music_note_rounded,
        label: '배경음악',
        value: effects.bgm == null ? null : '설정됨',
        onTap: onToggle,
      ),
      _EffectChip(
        icon: Icons.graphic_eq_rounded,
        label: '효과음',
        value: effects.sfx.enabled ? '설정됨' : null,
        onTap: onToggle,
      ),
      _EffectChip(
        icon: Icons.record_voice_over_rounded,
        label: 'TTS 보이스',
        value: effects.tts == null ? null : '설정됨',
        onTap: onToggle,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: chips),
        const SizedBox(height: 8),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: AdminColors.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  expanded ? '효과 설정 접기' : '효과 설정 열기',
                  style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EffectChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// null이면 이 효과는 꺼져 있다 — 테두리만 있는 중성 칩.
  final String? value;
  final VoidCallback onTap;

  const _EffectChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on
              ? AdminColors.gold.withOpacity(0.10)
              : AdminColors.panel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on
                ? AdminColors.gold.withOpacity(0.45)
                : AdminColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: on ? AdminColors.ivory : AdminColors.muted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: on ? AdminColors.ivory : AdminColors.muted,
              ),
            ),
            if (on) ...[
              const SizedBox(width: 7),
              Text(
                value!,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.gold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 카드 상단 — 아이콘 + "노드 {id} · {짧은 라벨}". 짧은 라벨은
/// [shortNodeLabel](admin_story_node_summary.dart)을 그대로 쓴다. 단,
/// 스토리맵의 "+" 드래그로 방금 만들어진 노드는 아직 본문이 비어 있어 그
/// 계산이 무의미하므로 "새 노드 ({sourceId}에서 연결됨)"을 보여준다.
class _Header extends StatelessWidget {
  final AdminStoryNode node;
  final String? creationSourceId;

  const _Header({required this.node, required this.creationSourceId});

  String get _label {
    final sourceId = creationSourceId;
    if (sourceId != null) return '새 노드 ($sourceId에서 연결됨)';
    return shortNodeLabel(
      id: node.id,
      firstBlockText: node.blocks.isNotEmpty ? node.blocks.first.text : '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.edit_note_rounded, size: 22, color: AdminColors.gold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '노드 ${node.id} · $_label',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AdminColors.ivory,
            ),
          ),
        ),
      ],
    );
  }
}

/// id(신규 노드만 편집 가능)/순서 — 헤더 바로 아래, 작고 눈에 덜 띄게.
class _MetaRow extends StatelessWidget {
  final AdminStoryNode node;
  final bool isIdEditable;
  final VoidCallback onChanged;

  const _MetaRow({
    required this.node,
    required this.isIdEditable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (isIdEditable)
          SizedBox(
            width: 200,
            child: TextFormField(
              initialValue: node.id,
              style: TextStyle(color: AdminColors.inputText, fontSize: 12.5),
              decoration: adminInputDecoration(hintText: '노드 ID').copyWith(
                isDense: true,
                prefixIcon: const Icon(Icons.tag_rounded, size: 14),
              ),
              onChanged: (value) {
                node.id = value;
                onChanged();
              },
            ),
          )
        else
          Text(
            '이미 저장된 노드의 ID는 바꿀 수 없어요.',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        SizedBox(
          width: 130,
          child: TextFormField(
            initialValue: '${node.order}',
            keyboardType: TextInputType.number,
            style: TextStyle(color: AdminColors.inputText, fontSize: 12.5),
            decoration: adminInputDecoration(hintText: '순서 (배경 인계 기준)')
                .copyWith(
              isDense: true,
              prefixIcon: const Icon(Icons.sort_rounded, size: 14),
            ),
            onChanged: (value) {
              node.order = int.tryParse(value) ?? node.order;
              onChanged();
            },
          ),
        ),
      ],
    );
  }
}

/// 좁은 폭 전용 "배경"/"연출 효과" 접힘 토글 — 필(pill) 모양, 값이 채워져
/// 있으면 작은 점을 하나 더 보여준다.
class _SectionPill extends StatelessWidget {
  final String label;
  final bool expanded;
  final bool filled;
  final VoidCallback onTap;

  const _SectionPill({
    required this.label,
    required this.expanded,
    required this.filled,
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
          color: expanded ? AdminColors.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: expanded ? AdminColors.gold : AdminColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filled) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AdminColors.gold,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: expanded ? AdminColors.ivory : AdminColors.muted,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 16,
              color: AdminColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// 배경 이미지 선택기 + 인계 안내 문구 + 이후 노드 적용 체크박스.
class _BackgroundSection extends StatelessWidget {
  final AdminStoryNode node;
  final List<AdminImage> images;
  final String? inheritedBackgroundImageId;
  final VoidCallback onChanged;

  const _BackgroundSection({
    required this.node,
    required this.images,
    required this.inheritedBackgroundImageId,
    required this.onChanged,
  });

  String _inheritanceHint() {
    final inherited = inheritedBackgroundImageId;
    if (inherited == null) {
      return '(기본값 없음 — 이 노드부터 배경 이미지가 표시되지 않아요)';
    }
    final matchingImage = images
        .where((img) => img.id == inherited)
        .firstOrNull;
    final label = matchingImage?.name ?? inherited;
    return '(기본값 사용 · 이전 노드에서 이어짐: $label)';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ImagePickerField(
          currentId: node.backgroundImageId,
          images: images,
          filterCategory: AdminImageCategory.background,
          onChanged: (id) {
            node.backgroundImageId = id;
            onChanged();
          },
        ),
        if (node.backgroundImageId == null) ...[
          const SizedBox(height: 6),
          Text(
            _inheritanceHint(),
            style: const TextStyle(fontSize: 11, color: AdminColors.gold),
          ),
        ] else ...[
          const SizedBox(height: 10),
          _BackgroundAppliesForwardToggle(
            value: node.backgroundAppliesForward,
            onChanged: (value) {
              node.backgroundAppliesForward = value;
              onChanged();
            },
          ),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// 배경 이미지를 명시적으로 고른 노드에서만 보이는 체크박스 — 인계 체인
/// 자체는 이미 동작하던 기존 로직(lib/core/story/
/// background_image_inheritance.dart)이고, 이 위젯은 그 동작을 작가에게
/// 눈에 보이게 확인시켜 줄 뿐이다.
class _BackgroundAppliesForwardToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BackgroundAppliesForwardToggle({
    required this.value,
    required this.onChanged,
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
            value: value,
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
            onChanged: (checked) => onChanged(checked ?? true),
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
                  '이후 노드부터 배경이 바뀔 때까지 자동으로 이어서 적용',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AdminColors.ivory,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value
                      ? '체크 해제하면 이 배경은 이 노드에만 적용돼요.'
                      : '지금은 이 노드에만 적용돼요.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AdminColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 저장 바 — 노드별 "승인 요청"은 여기 없다. 승인은 상단 바의
/// "변경사항 전체 승인요청" 하나로 이 팩의 미제출 변경사항을 한 번에 모아
/// 보낸다. 여기 남은 건 "나만 보이는" 임시저장뿐이다.
///
/// 예전에 여기 있던 "미리보기" 버튼은 제거했다 — 누르면 "실제 구현되면"
/// 이라는 안내만 뜨는 껍데기였고, 미리보기는 작업 툴바 줄의
/// "이 노드부터 미리보기"(새 창)로 옮겨간다.
class _SaveBar extends StatelessWidget {
  final VoidCallback onSaveDraft;

  const _SaveBar({required this.onSaveDraft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AdminColors.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton(
            onPressed: onSaveDraft,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.ivory,
              side: BorderSide(color: AdminColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '임시저장 (나만 보임)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '승인 요청은 상단의 "변경사항 전체 승인요청"으로 한 번에 보내요.',
            style: TextStyle(fontSize: 11.5, color: AdminColors.muted),
          ),
        ],
      ),
    );
  }
}
