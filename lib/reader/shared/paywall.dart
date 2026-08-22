import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_scope.dart';
import '../../core/state/game_state.dart';
import '../../features/catalog/models/story_pack.dart';
import '../../features/wallet/data/purchase_pack_service.dart';
import '../../features/wallet/pages/charge_page.dart';

/// story_page.dart(구 리더)의 미리보기 한도/구매 다이얼로그 흐름을 그대로
/// 옮겨온 것 — 인터랙티브/선형 리더 둘 다 같은 흐름을 쓴다. 유료 팩에서
/// [StoryPack.previewNodeLimit]을 넘어가려 할 때 호출한다.
///
/// 구매는 purchasePack Cloud Function을 통해서만 이뤄진다 — 코인 잔액은
/// 클라이언트가 직접 깎지 않는다(confirmCoinCharge와 같은 원칙). 성공하면
/// 서버가 이미 users/{uid}/save/current.ownedPackIds에 packId를 반영해
/// 둔 뒤이므로, 여기서는 그 결과를 로컬 GameState에 그대로 반영만 한다
/// (markPackOwned).
///
/// 반환값이 true면 구매(또는 이미 소유)로 이어서 진행해도 된다는 뜻이고,
/// false면 사용자가 취소했거나 코인이 부족해 결제까지 못 갔다는 뜻이다.
Future<bool> requestPackPurchase(BuildContext context, GameState gameState, StoryPack pack) async {
  final uid = AuthScope.of(context).userId;
  if (uid == null) return false;

  // 확인 다이얼로그 자신이 구매 요청까지 끝까지 들고 있는다 — "구매하기"를
  // 누른 뒤 purchasePack 호출이 끝날 때까지(네트워크 왕복) 다이얼로그가
  // 로딩 상태(버튼 비활성 + 스피너)로 남아 있고, 성공/실패가 정해진 뒤에만
  // 그 결과를 들고 닫힌다 — 그래서 "구매하기"를 누른 직후 화면이 아무 반응
  // 없어 보이는 구간이 없다.
  final outcome = await showDialog<_PurchaseDialogOutcome>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (dialogContext) => _PurchaseConfirmDialog(pack: pack),
  );

  switch (outcome) {
    case null:
    case _PurchaseDialogCancelled():
      return false;

    case _PurchaseDialogSuccess(:final result):
      gameState.markPackOwned(pack.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.alreadyOwned ? '이미 보유한 팩이에요.' : '${pack.title}을(를) 구매했습니다.',
            ),
          ),
        );
      }
      return true;

    case _PurchaseDialogError(:final error):
      if (!context.mounted) return false;
      if (error is FirebaseFunctionsException && error.code == 'failed-precondition') {
        await _showInsufficientCoinDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('구매에 실패했어요: $error')),
        );
      }
      return false;
  }
}

sealed class _PurchaseDialogOutcome {
  const _PurchaseDialogOutcome();
}

class _PurchaseDialogCancelled extends _PurchaseDialogOutcome {
  const _PurchaseDialogCancelled();
}

class _PurchaseDialogSuccess extends _PurchaseDialogOutcome {
  final PurchasePackResult result;
  const _PurchaseDialogSuccess(this.result);
}

class _PurchaseDialogError extends _PurchaseDialogOutcome {
  final Object error;
  const _PurchaseDialogError(this.error);
}

class _PurchaseConfirmDialog extends StatefulWidget {
  final StoryPack pack;

  const _PurchaseConfirmDialog({required this.pack});

  @override
  State<_PurchaseConfirmDialog> createState() => _PurchaseConfirmDialogState();
}

class _PurchaseConfirmDialogState extends State<_PurchaseConfirmDialog> {
  bool _isPurchasing = false;

  Future<void> _handlePurchase() async {
    setState(() => _isPurchasing = true);
    try {
      final result = await PurchasePackService().purchasePack(packId: widget.pack.id);
      if (!mounted) return;
      Navigator.pop(context, _PurchaseDialogSuccess(result));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context, _PurchaseDialogError(e));
    }
    // 여기서 _isPurchasing을 다시 false로 되돌릴 필요가 없다 — 두 분기
    // 전부 다이얼로그 자체를 pop하므로, 실패해도 스피너가 "멈춘 채 남는"
    // 게 아니라 다이얼로그가 사라지고 곧장 호출부의 에러 처리(충전 화면
    // 유도/일반 에러 스낵바)로 이어진다.
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF151515),
      title: const Text('여기부터는 구매 후 이어볼 수 있어요', style: TextStyle(color: Colors.white)),
      content: Text(
        '${widget.pack.title} · ${widget.pack.effectivePrice}코인',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: _isPurchasing
              ? null
              : () => Navigator.pop(context, const _PurchaseDialogCancelled()),
          child: const Text('취소', style: TextStyle(color: Colors.white70)),
        ),
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

Future<void> _showInsufficientCoinDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF151515),
      title: const Text('코인 부족', style: TextStyle(color: Colors.white)),
      content: const Text('코인이 부족합니다. 충전하시겠어요?', style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('취소', style: TextStyle(color: Colors.white70)),
        ),
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
