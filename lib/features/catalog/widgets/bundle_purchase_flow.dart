import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/state/game_state_scope.dart';
import '../../wallet/data/purchase_bundle_service.dart';
import '../../wallet/pages/charge_page.dart';
import '../models/pack_bundle.dart';
import '../models/story_pack.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 번들 상세/구매 다이얼로그를 연다 — BundleCard를 탭하면 여기로 온다.
/// paywall.dart의 requestPackPurchase와 같은 구조(확인 다이얼로그가 로딩
/// 상태까지 들고 있다가 성공/실패가 정해진 뒤에만 닫힌다)를 번들에 맞게
/// 옮긴 것이다. 구매 성공 시 새로 소유하게 된 팩 각각에 대해
/// GameState.markPackOwned를 호출한다 — 서버(purchaseBundle)가 이미
/// ownedPackIds에 반영해 둔 뒤이므로, 여기서는 그 결과를 로컬 GameState에
/// 그대로 반영만 한다.
Future<void> showBundlePurchaseDialog(
  BuildContext context, {
  required PackBundle bundle,
  required List<StoryPack> allPacks,
}) async {
  final gameState = GameStateScope.of(context);
  final uid = AuthScope.of(context).userId;
  if (uid == null) return;

  final included = allPacks.where((p) => bundle.packIds.contains(p.id)).toList();

  final outcome = await showDialog<_BundlePurchaseOutcome>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (dialogContext) => _BundlePurchaseDialog(bundle: bundle, included: included),
  );

  switch (outcome) {
    case null:
    case _BundlePurchaseCancelled():
      return;

    case _BundlePurchaseSuccess(:final result):
      for (final packId in result.newlyOwnedPackIds) {
        gameState.markPackOwned(packId);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.newlyOwnedPackIds.isEmpty
                  ? '이미 보유한 팩들이었어요.'
                  : '${bundle.name}을(를) 구매했어요.',
            ),
          ),
        );
      }
      return;

    case _BundlePurchaseError(:final error):
      if (!context.mounted) return;
      if (error is FirebaseFunctionsException && error.code == 'failed-precondition') {
        await _showFailedPreconditionDialog(context, error.message ?? '구매할 수 없어요.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('구매에 실패했어요: $error')),
        );
      }
      return;
  }
}

sealed class _BundlePurchaseOutcome {
  const _BundlePurchaseOutcome();
}

class _BundlePurchaseCancelled extends _BundlePurchaseOutcome {
  const _BundlePurchaseCancelled();
}

class _BundlePurchaseSuccess extends _BundlePurchaseOutcome {
  final PurchaseBundleResult result;
  const _BundlePurchaseSuccess(this.result);
}

class _BundlePurchaseError extends _BundlePurchaseOutcome {
  final Object error;
  const _BundlePurchaseError(this.error);
}

class _BundlePurchaseDialog extends StatefulWidget {
  final PackBundle bundle;
  final List<StoryPack> included;

  const _BundlePurchaseDialog({required this.bundle, required this.included});

  @override
  State<_BundlePurchaseDialog> createState() => _BundlePurchaseDialogState();
}

class _BundlePurchaseDialogState extends State<_BundlePurchaseDialog> {
  bool _isPurchasing = false;

  Future<void> _handlePurchase() async {
    setState(() => _isPurchasing = true);
    try {
      final result = await PurchaseBundleService().purchaseBundle(bundleId: widget.bundle.id);
      if (!mounted) return;
      Navigator.pop(context, _BundlePurchaseSuccess(result));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context, _BundlePurchaseError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = GameStateScope.of(context);
    final ownedPackIds = gameState.ownedPackIds;
    final bundle = widget.bundle;
    final canPurchase = bundle.canPurchaseGiven(ownedPackIds);
    final amountToCharge = bundle.amountToChargeFor(ownedPackIds);
    final ownedCount = bundle.ownedCountAmong(ownedPackIds);

    return AlertDialog(
      backgroundColor: const Color(0xFF151515),
      title: Text(bundle.name, style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final pack in widget.included)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· ${pack.title}${ownedPackIds.contains(pack.id) ? ' (보유중)' : ''}',
                  style: TextStyle(
                    color: ownedPackIds.contains(pack.id) ? Colors.white38 : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (!canPurchase)
              const Text(
                '이미 이 번들의 모든 팩을 보유하고 있어요.',
                style: TextStyle(color: Colors.white70),
              )
            else
              Text(
                ownedCount > 0
                    ? '이미 $ownedCount개 보유 — $amountToCharge코인만 더 내면돼요'
                    : '$amountToCharge코인',
                style: const TextStyle(color: _ivory, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPurchasing
              ? null
              : () => Navigator.pop(context, const _BundlePurchaseCancelled()),
          child: const Text('취소', style: TextStyle(color: Colors.white70)),
        ),
        if (canPurchase)
          TextButton(
            onPressed: _isPurchasing ? null : _handlePurchase,
            child: _isPurchasing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('구매하기', style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}

Future<void> _showFailedPreconditionDialog(BuildContext context, String message) {
  final isInsufficientCoin = message.contains('코인이 부족');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF151515),
      title: Text(isInsufficientCoin ? '코인 부족' : '구매할 수 없어요', style: const TextStyle(color: Colors.white)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('취소', style: TextStyle(color: Colors.white70)),
        ),
        if (isInsufficientCoin)
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChargePage()));
              }
            },
            child: const Text('충전하기', style: TextStyle(color: Colors.white)),
          ),
      ],
    ),
  );
}
