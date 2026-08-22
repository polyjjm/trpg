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

/// 데스크톱 2단 레이아웃으로 갈리는 폭 — 카탈로그/리더와 같은 기준값이지만,
/// wallet 기능이 catalog widgets를 import하지 않도록 여기 따로 둔다.
const double _desktopBreakpoint = 1100;

/// 데스크톱에서 콘텐츠가 늘어나는 최대 폭 — 1440px를 꽉 채우면 상품 카드 한
/// 줄이 과하게 길어져서 이름과 가격이 화면 양 끝으로 떨어진다.
const double _desktopContentMaxWidth = 1100;

/// 데스크톱 오른쪽 결제 패널 폭.
const double _summaryColumnWidth = 360;

/// 코인 충전 화면. pointPackages 컬렉션(active + platform=='web')을 읽어
/// 상품 카드로 보여주고, 상품을 고르고 "결제하기"를 누르면 Toss Payments
/// 결제창이 새 팝업 창으로 열린다 — 이 화면은 그동안 한 번도 이동/새로고침되지
/// 않는다. 결제 승인/코인 지급은 전부 서버(confirmCoinCharge)가 하고, 여기서는
/// 절대 잔액을 직접 더하지 않는다 — 화면의 잔액은 항상
/// WalletRepository.watchBalance 스트림을 그대로 보여준다.
///
/// 레이아웃은 폭으로 갈린다:
/// - 좁은 폭: 잔액 → 상품 목록 → 결제 수단 → 결제 버튼 세로 스택(기존 그대로).
/// - 데스크톱([_desktopBreakpoint] 이상): 왼쪽에 잔액 + 상품 목록, 오른쪽
///   360px에 결제 내역 패널(선택 상품/보너스/충전 후 잔액/결제 금액/결제 수단/
///   결제 버튼). 세로 스택으로 두면 상품이 다섯 개만 돼도 결제 버튼이 스크롤
///   아래로 밀려 내려간다.
class ChargePage extends StatefulWidget {
  const ChargePage({super.key});

  @override
  State<ChargePage> createState() => _ChargePageState();
}

class _ChargePageState extends State<ChargePage> {
  final PointPackageRepository _packageRepository = PointPackageRepository();
  final WalletRepository _walletRepository = WalletRepository();

  late final Stream<List<PointPackage>> _packagesStream = _packageRepository.watchWebPackages();

  String? _selectedPackageId;
  bool _isProcessing = false;

  void _selectPackage(String packageId) {
    if (_isProcessing) return;
    setState(() => _selectedPackageId = packageId);
  }

  /// [selected]를 결제한다 — 팝업 창에서 Toss 결제가 끝날 때까지 기다린 뒤
  /// 성공이면 그 자리에서 바로 confirmCoinCharge를 호출해 서버 승인/코인
  /// 지급까지 마친다.
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

  /// 실제 코인 지급은 confirmCoinCharge Cloud Function을 호출해야 비로소
  /// 일어난다. 잔액은 여기서 직접 더하지 않는다 — watchBalance 스트림이
  /// 서버가 반영한 값을 그대로 흘려보낸다.
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
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDesktop),
            Expanded(
              child: StreamBuilder<List<PointPackage>>(
                stream: _packagesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _centered('상품 목록을 불러오지 못했어요');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _gold));
                  }

                  final packages = snapshot.data ?? const <PointPackage>[];
                  if (packages.isEmpty) {
                    return _centered('아직 등록된 충전 상품이 없어요');
                  }

                  final selected =
                      packages.where((p) => p.id == _selectedPackageId).firstOrNull;

                  return isDesktop
                      ? _buildDesktopBody(uid, packages, selected)
                      : _buildMobileBody(uid, packages, selected);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    final row = Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        const SizedBox(width: 4),
        const Text(
          '코인 충전',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ivory),
        ),
      ],
    );

    if (!isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: row,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1C))),
      ),
      child: row,
    );
  }

  Widget _centered(String text) {
    return Center(
      child: Text(text, style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55))),
    );
  }

  /// 좁은 폭 — 잔액 → 상품 목록 → 결제 수단 → 결제 버튼(기존 순서 그대로).
  Widget _buildMobileBody(
    String? uid,
    List<PointPackage> packages,
    PointPackage? selected,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _BalanceCard(balanceStream: uid == null ? null : _walletRepository.watchBalance(uid)),
          const SizedBox(height: 26),
          const _SectionTitle('충전 상품'),
          const SizedBox(height: 14),
          for (final package in packages) ...[
            PointPackageCard(
              package: package,
              selected: package.id == _selectedPackageId,
              onTap: () => _selectPackage(package.id),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          const _PaymentMethodRow(),
          const SizedBox(height: 20),
          _buildSubmitButton(selected),
        ],
      ),
    );
  }

  /// 데스크톱 — 왼쪽 잔액 + 상품 목록, 오른쪽 결제 내역 패널.
  Widget _buildDesktopBody(
    String? uid,
    List<PointPackage> packages,
    PointPackage? selected,
  ) {
    final balanceStream = uid == null ? null : _walletRepository.watchBalance(uid);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _desktopContentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  children: [
                    _BalanceCard(balanceStream: balanceStream),
                    const SizedBox(height: 26),
                    const _SectionTitle('충전 상품'),
                    const SizedBox(height: 14),
                    for (final package in packages) ...[
                      PointPackageCard(
                        package: package,
                        selected: package.id == _selectedPackageId,
                        onTap: () => _selectPackage(package.id),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 32),
              SizedBox(
                width: _summaryColumnWidth,
                child: _PaymentSummaryPanel(
                  selected: selected,
                  balanceStream: balanceStream,
                  submitButton: _buildSubmitButton(selected),
                ),
              ),
            ],
          ),
        ),
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

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: _ivory,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  /// null이면 게스트 — 지갑 문서가 없으니 0코인으로 보여준다.
  final Stream<int>? balanceStream;

  const _BalanceCard({required this.balanceStream});

  @override
  Widget build(BuildContext context) {
    final stream = balanceStream;

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
              Text('보유 코인', style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.70))),
              const SizedBox(height: 2),
              if (stream == null)
                const _BalanceValue(0)
              else
                StreamBuilder<int>(
                  stream: stream,
                  builder: (context, snapshot) => _BalanceValue(snapshot.data ?? 0),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceValue extends StatelessWidget {
  final int balance;

  const _BalanceValue(this.balance);

  @override
  Widget build(BuildContext context) {
    return Text(
      '$balance코인',
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _gold),
    );
  }
}

