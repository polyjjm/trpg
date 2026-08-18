import 'package:flutter/material.dart';

import '../models/admin_image.dart';
import '../models/admin_story_node.dart';
import '../models/pending_action.dart';
import '../models/story_pack_type.dart';
import 'admin_theme.dart';
import 'image_picker_field.dart';
import 'info_banner.dart';
import 'labeled_field.dart';
import 'node_body_editor.dart';
import 'node_choice_editor.dart';

/// main — 선택된 노드 한 편을 편집하는 폼. 삭제 대기 노드는 배너 + 취소
/// 버튼만 보여주고, 그 외에는 필드 + 본문 + (팩 타입에 따라) 선택지 목록
/// 또는 다음 노드 입력 + 저장 바를 보여준다.
///
/// [packType]에 따라 아래쪽 분기 UI가 갈린다 — interactive면 선택지 목록,
/// linear면 "다음 노드" 입력 한 줄만.
class NodeEditor extends StatelessWidget {
  final AdminStoryNode node;
  final bool dirty;
  final bool isIdEditable;
  final List<AdminImage> images;
  final StoryPackType packType;

  /// 이 노드가 배경 이미지를 명시적으로 안 골랐을 때 실제로 쓰일 값
  /// (lib/core/story/background_image_inheritance.dart로 미리 계산해 전달됨).
  /// null이면 이어받을 값도 없다는 뜻.
  final String? inheritedBackgroundImageId;

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
    required this.inheritedBackgroundImageId,
    required this.onChanged,
    required this.onSaveDraft,
    required this.onRequestApproval,
    required this.onCancelDeleteRequest,
  });

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
                onPressed: onCancelDeleteRequest,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
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
                  color: isIdEditable
                      ? AdminColors.inputText
                      : AdminColors.muted,
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
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '이미 저장된 노드의 ID는 바꿀 수 없어요.',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ),
            const SizedBox(height: 18),
            LabeledField(
              label: '순서 (배경 이미지 인계 기준 — 작은 값이 앞선 노드)',
              child: SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: '${node.order}',
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                  decoration: adminInputDecoration(),
                  onChanged: (value) {
                    node.order = int.tryParse(value) ?? node.order;
                    onChanged();
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            LabeledField(
              label: '배경 이미지',
              child: ImagePickerField(
                currentId: node.backgroundImageId,
                images: images,
                onChanged: (id) {
                  node.backgroundImageId = id;
                  onChanged();
                },
              ),
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
            const SizedBox(height: 24),
            NodeBodyEditor(
              bodyText: node.bodyText,
              onChanged: (value) {
                node.bodyText = value;
                onChanged();
              },
            ),
            const SizedBox(height: 24),
            if (packType == StoryPackType.interactive)
              NodeChoiceEditor(choices: node.choices, onChanged: onChanged)
            else
              LabeledField(
                label: '다음 노드 ID',
                child: TextFormField(
                  initialValue: node.nextNodeId ?? '',
                  style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '마지막 노드면 비워두세요.'),
                  onChanged: (value) {
                    node.nextNodeId = value.isEmpty ? null : value;
                    onChanged();
                  },
                ),
              ),
            const SizedBox(height: 12),
            _SaveBar(
              onSaveDraft: onSaveDraft,
              onRequestApproval: onRequestApproval,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBanners() {
    final banners = <Widget>[];

    if (dirty) {
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

    return banners;
  }

  /// 배경 이미지를 안 골랐을 때 보여줄 안내 문구 — 실제로 무엇이 이어지는지
  /// (이미지 이름, 없으면 id 그대로) 보여줘서 "다시 안 골라도 된다"는 걸
  /// 작가가 알 수 있게 한다.
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
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
      ),
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
