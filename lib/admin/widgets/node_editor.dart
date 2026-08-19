import 'package:flutter/material.dart';

import '../models/admin_image.dart';
import '../models/admin_image_category.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
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

/// main — 선택된 노드 한 편을 편집하는 하나로 이어진 "쓰기 카드". 예전엔
/// 라벨 붙은 필드들을 위에서 아래로 순서대로 배치한 폼이었는데("기술적인
/// 서식 작성"에 가까웠다), 이번 패스에서 헤더 → 본문 문단 → (접힌) 배경/연출
/// 효과 → 선택지/다음 노드 → 저장 바 순서의 통 카드로 다시 짰다 — 본문에
/// 무게를 싣고, 배경/연출 효과처럼 자주 안 건드리는 설정은 접어 둔다.
///
/// [packType]에 따라 아래쪽 분기 UI가 갈린다 — interactive면 선택지 목록,
/// linear면 "다음 노드" 선택기 한 줄만.
class NodeEditor extends StatefulWidget {
  final AdminStoryNode node;
  final bool dirty;
  final bool isIdEditable;
  final List<AdminImage> images;
  final StoryPackType packType;

  /// 이동 대상 후보(선택지/다음 노드 선택기용) — 저장된 노드 + 세션 캐시
  /// 초안을 합친 목록(story_tab_view.dart의 displaySummaries)을 그대로
  /// 받는다.
  final List<AdminStoryNodeSummary> candidates;

  /// 이 노드가 배경 이미지를 명시적으로 안 골랐을 때 실제로 쓰일 값
  /// (lib/core/story/background_image_inheritance.dart로 미리 계산해 전달됨).
  /// null이면 이어받을 값도 없다는 뜻.
  final String? inheritedBackgroundImageId;

  /// 스토리맵에서 "+" 드래그로 빈 캔버스에 놓아 방금 만들어진 노드를 열었을
  /// 때만 값이 있다 — 그 출발 노드의 id. 헤더가 짧은 라벨 대신 "새 노드
  /// ({sourceId}에서 연결됨)"을 보여주는 데 쓴다(story_map_choice_popover_spec.md).
  final String? creationSourceId;

  final VoidCallback onChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onRequestApproval;
  final VoidCallback onCancelDeleteRequest;

  const NodeEditor({
    super.key,
    required this.node,
    required this.dirty,
    required this.isIdEditable,
    required this.images,
    required this.packType,
    required this.candidates,
    required this.inheritedBackgroundImageId,
    this.creationSourceId,
    required this.onChanged,
    required this.onSaveDraft,
    required this.onRequestApproval,
    required this.onCancelDeleteRequest,
  });

  @override
  State<NodeEditor> createState() => _NodeEditorState();
}

class _NodeEditorState extends State<NodeEditor> {
  bool _backgroundExpanded = false;
  bool _effectsExpanded = false;

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

    final hasBackground = node.backgroundImageId != null;
    final hasEffect =
        node.effects.blackout.enabled ||
        node.effects.shake.enabled ||
        node.effects.sfx.enabled ||
        node.effects.haptic.enabled;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
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
            const SizedBox(height: 20),
            NodeBodyBlocksEditor(
              blocks: node.blocks,
              onChanged: widget.onChanged,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SectionPill(
                  label: '배경',
                  expanded: _backgroundExpanded,
                  filled: hasBackground,
                  onTap: () => setState(
                    () => _backgroundExpanded = !_backgroundExpanded,
                  ),
                ),
                _SectionPill(
                  label: '연출 효과',
                  expanded: _effectsExpanded,
                  filled: hasEffect,
                  onTap: () =>
                      setState(() => _effectsExpanded = !_effectsExpanded),
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
              NodeEffectsEditor(
                effects: node.effects,
                onChanged: (effects) {
                  node.effects = effects;
                  widget.onChanged();
                },
              ),
            ],
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
              LabeledField(
                label: '다음 노드',
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
            const SizedBox(height: 12),
            _SaveBar(
              onSaveDraft: widget.onSaveDraft,
              onRequestApproval: widget.onRequestApproval,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBanners() {
    final banners = <Widget>[];

    if (widget.dirty) {
      banners.add(
        const InfoBanner(
          style: InfoBannerStyle.dirty,
          text:
              '저장하지 않은 변경사항이 있어요. "임시저장"을 눌러야 다음에 다시 열었을 때 남아있고, '
              '"승인 요청"을 보내야 상위 관리자 검토 후 플레이어에게 반영돼요.',
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
              '"승인 요청"을 보내서 상위 관리자가 승인해야 실제 반영돼요.',
        ),
      );
    }

    if (banners.isNotEmpty) banners.add(const SizedBox(height: 4));
    return banners;
  }
}

/// 카드 상단 — 아이콘 + "노드 {id} · {짧은 라벨}". 짧은 라벨은
/// [shortNodeLabel](admin_story_node_summary.dart, ChoiceTargetPicker 카드/
/// 스토리맵 팝오버와 같은 계산)을 그대로 쓴다. 단, 스토리맵의 "+" 드래그로
/// 방금 만들어진 노드([creationSourceId]가 있는 경우)는 아직 본문이 비어
/// 있어 그 계산이 무의미하므로, 대신 "새 노드 ({sourceId}에서 연결됨)"을
/// 보여준다(story_map_choice_popover_spec.md).
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
/// 카드가 "쓰기"에 무게를 싣게 된 뒤로 이 두 필드는 부차적인 메타데이터로
/// 취급한다(예전엔 각각 큼직한 LabeledField 블록이었다).
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

/// "배경"/"연출 효과" 접힘 토글 — 필(pill) 모양, 값이 채워져 있으면 작은
/// 점을 하나 더 보여준다(둘 다 접혀 있어도 "이 노드에 배경/효과가 있다"는
/// 걸 알 수 있게).
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

/// "배경" 필을 펼쳤을 때 보이는 내용 — 예전 폼에 있던 배경 이미지
/// 선택기/인계 안내 문구/이후 노드 적용 체크박스를 그대로 옮겨왔다.
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
/// 눈에 보이게 확인시켜 줄 뿐이다. 기본값(체크됨)은 지금까지의 동작 그대로다.
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
                    fontSize: 13,
                    color: AdminColors.ivory,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value
                      ? '체크 해제하면 이 배경은 이 노드에만 적용돼요. 다음 노드부터는 이 노드가 '
                            '없었던 것처럼, 그 이전에 이어져 오던 배경(또는 기본 배경)으로 돌아가요.'
                      : '지금은 이 노드에만 적용돼요. 다음 노드부터는 이 노드가 없었던 것처럼, 그 이전에 '
                            '이어져 오던 배경(또는 기본 배경)이 계속 이어져요.',
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

class _SaveBar extends StatelessWidget {
  final VoidCallback onSaveDraft;
  final VoidCallback onRequestApproval;

  const _SaveBar({required this.onSaveDraft, required this.onRequestApproval});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AdminColors.border)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton(
            onPressed: onSaveDraft,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.muted,
              side: BorderSide(color: AdminColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('임시저장 (나만 보임)', style: TextStyle(fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: onRequestApproval,
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.gold,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '승인 요청 보내기',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: AdminColors.panel,
                  title: Text(
                    '미리보기',
                    style: TextStyle(color: AdminColors.ivory),
                  ),
                  content: Text(
                    '실제 구현되면 여기서 바로 플레이해볼 수 있어요.',
                    style: TextStyle(color: AdminColors.muted),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.muted,
              side: BorderSide(color: AdminColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('미리보기', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
