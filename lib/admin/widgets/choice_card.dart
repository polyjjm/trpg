import 'package:flutter/material.dart';

import '../models/admin_choice.dart';
import '../models/admin_image.dart';
import '../models/admin_story_node_summary.dart';
import '../models/choice_type.dart';
import '../models/move_mode.dart';
import '../models/random_move_candidate.dart';
import 'admin_theme.dart';
import 'image_picker_field.dart';
import 'labeled_field.dart';
import 'node_dropdown.dart';

/// choice-card — 선택지 하나를 편집하는 카드. 텍스트/이미지/트리거 타입 탭 +
/// 타입별 상세 필드(renderTriggerDetail 대응)로 구성된다.
///
/// [choice]는 부모(NodeEditor)가 들고 있는 노드의 choices 리스트 원소를 그대로
/// 참조로 받아 직접 mutate한다 — 값이 바뀔 때마다 [onChanged]를 불러 부모가
/// setState + dirty 표시를 하게 한다.
class ChoiceCard extends StatelessWidget {
  final int index;
  final AdminChoice choice;
  final List<AdminImage> images;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const ChoiceCard({
    super.key,
    required this.index,
    required this.choice,
    required this.images,
    required this.nodeOptions,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '선택지 ${index + 1}',
                style: const TextStyle(fontSize: 12, color: AdminColors.muted, fontWeight: FontWeight.w700),
              ),
              InkWell(
                onTap: onRemove,
                child: const Text('삭제', style: TextStyle(fontSize: 12, color: AdminColors.danger)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LabeledField(
            label: '버튼에 표시될 텍스트',
            child: TextFormField(
              initialValue: choice.text,
              style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
              decoration: adminInputDecoration(),
              onChanged: (value) {
                choice.text = value;
                onChanged();
              },
            ),
          ),
          const SizedBox(height: 10),
          LabeledField(
            label: '선택지 전용 이미지 (선택 사항 — 안 고르면 노드 배경 그대로 사용)',
            child: ImagePickerField(
              currentId: choice.imageId,
              images: images,
              onChanged: (id) {
                choice.imageId = id;
                onChanged();
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in ChoiceType.values)
                _TriggerTab(
                  label: type.label,
                  selected: choice.type == type,
                  onTap: () {
                    choice.type = type;
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          _TriggerDetail(choice: choice, nodeOptions: nodeOptions, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TriggerTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TriggerTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AdminColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AdminColors.accent : AdminColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : AdminColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF5C4A1F) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AdminColors.gold : AdminColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? AdminColors.gold : AdminColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TriggerDetail extends StatelessWidget {
  final AdminChoice choice;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;

  const _TriggerDetail({required this.choice, required this.nodeOptions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AdminColors.panel2, borderRadius: BorderRadius.circular(8)),
      child: switch (choice.type) {
        ChoiceType.move => _MoveDetail(choice: choice, nodeOptions: nodeOptions, onChanged: onChanged),
        ChoiceType.battle => _BattleDetail(choice: choice, nodeOptions: nodeOptions, onChanged: onChanged),
        ChoiceType.encounter => _EncounterDetail(choice: choice, nodeOptions: nodeOptions, onChanged: onChanged),
        ChoiceType.merchant => _MerchantDetail(choice: choice, nodeOptions: nodeOptions, onChanged: onChanged),
        ChoiceType.item => _ItemDetail(choice: choice, nodeOptions: nodeOptions, onChanged: onChanged),
      },
    );
  }
}

class _MoveDetail extends StatelessWidget {
  final AdminChoice choice;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;

  const _MoveDetail({required this.choice, required this.nodeOptions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ModeTab(
              label: '고정 노드로 이동',
              selected: choice.mode != MoveMode.random,
              onTap: () {
                choice.mode = MoveMode.fixed;
                onChanged();
              },
            ),
            const SizedBox(width: 6),
            _ModeTab(
              label: '여러 노드 중 확률로 랜덤 선택',
              selected: choice.mode == MoveMode.random,
              onTap: () {
                choice.mode = MoveMode.random;
                if (choice.random.isEmpty) {
                  choice.random.add(RandomMoveCandidate(pct: 100));
                }
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (choice.mode == MoveMode.random)
          _RandomMoveEditor(choice: choice, nodeOptions: nodeOptions, onChanged: onChanged)
        else
          LabeledField(
            label: '이동할 노드',
            child: NodeDropdown(
              currentId: choice.target,
              options: nodeOptions,
              onChanged: (id) {
                choice.target = id;
                onChanged();
              },
            ),
          ),
      ],
    );
  }
}

class _RandomMoveEditor extends StatelessWidget {
  final AdminChoice choice;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;

  const _RandomMoveEditor({required this.choice, required this.nodeOptions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final total = choice.random.fold<int>(0, (sum, r) => sum + r.pct);
    final ok = total == 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < choice.random.length; i++)
          Padding(
            key: ObjectKey(choice.random[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: NodeDropdown(
                    currentId: choice.random[i].node,
                    options: nodeOptions,
                    onChanged: (id) {
                      choice.random[i].node = id;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    initialValue: '${choice.random[i].pct}',
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                    decoration: adminInputDecoration(),
                    onChanged: (value) {
                      choice.random[i].pct = int.tryParse(value) ?? 0;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                const Text('%', style: TextStyle(color: AdminColors.muted, fontSize: 12)),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    choice.random.removeAt(i);
                    onChanged();
                  },
                  child: const Text('삭제', style: TextStyle(fontSize: 12, color: AdminColors.danger)),
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: () {
            choice.random.add(RandomMoveCandidate());
            onChanged();
          },
          style: TextButton.styleFrom(
            foregroundColor: AdminColors.gold,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            side: const BorderSide(color: AdminColors.border, style: BorderStyle.solid),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: const Text('+ 후보 노드 추가', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 4),
        Text(
          '합계 $total% ${ok ? '· 정상' : '· 100%가 되어야 저장할 수 있어요'}',
          style: TextStyle(fontSize: 11, color: ok ? AdminColors.ok : AdminColors.danger),
        ),
      ],
    );
  }
}

class _BattleDetail extends StatelessWidget {
  final AdminChoice choice;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;

  const _BattleDetail({required this.choice, required this.nodeOptions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledField(
          label: '전투 설정 ID',
          child: TextFormField(
            initialValue: choice.battleId,
            style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
            decoration: adminInputDecoration(hintText: '예: zombie_01'),
            onChanged: (value) {
              choice.battleId = value;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: '승리 시',
                child: NodeDropdown(
                  currentId: choice.winNode,
                  options: nodeOptions,
                  onChanged: (id) {
                    choice.winNode = id;
                    onChanged();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: '패배 시',
                child: NodeDropdown(
                  currentId: choice.loseNode,
                  options: nodeOptions,
                  onChanged: (id) {
                    choice.loseNode = id;
                    onChanged();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: '도주 시',
                child: NodeDropdown(
                  currentId: choice.escapeNode,
                  options: nodeOptions,
                  onChanged: (id) {
                    choice.escapeNode = id;
                    onChanged();
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EncounterDetail extends StatelessWidget {
  final AdminChoice choice;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;

  const _EncounterDetail({required this.choice, required this.nodeOptions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledField(
          label: '조우 설정 ID',
          child: TextFormField(
            initialValue: choice.encounterId,
            style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
            decoration: adminInputDecoration(hintText: '예: risk_01'),
            onChanged: (value) {
              choice.encounterId = value;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: '극복 시',
                child: NodeDropdown(
                  currentId: choice.winNode,
                  options: nodeOptions,
                  onChanged: (id) {
                    choice.winNode = id;
                    onChanged();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: '탈출 시',
                child: NodeDropdown(
                  currentId: choice.escapeNode,
                  options: nodeOptions,
                  onChanged: (id) {
                    choice.escapeNode = id;
                    onChanged();
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MerchantDetail extends StatelessWidget {
  final AdminChoice choice;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;

  const _MerchantDetail({required this.choice, required this.nodeOptions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: '상인 화면 끝나고 이동할 노드',
      child: NodeDropdown(
        currentId: choice.target,
        options: nodeOptions,
        onChanged: (id) {
          choice.target = id;
          onChanged();
        },
      ),
    );
  }
}

class _ItemDetail extends StatelessWidget {
  final AdminChoice choice;
  final List<AdminStoryNodeSummary> nodeOptions;
  final VoidCallback onChanged;

  const _ItemDetail({required this.choice, required this.nodeOptions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: '아이템 ID',
                child: TextFormField(
                  initialValue: choice.itemId,
                  style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: bandage_01'),
                  onChanged: (value) {
                    choice.itemId = value;
                    onChanged();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: '개수',
                child: TextFormField(
                  initialValue: '${choice.itemCount}',
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(),
                  onChanged: (value) {
                    choice.itemCount = int.tryParse(value) ?? 1;
                    onChanged();
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LabeledField(
          label: '획득 후 이동할 노드',
          child: NodeDropdown(
            currentId: choice.target,
            options: nodeOptions,
            onChanged: (id) {
              choice.target = id;
              onChanged();
            },
          ),
        ),
      ],
    );
  }
}
