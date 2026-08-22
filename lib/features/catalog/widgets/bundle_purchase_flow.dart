import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/state/game_state_scope.dart';
import '../../wallet/data/purchase_bundle_service.dart';
import '../../wallet/data/wallet_repository.dart';
import '../../wallet/pages/charge_page.dart';
import '../models/genre_style.dart';
import '../models/pack_bundle.dart';
import '../models/story_pack.dart';
import '../../../core/auth/auth_scope.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);
const Color _amber = Color(0xFFFFB648);
const Color _muted = Color(0xFF83817A);
const Color _owned = Color(0xFF3FA66B);
const Color _panelBg = Color(0xFF0E0E0D);
const Color _footerBg = Color(0xFF0B0B0A);
const Color _hairline = Color(0xFF1E1E1C);
const Color _panelBorder = Color(0xFF262624);

/// 번들 상세/구매 패널을 연다 — BundleCard를 탭하면 여기로 온다.
///
/// paywall.dart의 requestPackPurchase와 같은 구조(확인 화면이 로딩 상태까지
/// 들고 있다가 성공/실패가 정해진 뒤에만 닫힌다)를 그대로 따른다. 구매
/// 성공 시 새로 소유하게 된 팩 각각에 대해 GameState.markPackOwned를
/// 호출한다 — 서버(purchaseBundle)가 이미 ownedPackIds에 반영해 둔 뒤이므로
/// 여기서는 그 결과를 로컬 GameState에 반영만 한다.
///
/// 표현은 AlertDialog가 아니라 640px 패널이다. 예전엔 기본 AlertDialog에
/// 팩 제목만 '· 불릿' 텍스트로 나열했는데, 데스크톱 폭에서 폰 알림창처럼
/// 보이고 무엇을 사는지도 알 수 없었다. 지금은 팩마다 표지/형식/분량/설명을
/// 보여주고, 결제 금액 계산 근거(정가 → 보유분 제외 → 결제액)와 코인 잔액
/// 변화를 하단에 고정해 둔다.
Future<void> showBundlePurchaseDialog(
  BuildContext context, {
  required PackBundle bundle,
  required List<StoryPack> allPacks,
}) async {
  final gameState = GameStateScope.of(context);
  final uid = AuthScope.of(context).userId;
  if (uid == null) return;

  // 번들의 packIds 순서를 그대로 따른다 — allPacks 순서(제목/최신순)로
  // 뒤섞이면 관리자가 의도한 나열 순서가 사라진다.
  final included = <StoryPack>[];
  for (final packId in bundle.packIds) {
    for (final pack in allPacks) {
      if (pack.id == packId) {
        included.add(pack);
        break;
      }
    }
  }

  final outcome = await showDialog<_BundlePurchaseOutcome>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (dialogContext) => _BundlePurchaseDialog(
      bundle: bundle,
      included: included,
      uid: uid,
    ),
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
      // 잔액은 화면에서 미리 보여주지만, 실제 청구 가능 여부의 유일한 원천은
      // 서버다 — 클라이언트 계산이 통과해도 failed-precondition이 올 수 있다.
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

  /// 호출부가 이미 확인한 uid를 그대로 받는다 — showDialog의 빌더 컨텍스트가
  /// AuthScope 아래인지는 라우터 구성에 달려 있어서, 여기서 다시 찾지 않는다.
  final String uid;

  const _BundlePurchaseDialog({
    required this.bundle,
    required this.included,
    required this.uid,
  });

  @override
  State<_BundlePurchaseDialog> createState() => _BundlePurchaseDialogState();
}

class _BundlePurchaseDialogState extends State<_BundlePurchaseDialog> {
  bool _isPurchasing = false;

  // build()마다 새로 만들면 StreamBuilder가 매번 재구독해서 잔액이 깜빡인다.
  final WalletRepository _walletRepository = WalletRepository();
  late final Stream<int> _balanceStream = _walletRepository.watchBalance(widget.uid);

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

