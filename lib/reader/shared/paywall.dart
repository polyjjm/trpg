import 'package:flutter/material.dart';

import '../../core/state/game_state.dart';
import '../../features/catalog/models/story_pack.dart';
import '../../features/wallet/pages/charge_page.dart';

/// story_page.dart(구 리더)의 미리보기 한도/구매 다이얼로그 흐름을 그대로
/// 옮겨온 것 — 인터랙티브/선형 리더 둘 다 같은 흐름을 쓴다. 유료 팩에서
/// [StoryPack.previewNodeLimit]을 넘어가려 할 때 호출한다.
///
/// 반환값이 true면 구매(또는 이미 소유)로 이어서 진행해도 된다는 뜻이고,
/// false면 사용자가 취소했거나 캐시가 부족해 결제까지 못 갔다는 뜻이다.
Future<bool> requestPackPurchase(BuildContext context, GameState gameState, StoryPack pack) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF151515),
      title: const Text('여기부터는 구매 후 이어볼 수 있어요', style: TextStyle(color: Colors.white)),
      content: Text('${pack.title} · ₩${pack.price}', style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('취소', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('구매하기', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  if (gameState.spendCash(pack.price)) {
    gameState.markPackOwned(pack.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pack.title}을(를) 구매했습니다.')));
    }
    return true;
  }

  if (!context.mounted) return false;
  await _showInsufficientCashDialog(context);
  return false;
}

Future<void> _showInsufficientCashDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF151515),
      title: const Text('캐시 부족', style: TextStyle(color: Colors.white)),
      content: const Text('캐시가 부족합니다. 충전하시겠어요?', style: TextStyle(color: Colors.white70)),
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