/// 테스트 모드에서는 카드 결제 하나만 지원한다 — 실제로 고를 수 있는
/// 선택지가 아니라 지금 어떤 수단으로 결제되는지 보여주는 정보 행이다.
class _PaymentMethodRow extends StatelessWidget {
  const _PaymentMethodRow();

  @override
  Widget build(BuildContext context) {
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
}

/// 데스크톱 오른쪽 결제 내역 패널.
///
/// ⚠️ "선택한 상품" 줄은 반드시 [PointPackage.coinAmount]를 쓴다 — 상품
/// 이름(예: "코인 1,100")에는 보너스가 이미 포함된 경우가 있어서, 이름을
/// 기준으로 잡고 보너스를 또 더하면 충전 후 잔액이 실제보다 많아진다.
/// 충전 후 잔액 = 현재 잔액 + coinAmount + bonusCoins.
class _PaymentSummaryPanel extends StatelessWidget {
  final PointPackage? selected;
  final Stream<int>? balanceStream;
  final Widget submitButton;

  const _PaymentSummaryPanel({
    required this.selected,
    required this.balanceStream,
    required this.submitButton,
  });

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    final stream = balanceStream;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '결제 내역',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ivory),
          ),
          const SizedBox(height: 16),
          if (selected == null)
            Text(
              '충전할 상품을 선택해주세요.',
              style: TextStyle(fontSize: 13, height: 1.6, color: _ivory.withOpacity(0.6)),
            )
          else ...[
            _SummaryLine(
              label: '선택한 상품',
              value: '코인 ${formatWon(selected.coinAmount)}',
            ),
            if (selected.bonusCoins > 0) ...[
              const SizedBox(height: 8),
              _SummaryLine(
                label: '보너스',
                value: '+${formatWon(selected.bonusCoins)}',
                valueColor: _gold,
              ),
            ],
            if (stream != null) ...[
              const SizedBox(height: 8),
              StreamBuilder<int>(
                stream: stream,
                builder: (context, snapshot) {
                  final balance = snapshot.data;
                  return _SummaryLine(
                    label: '충전 후 잔액',
                    value: balance == null
                        ? '-'
                        : '${formatWon(balance + selected.coinAmount + selected.bonusCoins)}코인',
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            Divider(height: 1, thickness: 1, color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Expanded(
                  child: Text(
                    '결제 금액',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ivory),
                  ),
                ),
                Text(
                  '₩${formatWon(selected.currentPriceKRW)}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _gold),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          const _PaymentMethodRow(),
          const SizedBox(height: 16),
          submitButton,
          const SizedBox(height: 12),
          Text(
            '결제창은 새 팝업으로 열립니다. 팝업이 차단되면 브라우저 설정에서 허용해 주세요.',
            style: TextStyle(fontSize: 11.5, height: 1.6, color: _ivory.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryLine({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 12.5, color: _ivory.withOpacity(0.6))),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? _ivory,
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