  void _openChargePage() {
    Navigator.pop(context, const _BundlePurchaseCancelled());
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChargePage()));
  }

  @override
  Widget build(BuildContext context) {
    final ownedPackIds = GameStateScope.of(context).ownedPackIds;
    final bundle = widget.bundle;
    final canPurchase = bundle.canPurchaseGiven(ownedPackIds);
    final amountToCharge = bundle.amountToChargeFor(ownedPackIds);
    final ownedCount = bundle.ownedCountAmong(ownedPackIds);
    final totalCount = bundle.packIds.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        // 팩이 많은 번들도 화면을 넘지 않게 — 넘치면 본문만 스크롤된다.
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _panelBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                onClose: _isPurchasing
                    ? null
                    : () => Navigator.pop(context, const _BundlePurchaseCancelled()),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.name.isEmpty ? '번들 상품' : bundle.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _ivory,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ownedCount > 0
                            ? '이야기 $totalCount편 · 이미 $ownedCount편 보유'
                            : '이야기 $totalCount편',
                        style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.6)),
                      ),
                      const SizedBox(height: 22),
                      // 장르 행 사이에 쓰는 것과 같은 웜톤 구분선(ShelfLedgeDivider와
                      // 같은 색) — 이 패널도 같은 서가 톤을 따른다.
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF6B4A2E).withOpacity(0.0),
                              const Color(0xFF6B4A2E).withOpacity(0.55),
                              const Color(0xFF6B4A2E).withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        '포함된 이야기',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: _ivory.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var i = 0; i < widget.included.length; i++) ...[
                        if (i != 0) const SizedBox(height: 14),
                        _IncludedPackRow(
                          pack: widget.included[i],
                          alreadyOwned: ownedPackIds.contains(widget.included[i].id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              StreamBuilder<int>(
                stream: _balanceStream,
                builder: (context, snapshot) {
                  return _Footer(
                    listPrice: bundle.effectivePrice,
                    ownedCount: ownedCount,
                    amountToCharge: amountToCharge,
                    balance: snapshot.data,
                    canPurchase: canPurchase,
                    isPurchasing: _isPurchasing,
                    onCancel: _isPurchasing
                        ? null
                        : () => Navigator.pop(context, const _BundlePurchaseCancelled()),
                    onPurchase: _isPurchasing ? null : _handlePurchase,
                    onCharge: _isPurchasing ? null : _openChargePage,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback? onClose;

  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: Row(
        children: [
          const Text(
            '번들 상품',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: _amber,
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('닫기', style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.55))),
                  const SizedBox(width: 4),
                  Icon(Icons.close_rounded, size: 19, color: _ivory.withOpacity(0.55)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 번들에 포함된 팩 한 편 — 표지 + 제목 + 상태 배지 + 장르·형식·분량 +
/// 설명(StoryPack.description).
///
/// 이미 보유한 팩은 제목을 흐리게 하고 '보유중' 배지를 단다. 새로 받는 팩은
/// 골드 배지 — 결제 금액이 왜 정가보다 낮은지(프로레이팅) 이 목록만 봐도
/// 읽히게 하는 게 목적이다.
class _IncludedPackRow extends StatelessWidget {
  final StoryPack pack;
  final bool alreadyOwned;

  const _IncludedPackRow({required this.pack, required this.alreadyOwned});

  @override
  Widget build(BuildContext context) {
    final genreStyle = genreStyleFor(pack.primaryGenre);
    final coverUrl = pack.coverImageUrl;
    final isInteractive = pack.format == StoryPackFormat.interactive;
    final lengthLabel = pack.publishedNodeCount > 0
        ? (isInteractive ? '노드 ${pack.publishedNodeCount}' : '${pack.publishedNodeCount}화')
        : null;
    final meta = [
      genreStyle.label,
      pack.format.label,
      if (lengthLabel != null) lengthLabel,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          // storyCoverAspectRatio(0.6)와 같은 비율 — 앱 전체가 쓰는 표지 비율.
          height: 62 / 0.6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _CoverPlaceholder(icon: genreStyle.icon),
                      )
                    : _CoverPlaceholder(icon: genreStyle.icon),
              ),
              Positioned(
                left: 5,
                top: 5,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isInteractive ? const Color(0xFF2AA198) : const Color(0xFF3A7BD5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    isInteractive ? Icons.call_split_rounded : Icons.menu_book_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      pack.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: alreadyOwned ? _ivory.withOpacity(0.45) : _ivory,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusTag(alreadyOwned: alreadyOwned),
                ],
              ),
              const SizedBox(height: 4),
              Text(meta, style: const TextStyle(fontSize: 11.5, color: _muted)),
              if (pack.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  pack.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.65,
                    color: _ivory.withOpacity(0.72),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusTag extends StatelessWidget {
  final bool alreadyOwned;

  const _StatusTag({required this.alreadyOwned});

  @override
  Widget build(BuildContext context) {
    final color = alreadyOwned ? _owned : _gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        alreadyOwned ? '보유중' : '새로 받음',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// 표지가 없거나 로드에 실패했을 때 — StoryCoverCard의 _CoverPlaceholder와
/// 같은 조합(브랜드 그라디언트 + 장르 아이콘).
class _CoverPlaceholder extends StatelessWidget {
  final IconData icon;

  const _CoverPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B4A), Color(0xFFFFB648)],
        ),
      ),
      child: Center(
        child: Icon(icon, color: Colors.white.withOpacity(0.92), size: 24),
      ),
    );
  }
}

/// 하단 고정 결제 영역 — 금액 계산 근거와 잔액 변화, 그리고 상태별 버튼.
///
/// 상태 네 가지:
/// - 전부 보유 중: 안내 문구만, 구매 버튼 없음
/// - 잔액 부족: 경고 줄 + '충전하기'
/// - 구매 진행 중: 버튼에 스피너, 취소/닫기 비활성
/// - 평소: 'N코인으로 구매'
class _Footer extends StatelessWidget {
  final int listPrice;
  final int ownedCount;
  final int amountToCharge;

  /// null이면 아직 잔액 스트림의 첫 스냅샷이 안 온 상태 — 잔액 줄과 부족
  /// 판단을 모두 보류한다(잔액을 0으로 가정하고 부족하다고 막으면 안 된다).
  final int? balance;

  final bool canPurchase;
  final bool isPurchasing;
  final VoidCallback? onCancel;
  final VoidCallback? onPurchase;
  final VoidCallback? onCharge;

  const _Footer({
    required this.listPrice,
    required this.ownedCount,
    required this.amountToCharge,
    required this.balance,
    required this.canPurchase,
    required this.isPurchasing,
    required this.onCancel,
    required this.onPurchase,
    required this.onCharge,
  });

  @override
  Widget build(BuildContext context) {
    final balance = this.balance;
    final insufficient = balance != null && balance < amountToCharge;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
      decoration: const BoxDecoration(
        color: _footerBg,
        border: Border(top: BorderSide(color: _hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canPurchase)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 17, color: _owned),
                const SizedBox(width: 8),
                Text(
                  '이미 이 번들의 모든 이야기를 보유하고 있어요.',
                  style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.75)),
                ),
              ],
            )
          else ...[
            _PriceLine(label: '번들 정가', value: '$listPrice코인'),
            if (ownedCount > 0) ...[
              const SizedBox(height: 5),
              _PriceLine(
                label: '보유한 $ownedCount편 제외',
                value: '−${listPrice - amountToCharge}코인',
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 1, color: _hairline),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '결제 금액',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory),
                      ),
                      if (balance != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          insufficient
                              ? '보유 $balance코인 — ${amountToCharge - balance}코인 부족'
                              : '보유 $balance → 구매 후 ${balance - amountToCharge}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: insufficient ? const Color(0xFFF09595) : _muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '$amountToCharge코인',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _gold),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 104,
                height: 48,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.14)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    foregroundColor: _ivory.withOpacity(0.75),
                  ),
                  child: Text(canPurchase ? '취소' : '닫기',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              if (canPurchase) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: insufficient
                        ? FilledButton(
                            onPressed: onCharge,
                            style: FilledButton.styleFrom(
                              backgroundColor: _amber,
                              foregroundColor: const Color(0xFF14140F),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('충전하기',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          )
                        : FilledButton(
                            onPressed: onPurchase,
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: const Color(0xFF14140F),
                              disabledBackgroundColor: _gold.withOpacity(0.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isPurchasing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF14140F),
                                    ),
                                  )
                                : Text('$amountToCharge코인으로 구매',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  final String label;
  final String value;

  const _PriceLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12.5, color: _ivory.withOpacity(0.6));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}

Future<void> _showFailedPreconditionDialog(BuildContext context, String message) {
  final isInsufficientCoin = message.contains('코인이 부족');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: _panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _panelBorder),
      ),
      title: Text(
        isInsufficientCoin ? '코인이 부족해요' : '구매할 수 없어요',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ivory),
      ),
      content: Text(message, style: TextStyle(fontSize: 13.5, height: 1.6, color: _ivory.withOpacity(0.72))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('닫기', style: TextStyle(color: _ivory.withOpacity(0.6))),
        ),
        if (isInsufficientCoin)
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChargePage()));
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: const Color(0xFF14140F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('충전하기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
      ],
    ),
  );
}
