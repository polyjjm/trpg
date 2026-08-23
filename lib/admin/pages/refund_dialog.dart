import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../data/refund_charge_service.dart';
import '../models/wallet_transaction.dart';
import '../widgets/admin_theme.dart';
import '../widgets/labeled_field.dart';

/// 환불 확인 다이얼로그를 열고, 성공/실패에 따라 스낵바를 보여준다.
/// [onRefunded]는 성공했을 때 호출부(결제내역 탭)가 목록을 다시 읽도록
/// 알려주는 콜백이다.
Future<void> showRefundDialog(
  BuildContext context, {
  required AdminChargeTransaction charge,
  required VoidCallback onRefunded,
}) async {
  final outcome = await showDialog<_RefundOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RefundDialog(charge: charge),
  );

  if (!context.mounted) return;
  switch (outcome) {
    case null:
    case _RefundCancelled():
      return;
    case _RefundSuccess(:final result):
      onRefunded();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '환불 완료 — 코인 ${result.refundedCoins}개, ${result.refundedKRW}원 (상태: ${result.refundStatus})',
          ),
        ),
      );
    case _RefundError(:final error):
      final message = error is FirebaseFunctionsException
          ? (error.message ?? '환불에 실패했어요.')
          : '환불에 실패했어요: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AdminColors.danger),
      );
  }
}

sealed class _RefundOutcome {
  const _RefundOutcome();
}

class _RefundCancelled extends _RefundOutcome {
  const _RefundCancelled();
}

class _RefundSuccess extends _RefundOutcome {
  final RefundChargeResult result;
  const _RefundSuccess(this.result);
}

class _RefundError extends _RefundOutcome {
  final Object error;
  const _RefundError(this.error);
}

class _RefundDialog extends StatefulWidget {
  final AdminChargeTransaction charge;

  const _RefundDialog({required this.charge});

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  final TextEditingController _reasonController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _reasonController.text.trim().isNotEmpty && !_isProcessing;

  Future<void> _submit() async {
    setState(() => _isProcessing = true);
    try {
      final result = await RefundChargeService().refundCharge(
        uid: widget.charge.uid,
        chargeTxId: widget.charge.id,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, _RefundSuccess(result));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context, _RefundError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final charge = widget.charge;

    return AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text('환불 처리', style: TextStyle(color: AdminColors.ivory)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${charge.displayName.isEmpty ? '(이름 없음)' : charge.displayName} · ${charge.uid}',
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '지급 코인 ${charge.coinAmount} · 결제금액 ${charge.amountKRW}원'
              '${charge.refundedCoins > 0 ? ' · 이미 환불 ${charge.refundedCoins}코인' : ''}',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              '최대 ${charge.refundableCoinsUpperBound}코인까지 환불 가능해요(단, 이미 사용해 지갑에 '
              '남아있지 않은 코인은 제외돼요 — 실제 환불 금액은 서버가 다시 계산해요).',
              style: TextStyle(
                fontSize: 11.5,
                color: AdminColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '환불 사유 (필수)',
              child: TextField(
                controller: _reasonController,
                autofocus: true,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                decoration: adminInputDecoration(
                  hintText: '예: 고객 요청 — 미사용 코인 환불',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing
              ? null
              : () => Navigator.pop(context, const _RefundCancelled()),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: _isProcessing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AdminColors.gold,
                  ),
                )
              : const Text('환불하기', style: TextStyle(color: AdminColors.gold)),
        ),
      ],
    );
  }
}
