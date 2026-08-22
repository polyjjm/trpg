import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/payment/toss_payments.dart';
import '../../../core/payment/toss_payments_config.dart';
import '../../../core/payment/toss_popup_result.dart';
import '../data/coin_charge_service.dart';
import '../data/point_package_repository.dart';
import '../data/wallet_repository.dart';
import '../models/point_package.dart';
import '../widgets/point_package_card.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 코인 충전 화면. pointPackages 컬렉션(active + platform=='web')을 읽어
/// 상품 카드로 보여주고, 상품을 고르고 "결제하기"를 누르면 Toss Payments
/// 결제창이 새 팝업 창으로 열린다(openTossPaymentPopup) — 이 탭은 그동안
/// 한 번도 이동/새로고침되지 않는다. 결제 승인/코인 지급은 전부 서버
/// (confirmCoinCharge Cloud Function)가 하고, 여기서는 절대 잔액을 직접
/// 더하지 않는다 — 화면의 잔액은 항상 WalletRepository.watchBalance
/// 스트림(users/{uid}/wallet/current)을 그대로 보여준다.
class ChargePage extends StatefulWidget {
  const ChargePage({super.key});

  @override
  State<ChargePage> createState() => _ChargePageState();
}

class _ChargePageState extends State<ChargePage> {
  final PointPackageRepository _packageRepository = PointPackageRepository();
  final WalletRepository _walletRepository = WalletRepository();

  late final Stream<List<PointPackage>> _packagesStream =
      _packageRepository.watchWebPackages();

  String? _selectedPackageId;
  bool _isProcessing = false;

  void _selectPackage(String packageId) {
    if (_isProcessing) return;
    setState(() => _selectedPackageId = packageId);
  }

  /// [selected]를 결제한다 — 팝업 창에서 Toss 결제가 끝날 때까지 기다린 뒤
  /// (openTossPaymentPopup이 반환하는 시점), 성공이면 그 자리에서 바로
  /// confirmCoinCharge를 호출해 서버 승인/코인 지급까지 마친다. 이 화면
  /// 자체는 그동안 한 번도 떠나지 않는다 — 새로고침도, 라우트 전환도 없다.
  ///
  /// openTossPaymentPopup 호출 앞에 await가 없어야 한다(uid 조회/setState/
  /// FirebaseAuth.instance.currentUser는 전부 동기 코드) — 그래야 버튼 클릭과
  /// 같은 JS 태스크 안에서 window.open이 실행되어 팝업 차단기를 피한다.
  Future<void> _submit(PointPackage selected) async {
    final uid = AuthScope.of(context).userId;
    if (uid == null) return;

    setState(() => _isProcessing = true);

    final orderId = 'chg_${uid}_${DateTime.now().millisecondsSinceEpoch}';
    final currentUser = FirebaseAuth.instance.currentUser;

    final result = await openTossPaymentPopup(
      clientKey: TossPaymentsConfig.clientKey,
      amountKRW: selected.currentPriceKRW,
      orderId: orderId,
      orderName: selected.name.isEmpty ? '코인 ${selected.coinAmount}개' : selected.name,
      packageId: selected.id,
      customerName: currentUser?.displayName,
      customerEmail: currentUser?.email,
    );

    if (!mounted) return;

    switch (result) {
      case TossPopupSuccess():
        await _confirmCharge(result, packageId: selected.id);
      case TossPopupFailure(:final message):
        setState(() => _isProcessing = false);
        await _showResultDialog(title: '결제가 완료되지 않았어요', message: message);
      case TossPopupCancelled():
        // 사용자가 그냥 팝업을 닫은 것뿐이다 — 에러가 아니니 조용히 원래
        // 화면 상태로 돌아간다(다이얼로그 없음).
        setState(() => _isProcessing = false);
      case TossPopupBlocked():
        setState(() => _isProcessing = false);
        await _showResultDialog(
          title: '팝업이 차단됐어요',
          message: '브라우저 설정에서 이 사이트의 팝업을 허용한 뒤 다시 시도해주세요.',
        );
    }
  }

  /// Toss가 결제를 확인해 준 뒤 — 실제 코인 지급은 여기서 confirmCoinCharge
  /// Cloud Function을 호출해야 비로소 일어난다. 잔액은 여기서 직접 더하지
  /// 않는다 — WalletRepository.watchBalance 스트림이 서버가 반영한 값을
  /// 그대로 흘려보낸다.
  Future<void> _confirmCharge(TossPopupSuccess success, {required String packageId}) async {
    String message;
    try {
      final chargeResult = await CoinChargeService().confirmCharge(
        paymentKey: success.paymentKey,
        orderId: success.orderId,
        amount: success.amount,
        packageId: packageId,
      );
      message = chargeResult.alreadyProcessed
          ? '이미 처리된 결제예요. 현재 잔액 ${chargeResult.newBalance}코인'
          : '코인 충전이 완료됐어요. 현재 잔액 ${chargeResult.newBalance}코인';
    } catch (e) {
      message = '결제 승인에 실패했어요: $e';
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);
    await _showResultDialog(title: '코인 충전', message: message);
  }

  Future<void> _showResultDialog({required String title, required String message}) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A14),
        title: Text(title, style: const TextStyle(color: _ivory)),
        content: Text(message, style: const TextStyle(color: _ivory)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인', style: TextStyle(color: _gold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthScope.of(context).userId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '코인 충전',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _ivory,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildBalanceCard(uid),
              const SizedBox(height: 26),
              const Text(
                '충전 상품',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: StreamBuilder<List<PointPackage>>(
                  stream: _packagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '상품 목록을 불러오지 못했어요',
                          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _gold),
                      );
                    }

                    final packages = snapshot.data ?? const <PointPackage>[];
                    if (packages.isEmpty) {
                      return Center(
                        child: Text(
                          '아직 등록된 충전 상품이 없어요',
                          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
                        ),
                      );
                    }

                    final selected = packages
                        .where((p) => p.id == _selectedPackageId)
                        .firstOrNull;

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        for (final package in packages) ...[
                          PointPackageCard(
                            package: package,
                            selected: package.id == _selectedPackageId,
                            onTap: () => _selectPackage(package.id),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 8),
                        _buildPaymentMethodRow(),
                        const SizedBox(height: 20),
                        _buildSubmitButton(selected),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(String? uid) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on_rounded, color: _gold, size: 26),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '보유 코인',
                style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.70)),
              ),
              const SizedBox(height: 2),
              if (uid == null)
                const Text(
                  '0코인',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _gold),
                )
              else
                StreamBuilder<int>(
                  stream: _walletRepository.watchBalance(uid),
                  builder: (context, snapshot) {
                    final balance = snapshot.data ?? 0;
                    return Text(
                      '$balance코인',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _gold,
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 테스트 모드에서는 카드 결제 하나만 지원한다 — 실제로 고를 수 있는
  /// 선택지가 아니라 지금 어떤 수단으로 결제되는지 보여주는 정보 행이다.
  Widget _buildPaymentMethodRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.credit_card_rounded, color: _ivory.withOpacity(0.75), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '결제 수단: 신용·체크카드',
              style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.85)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Toss 테스트 모드',
              style: TextStyle(fontSize: 10.5, color: _ivory.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(PointPackage? selected) {
    final canSubmit = selected != null && !_isProcessing;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: canSubmit ? () => _submit(selected) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: Colors.black,
          disabledBackgroundColor: _gold.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              )
            : Text(
                selected == null
                    ? '상품을 선택해주세요'
                    : '₩${formatWon(selected.currentPriceKRW)} 결제하기',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
