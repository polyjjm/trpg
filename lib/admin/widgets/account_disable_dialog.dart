import 'package:flutter/material.dart';

import '../../core/user/user_profile.dart';
import 'admin_theme.dart';
import 'checkbox_row.dart';
import 'labeled_field.dart';

/// [DisableAccountDialog]가 돌려주는 입력값 — 실제 정지/해제 처리(Cloud
/// Function 호출)는 호출부가 한다, 이 다이얼로그는 입력만 모은다
/// (author_management_section.dart의 `_RevokeDialog`/`promptRejectionReason`
/// 등 이 admin 도구의 다른 다이얼로그들과 같은 관례).
class DisableAccountResult {
  final String? reason;
  final bool suspendPacks;

  const DisableAccountResult({this.reason, this.suspendPacks = false});
}

/// 계정 정지/정지 해제 공용 다이얼로그 — 원래 author_management_section.dart
/// 안에 있던 private `_DisableDialog`였다. "회원 관리" 화면의 회원 탭이
/// 독자/관리자 계정에도 같은 정지·해제 조치를 걸 수 있게 되면서(작가 전용이
/// 아니게 되면서) 공용 위젯으로 옮기고, [showSuspendPacksCheckbox]를
/// 매개변수로 열었다 — 작가 탭(author_management_section.dart)은 대상이
/// 항상 작가라 늘 true를 넘겨서 예전과 완전히 같은 동작을 유지하고, 회원
/// 탭은 대상이 작가일 때만 true를 넘긴다(독자/관리자는 애초에 팩이 없으니
/// 그 체크박스 자체가 무의미하다).
class DisableAccountDialog extends StatefulWidget {
  final UserProfile profile;
  final bool disabling;
  final bool showSuspendPacksCheckbox;

  const DisableAccountDialog({
    super.key,
    required this.profile,
    required this.disabling,
    required this.showSuspendPacksCheckbox,
  });

  @override
  State<DisableAccountDialog> createState() => _DisableAccountDialogState();
}

class _DisableAccountDialogState extends State<DisableAccountDialog> {
  final TextEditingController _reasonController = TextEditingController();
  late bool _suspendPacks = widget.showSuspendPacksCheckbox;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile.displayName.isEmpty
        ? '(이름 없음)'
        : widget.profile.displayName;
    final disabling = widget.disabling;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(
        disabling ? '계정 정지' : '정지 해제',
        style: TextStyle(color: AdminColors.ivory),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              disabling
                  ? '$name 계정의 로그인을 막아요. 지갑/거래/작품 등 데이터는 그대로 '
                        '남고, 되돌릴 수 있어요(진짜 계정 삭제가 아니에요).'
                  : '$name 계정의 로그인 차단을 풀어요. 다시 로그인할 수 있게 돼요.',
              style: TextStyle(
                fontSize: 12.5,
                color: AdminColors.muted,
                height: 1.4,
              ),
            ),
            if (!disabling && widget.showSuspendPacksCheckbox) ...[
              const SizedBox(height: 8),
              Text(
                '내려간 작품은 자동으로 복원되지 않아요 — 필요하면 전체 작품 '
                '목록에서 따로 복원해 주세요.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AdminColors.dirtyBannerText,
                  height: 1.4,
                ),
              ),
            ],
            if (disabling) ...[
              const SizedBox(height: 16),
              LabeledField(
                label: '사유 (선택)',
                child: TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                  decoration: adminInputDecoration(hintText: '예: 이용 정책 위반'),
                ),
              ),
              if (widget.showSuspendPacksCheckbox) ...[
                const SizedBox(height: 14),
                CheckboxRow(
                  value: _suspendPacks,
                  onChanged: (value) => setState(() => _suspendPacks = value),
                  label: '이 작가의 작품도 함께 비공개 처리',
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            DisableAccountResult(
              reason: _reasonController.text.trim().isEmpty
                  ? null
                  : _reasonController.text.trim(),
              suspendPacks: _suspendPacks,
            ),
          ),
          child: Text(
            disabling ? '정지하기' : '정지 해제',
            style: TextStyle(
              color: disabling ? AdminColors.rejectText : AdminColors.gold,
            ),
          ),
        ),
      ],
    );
  }
}
