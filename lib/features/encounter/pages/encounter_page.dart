import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/audio/audio_service.dart';
import '../../../core/audio/system_sfx.dart';
import '../../../core/auth/auth_scope.dart';
import '../../../core/state/game_state.dart';
import '../../../core/state/game_state_scope.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/footer_nav_bar.dart';
import '../../../widgets/hearts_indicator.dart';
import '../../auth/pages/sign_in_page.dart';
import '../../battle/inventory/data/item_catalog.dart';
import '../../battle/inventory/models/item_effect_type.dart';
import '../../battle/inventory/models/item_model.dart';
import '../models/encounter_config.dart';
import '../models/encounter_result.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 카드 기반 BattlePage 대신, 일반 적과의 가벼운 조우를 텍스트 + 선택지로 처리하는 화면.
class EncounterPage extends StatefulWidget {
  final EncounterConfig config;

  const EncounterPage({super.key, required this.config});

  @override
  State<EncounterPage> createState() => _EncounterPageState();
}

class _EncounterPageState extends State<EncounterPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Random _random = Random();

  late GameState _gameState;
  bool _initialized = false;

  late final AnimationController _revealController;
  late final Animation<double> _revealOpacity;
  late final Animation<double> _revealScale;

  bool _revealing = true;
  bool _resolving = false;
  late String _message;

  @override
  void initState() {
    super.initState();
    _message = widget.config.description;

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _revealOpacity = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOut,
    );
    _revealScale = Tween<double>(begin: 1.12, end: 1.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOutCubic),
    );
    _revealController.forward();

    _startRevealTimer();
  }

  Future<void> _startRevealTimer() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _revealing = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    _gameState = GameStateScope.of(context);
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  Future<void> _onAttackPressed() async {
    if (_resolving) return;

    setState(() {
      _resolving = true;
      _message = '${widget.config.enemyName}에게 달려든다...';
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final success = _random.nextDouble() <= widget.config.attackSuccessChance;
    if (success) {
      setState(() {
        _message = '${widget.config.enemyName}을(를) 물리쳤다.';
      });

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      Navigator.pop(
        context,
        const EncounterResult(outcome: EncounterOutcome.win),
      );
      return;
    }

    await _takeHit('공격당했다. 하트를 잃었다.');
  }

  Future<void> _onEscapePressed() async {
    if (_resolving) return;

    setState(() {
      _resolving = true;
      _message = '틈을 노려 도망친다...';
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final success = _random.nextDouble() <= widget.config.escapeChance;
    if (success) {
      setState(() {
        _message = '도망에 성공했다.';
      });

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      Navigator.pop(
        context,
        const EncounterResult(outcome: EncounterOutcome.escaped),
      );
      return;
    }

    await _takeHit('도망에 실패했다. 하트를 잃었다.');
  }

  Future<void> _takeHit(String message) async {
    setState(() {
      _message = message;
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final dead = _gameState.loseHeart();
    AudioService.instance.playSfx(SystemSfx.heartLose.assetPath);
    if (dead) {
      setState(() {
        _message = '더 이상 버틸 수 없었다...';
      });

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      Navigator.pop(
        context,
        const EncounterResult(outcome: EncounterOutcome.dead),
      );
      return;
    }

    setState(() {
      _resolving = false;
    });
  }

  Future<void> _onItemPressed() async {
    if (_resolving) return;

    final usableItems = <MapEntry<String, ItemModel>>[];
    _gameState.inventory.forEach((itemId, count) {
      if (count <= 0) return;
      final item = itemCatalog[itemId];
      if (item != null &&
          item.battleUsable &&
          item.effectType == ItemEffectType.heal) {
        usableItems.add(MapEntry(itemId, item));
      }
    });

    if (usableItems.isEmpty) {
      setState(() {
        _message = '사용할 수 있는 아이템이 없다.';
      });
      return;
    }

    final selectedItemId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '아이템 사용',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in usableItems)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${entry.value.name} x${_gameState.inventory[entry.key]}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      entry.value.description,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () => Navigator.pop(sheetContext, entry.key),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedItemId == null) return;

    final item = itemCatalog[selectedItemId]!;
    _gameState.removeItem(selectedItemId);
    _gameState.healHeart();

    setState(() {
      _message = '${item.name}을(를) 사용해 하트를 하나 회복했다.';
    });
  }

  void _confirmRestartFromDrawer() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text('처음부터 다시 시작', style: TextStyle(color: Colors.white)),
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
              _gameState.resetProgress();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text(
              '다시 시작',
              style: TextStyle(color: Colors.redAccent),
            ),
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
        title: const Text('라이브러리로 돌아가기', style: TextStyle(color: Colors.white)),
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
              widget.config.backgroundImage,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.40)),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _revealing ? _buildReveal() : _buildEncounterPanel(),
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
                  hearts: _gameState.hearts,
                  maxHearts: GameState.maxHearts,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReveal() {
    return Center(
      key: const ValueKey('encounter_reveal'),
      child: FadeTransition(
        opacity: _revealOpacity,
        child: ScaleTransition(
          scale: _revealScale,
          child: Image.asset(
            widget.config.enemyImage,
            width: 320,
            height: 320,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildEncounterPanel() {
    return SafeArea(
      key: const ValueKey('encounter_panel'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          children: [
            const SizedBox(height: 48),
            const Spacer(),
            Image.asset(
              widget.config.enemyImage,
              width: 200,
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
              ),
              child: Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildChoiceButton(text: '공격', onTap: _onAttackPressed),
            const SizedBox(height: 12),
            _buildChoiceButton(text: '도망', onTap: _onEscapePressed),
            const SizedBox(height: 12),
            _buildChoiceButton(text: '아이템', onTap: _onItemPressed),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceButton({
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _resolving ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(_resolving ? 0.20 : 0.32),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: _ivory.withOpacity(_resolving ? 0.15 : 0.35),
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            color: _ivory.withOpacity(_resolving ? 0.4 : 0.92),
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
