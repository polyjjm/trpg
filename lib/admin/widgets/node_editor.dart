import 'package:flutter/material.dart';

import '../models/admin_choice.dart';
import '../models/admin_image.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/pending_action.dart';
import 'admin_theme.dart';
import 'choice_card.dart';
import 'image_picker_field.dart';
import 'info_banner.dart';
import 'labeled_field.dart';

/// main — 선택된 노드 한 편을 편집하는 폼. renderMain()의 스토리 노드 분기를
/// 그대로 옮겼다: 삭제 대기 노드는 배너 + 취소 버튼만 보여주고, 그 외에는
/// 필드 + 선택지 목록 + 저장 바를 보여준다.
class NodeEditor extends StatelessWidget {
  final AdminStoryNode node;
  final bool dirty;
  final bool isIdEditable;
  final List<AdminImage> images;
  final List<AdminStoryNodeSummary> nodeOptions;
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
    required this.nodeOptions,
    required this.onChanged,
    required this.onSaveDraft,
    required this.onRequestApproval,
    required this.onCancelDeleteRequest,
  });

  @override
  Widget build(BuildContext context) {
    if (node.pendingAction == PendingAction.delete) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const InfoBanner(
                style: InfoBannerStyle.dirty,
                text: '이 노드는 삭제 요청이 들어가 있어요. 상위 관리자 승인을 기다리는 중이고, '
                    '그동안 플레이어에게는 계속 원래 내용이 보여요.',
              ),
              OutlinedButton(
                onPressed: onCancelDeleteRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.muted,
                  side: const BorderSide(color: AdminColors.border),
                ),
                child: const Text('삭제 요청 취소하기'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildBanners(),
            LabeledField(
              label: '노드 ID',
              child: TextFormField(
                initialValue: node.id,
                enabled: isIdEditable,
                style: TextStyle(
                  color: isIdEditable ? AdminColors.ivory : AdminColors.muted,
                  fontSize: 13,
                ),
                decoration: adminInputDecoration(),
                onChanged: (value) {
                  node.id = value;
                  onChanged();
                },
              ),
            ),
            if (!isIdEditable)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '이미 저장된 노드의 ID는 바꿀 수 없어요.',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'DAY / 챕터',
                    child: TextFormField(
                      initialValue: '${node.day}',
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                      decoration: adminInputDecoration(),
                      onChanged: (value) {
                        node.day = int.tryParse(value) ?? node.day;
                        onChanged();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LabeledField(
                    label: '제목',
                    child: TextFormField(
                      initialValue: node.title,
                      style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                      decoration: adminInputDecoration(),
                      onChanged: (value) {
                        node.title = value;
                        onChanged();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '본문',
              child: TextFormField(
                initialValue: node.body,
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                decoration: adminInputDecoration(),
                onChanged: (value) {
                  node.body = value;
                  onChanged();
                },
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '배경 이미지',
              child: ImagePickerField(
                currentId: node.bgImageId,
                images: images,
                onChanged: (id) {
                  node.bgImageId = id;
                  onChanged();
                },
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('선택지', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.ivory)),
                TextButton(
                  onPressed: () {
                    node.choices.add(AdminChoice());
                    onChanged();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AdminColors.gold,
                    backgroundColor: AdminColors.panel2,
                    side: const BorderSide(color: AdminColors.border, style: BorderStyle.solid),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('+ 선택지 추가', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < node.choices.length; i++)
              ChoiceCard(
                key: ObjectKey(node.choices[i]),
                index: i,
                choice: node.choices[i],
                images: images,
                nodeOptions: nodeOptions,
                onChanged: onChanged,
                onRemove: () {
                  node.choices.removeAt(i);
                  onChanged();
                },
              ),
            const SizedBox(height: 12),
            _SaveBar(onSaveDraft: onSaveDraft, onRequestApproval: onRequestApproval),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBanners() {
    final banners = <Widget>[];

    if (dirty) {
      banners.add(const InfoBanner(
        style: InfoBannerStyle.dirty,
        text: '저장하지 않은 변경사항이 있어요. "임시저장"을 눌러야 다음에 다시 열었을 때 남아있고, '
            '"승인 요청"을 보내야 상위 관리자 검토 후 플레이어에게 반영돼요.',
      ));
    } else if (node.pendingAction == PendingAction.edit || node.pendingAction == PendingAction.create) {
      final actionLabel = node.pendingAction == PendingAction.create ? '신규 등록' : '수정';
      final visibility = node.liveSnapshot != null
          ? '플레이어에게는 이전 버전이 그대로 보여요.'
          : '플레이어에게는 아직 안 보여요.';
      banners.add(InfoBanner(
        style: InfoBannerStyle.dirty,
        text: '$actionLabel 승인 요청을 보냈어요. 상위 관리자가 검토 중이에요 — 승인 전까지 $visibility',
      ));
    }

    if (node.liveSnapshot != null &&
        node.pendingAction != PendingAction.edit &&
        node.pendingAction != PendingAction.create) {
      banners.add(const InfoBanner(
        style: InfoBannerStyle.live,
        text: '이 노드는 현재 연재 중이에요. 지금 여기서 수정하면 바로 반영되는 게 아니라, '
            '"승인 요청"을 보내서 상위 관리자가 승인해야 실제 반영돼요.',
      ));
    }

    return banners;
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
      decoration: const BoxDecoration(
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
              side: const BorderSide(color: AdminColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('임시저장 (나만 보임)', style: TextStyle(fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: onRequestApproval,
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.gold,
              foregroundColor: const Color(0xFF111111),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('승인 요청 보내기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          OutlinedButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: AdminColors.panel,
                  title: const Text('미리보기', style: TextStyle(color: AdminColors.ivory)),
                  content: const Text(
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
              side: const BorderSide(color: AdminColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('미리보기', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
