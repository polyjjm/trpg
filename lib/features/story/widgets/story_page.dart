import 'package:flutter/material.dart';
import 'typewriter_text.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/constants/asset_paths.dart';
import '../../../core/state/game_state.dart';
import '../../../core/state/game_state_scope.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/footer_nav_bar.dart';
import '../../../widgets/hearts_indicator.dart';
import '../../auth/pages/sign_in_page.dart';
import '../../battle/data/battle_configs.dart';
import '../../battle/models/battle_result.dart';
import '../../battle/pages/battle_page.dart';
import '../../catalog/models/story_pack.dart';
import '../../encounter/data/encounter_configs.dart';
import '../../encounter/models/encounter_result.dart';
import '../../encounter/pages/encounter_page.dart';
import '../../merchant/pages/merchant_page.dart';
import '../../wallet/pages/charge_page.dart';
import '../data/story_nodes.dart';
import '../models/story_choice.dart';

class StoryPage extends StatefulWidget {
  final StoryPack pack;

  const StoryPage({super.key, required this.pack});

  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _typedNodeId;
  bool _showChoices = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final currentNodeId = GameStateScope.of(context).currentNodeId;
    if (_typedNodeId != currentNodeId) {
      _typedNodeId = currentNodeId;
      _showChoices = false;
    }
  }

  Future<void> _handleBattleChoice(StoryBattleTrigger trigger) async {
    final config = battleConfigs[trigger.battleId];
    if (config == null) return;

    final gameState = GameStateScope.of(context);

    final result = await Navigator.push<BattleResult>(
      context,
      MaterialPageRoute(
        builder: (_) => BattlePage(config: config),
      ),
    );

    if (!mounted || result == null) return;

    gameState.applyBattleResult(result);

    final nextNodeId = switch (result.outcome) {
      BattleOutcome.win => trigger.winNodeId,
      BattleOutcome.lose => trigger.loseNodeId,
      BattleOutcome.escape => trigger.escapeNodeId,
    };

    _goToNode(nextNodeId);

    if (!mounted) return;

    final rewardText = result.reward.itemIds.isEmpty
        ? '획득한 아이템 없음'
        : '획득 아이템: ${result.reward.itemIds.join(', ')}';

    final message = switch (result.outcome) {
      BattleOutcome.win => '전투 승리. 남은 HP: ${result.remainHp} / $rewardText',
      BattleOutcome.escape => '전투에서 도망쳤다.',
      BattleOutcome.lose => '전투에서 패배했다.',
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleEncounterChoice(StoryEncounterTrigger trigger) async {
    final config = encounterConfigs[trigger.encounterId];
    if (config == null) return;

    final gameState = GameStateScope.of(context);

    final result = await Navigator.push<EncounterResult>(
      context,
      MaterialPageRoute(
        builder: (_) => EncounterPage(config: config),
      ),
    );

    if (!mounted || result == null) return;

    if (result.outcome == EncounterOutcome.dead) {
      gameState.resetProgress(storyStartNodeId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('쓰러지고 말았다. 처음부터 다시 시작한다.')),
      );
      return;
    }

    final nextNodeId = result.outcome == EncounterOutcome.win
        ? trigger.winNodeId
        : trigger.escapeNodeId;

    _goToNode(nextNodeId);

    if (!mounted) return;

    final message = result.outcome == EncounterOutcome.win
        ? '${config.enemyName}을(를) 물리쳤다.'
        : '위기에서 벗어났다.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleMerchantChoice(StoryMerchantTrigger trigger) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MerchantPage(),
      ),
    );

    if (!mounted) return;

    _goToNode(trigger.nextNodeId);
  }

  void _handleNodeChoice(String nextNodeId) {
    _goToNode(nextNodeId);
  }

  /// 스토리 노드 이동을 한 곳에서 처리한다 — 일반 선택지든 전투/조우/상인 결과든
  /// 다음 노드로 넘어가기 전에 항상 이 메서드를 거쳐, 유료 팩의 무료 미리보기
  /// 한도를 일관되게 검사한다.
  void _goToNode(String nextNodeId) {
    final gameState = GameStateScope.of(context);
    final pack = widget.pack;

    final previewLimitReached = pack.price > 0 &&
        !gameState.ownsPack(pack.id) &&
        gameState.visitedNodeCount >= pack.previewNodeLimit;

    if (previewLimitReached) {
      _showPaywallDialog(gameState, nextNodeId);
      return;
    }

    gameState.goToNode(nextNodeId);
  }

  void _showPaywallDialog(GameState gameState, String nextNodeId) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          '여기부터는 구매 후 이어볼 수 있어요',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${widget.pack.title} · ₩${widget.pack.price}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _purchaseAndContinue(gameState, nextNodeId);
            },
            child: const Text('구매하기', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _purchaseAndContinue(GameState gameState, String nextNodeId) {
    if (gameState.spendCash(widget.pack.price)) {
      gameState.markPackOwned(widget.pack.id);
      gameState.goToNode(nextNodeId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.pack.title}을(를) 구매했습니다.')),
      );
      return;
    }

    _showInsufficientCashDialog();
  }

  void _showInsufficientCashDialog() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text('캐시 부족', style: TextStyle(color: Colors.white)),
        content: const Text(
          '캐시가 부족합니다. 충전하시겠어요?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChargePage()),
              );
            },
            child: const Text('충전하기', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleRestart() {
    GameStateScope.of(context).resetProgress(storyStartNodeId);
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _confirmRestartFromDrawer() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          '처음부터 다시 시작',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '진행 상황이 모두 초기화됩니다. 계속하시겠습니까?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _handleRestart();
            },
            child: const Text('다시 시작', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmLibraryFromDrawer() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          '라이브러리로 돌아가기',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '현재 진행 상황은 자동으로 저장됩니다.\n라이브러리로 돌아가시겠습니까?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text('라이브러리로', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSettingsPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('설정 화면은 다음 업데이트에서 제공될 예정입니다.')),
    );
  }

  Future<void> _handleSignOut() async {
    await AuthScope.of(context).signOut();
    if (!mounted) return;

    Navigator.popUntil(context, (route) => route.isFirst);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignInPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color ivory = Color(0xFFE2D4BF);
    const Color softLine = Color(0x99CDBDA7);

    final gameState = GameStateScope.of(context);
    final currentNodeId = gameState.currentNodeId;
    final node = storyNodes[currentNodeId]!;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(
        onLibrary: _confirmLibraryFromDrawer,
        onRestart: _confirmRestartFromDrawer,
        onSettings: _showSettingsPlaceholder,
        onSignOut: _handleSignOut,
      ),
      bottomNavigationBar: const FooterNavBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              node.backgroundImage,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.22),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.08),
                    Colors.black.withOpacity(0.18),
                    Colors.black.withOpacity(0.48),
                    Colors.black.withOpacity(0.78),
                  ],
                  stops: const [0.0, 0.32, 0.68, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.10),
                    Colors.black.withOpacity(0.45),
                  ],
                  stops: const [0.45, 0.78, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          node.dayLabel,
                          style: TextStyle(
                            fontSize: 18,
                            letterSpacing: 3.5,
                            color: ivory.withOpacity(0.95),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          node.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: ivory,
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 2),
                                blurRadius: 18,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withOpacity(0.22),
                            Colors.black.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 1.2,
                            height: 118,
                            margin: const EdgeInsets.only(top: 4, right: 16),
                            color: softLine.withOpacity(0.45),
                          ),
                          Expanded(
                            child: TypewriterText(
                              key: ValueKey(node.id),
                              text: node.text,
                              speed: const Duration(milliseconds: 45),
                              style: TextStyle(
                                fontSize: 21,
                                height: 1.5,
                                color: ivory.withOpacity(0.97),
                                fontWeight: FontWeight.w400,
                                shadows: const [
                                  Shadow(
                                    offset: Offset(0, 2),
                                    blurRadius: 10,
                                    color: Colors.black87,
                                  ),
                                ],
                              ),
                              onComplete: () {
                                if (!mounted) return;
                                setState(() {
                                  _showChoices = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  AnimatedOpacity(
                    opacity: _showChoices ? 1 : 0,
                    duration: const Duration(milliseconds: 500),
                    child: IgnorePointer(
                      ignoring: !_showChoices,
                      child: Column(
                        children: node.isEnding
                            ? [
                                _buildChoiceButton(
                                  text: '처음으로',
                                  textColor: ivory,
                                  onTap: _handleRestart,
                                ),
                              ]
                            : [
                                for (final choice in node.choices) ...[
                                  _buildChoiceButton(
                                    text: choice.text,
                                    textColor: ivory,
                                    onTap: choice.triggersBattle
                                        ? () => _handleBattleChoice(choice.battleTrigger!)
                                        : choice.triggersEncounter
                                            ? () => _handleEncounterChoice(choice.encounterTrigger!)
                                            : choice.triggersMerchant
                                                ? () => _handleMerchantChoice(choice.merchantTrigger!)
                                                : () => _handleNodeChoice(choice.nextNodeId!),
                                  ),
                                  if (choice != node.choices.last)
                                    const SizedBox(height: 14),
                                ],
                              ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: IconButton(
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(Icons.menu_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: HeartsIndicator(
                  hearts: gameState.hearts,
                  maxHearts: GameState.maxHearts,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceButton({
    required String text,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return _HoverChoiceButton(
      text: text,
      textColor: textColor,
      onTap: onTap,
    );
  }
}

class _HoverChoiceButton extends StatefulWidget {
  final String text;
  final Color textColor;
  final VoidCallback onTap;

  const _HoverChoiceButton({
    required this.text,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_HoverChoiceButton> createState() => _HoverChoiceButtonState();
}

class _HoverChoiceButtonState extends State<_HoverChoiceButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          constraints: const BoxConstraints(
            minHeight: 88,
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Opacity(
                    opacity: 0.22,
                    child: Image.asset(
                      UiPaths.choiceBg,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _hovered
                          ? [
                        Colors.black.withOpacity(0.18),
                        Colors.black.withOpacity(0.08),
                      ]
                          : [
                        Colors.black.withOpacity(0.12),
                        Colors.black.withOpacity(0.04),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: _hovered
                          ? widget.textColor.withOpacity(0.60)
                          : widget.textColor.withOpacity(0.28),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.03),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  widget.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.4,
                    color: widget.textColor.withOpacity(_hovered ? 0.98 : 0.90),
                    fontWeight: FontWeight.w400,
                    shadows: const [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 8,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
