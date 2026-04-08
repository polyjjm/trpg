import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/constants/asset_paths.dart';
import '../models/battle_card.dart';
import '../models/battle_config.dart';
import '../models/battle_result.dart';
import '../models/battle_reward.dart';
import '../models/battle_unit.dart';
import '../services/battle_service.dart';
import '../widgets/battle_card_select_row.dart';
import '../widgets/battle_hp_bar.dart';

class BattlePage extends StatefulWidget {
  final BattleConfig config;

  const BattlePage({
    super.key,
    required this.config,
  });

  @override
  State<BattlePage> createState() => _BattlePageState();
}

class _BattlePageState extends State<BattlePage> {
  final BattleService _battleService = BattleService();
  final Random _random = Random();

  late BattleUnit player;
  late BattleUnit enemy;
  late BattleReward _reward;
  late List<BattleCard> _battleCards;

  String battleLog = '';
  bool playerTurn = true;
  bool battleEnd = false;
  bool actionLock = false;

  double playerOffsetX = 0;
  double enemyShakeX = 0;

  bool showDamageText = false;
  String damageText = '';

  bool _showCardSelection = false;
  int? _selectedCardIndex;

  @override
  void initState() {
    super.initState();

    player = BattleUnit(
      name: '생존자',
      maxHp: 30,
      hp: 30,
      attack: 8,
    );

    enemy = _createEnemy(widget.config);
    _reward = _createReward(widget.config);
    _battleCards = _battleService.getBattleCards();

    battleLog = widget.config.startMessage;
  }

  BattleUnit _createEnemy(BattleConfig config) {
    final hp = _randomInRange(config.enemyHpRange.min, config.enemyHpRange.max);
    final attack =
    _randomInRange(config.enemyAttackRange.min, config.enemyAttackRange.max);

    return BattleUnit(
      name: config.enemyName,
      maxHp: hp,
      hp: hp,
      attack: attack,
    );
  }

  BattleReward _createReward(BattleConfig config) {
    final minCount = config.minDropCount;
    final maxCount = config.maxDropCount;

    int dropCount = minCount;
    if (maxCount > minCount) {
      dropCount = minCount + _random.nextInt(maxCount - minCount + 1);
    }

    final List<String> itemIds = [];
    final shuffled = [...config.dropItems]..shuffle(_random);

    for (final item in shuffled) {
      if (itemIds.length >= dropCount) break;
      if (_random.nextDouble() <= item.chance) {
        itemIds.add(item.itemId);
      }
    }

    return BattleReward(
      itemIds: itemIds,
      gold: 0,
      exp: 0,
    );
  }

  int _randomInRange(int min, int max) {
    if (max <= min) return min;
    return min + _random.nextInt(max - min + 1);
  }

  Future<void> _playPlayerAttackMotion() async {
    setState(() {
      playerOffsetX = 28;
    });

    await Future.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;

    setState(() {
      playerOffsetX = 0;
    });
  }

  Future<void> _playEnemyHitMotion(int damage) async {
    setState(() {
      damageText = '-$damage';
      showDamageText = true;
      enemyShakeX = -10;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      enemyShakeX = 10;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      enemyShakeX = -6;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      enemyShakeX = 0;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() {
      showDamageText = false;
    });
  }

  Future<void> onAttackPressed() async {
    if (!playerTurn || battleEnd || actionLock) return;

    setState(() {
      _battleCards = _battleService.getBattleCards();
      actionLock = true;
      _showCardSelection = true;
      _selectedCardIndex = null;
      battleLog = '공격 방식을 선택한다.';
    });
  }

  Future<void> onDefendPressed() async {
    if (!playerTurn || battleEnd || actionLock) return;

    setState(() {
      actionLock = true;
      battleLog = '${player.name}이(가) 방어 자세를 취했다.';
      playerTurn = false;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted || battleEnd) return;

    final reducedDamage = (enemy.attack / 2).floor();
    if (reducedDamage > 0) {
      player.takeDamage(reducedDamage);
    }

    setState(() {
      battleLog =
      '${enemy.name}의 공격. ${player.name}이(가) $reducedDamage 데미지를 입었다.';
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    if (player.isDead) {
      setState(() {
        battleLog = widget.config.loseMessage;
        battleEnd = true;
        actionLock = false;
      });

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      Navigator.pop(
        context,
        BattleResult(
          outcome: BattleOutcome.lose,
          remainHp: player.hp,
          battleId: widget.config.id,
          reward: BattleReward.empty(),
          usedItemIds: [],
        ),
      );
      return;
    }

    setState(() {
      playerTurn = true;
      actionLock = false;
      battleLog = '당신의 턴이다.';
    });
  }

  Future<void> onEscapePressed() async {
    if (!playerTurn || battleEnd || actionLock) return;
    if (!widget.config.canEscape) return;

    setState(() {
      actionLock = true;
      battleLog = '${player.name}이(가) 도망을 시도한다.';
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final escapeSuccess = _random.nextDouble() <= widget.config.escapeChance;

    if (escapeSuccess) {
      setState(() {
        battleLog = '도망에 성공했다.';
        battleEnd = true;
        actionLock = false;
      });

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      Navigator.pop(
        context,
        BattleResult(
          outcome: BattleOutcome.escape,
          remainHp: player.hp,
          battleId: widget.config.id,
          reward: BattleReward.empty(),
          usedItemIds: [],
        ),
      );
      return;
    }

    setState(() {
      battleLog = '도망에 실패했다.';
      playerTurn = false;
      actionLock = false;
    });

    await enemyAttack();
  }

  Future<void> onBattleCardSelected(int index) async {
    if (!_showCardSelection || battleEnd) return;

    setState(() {
      _selectedCardIndex = index;
    });

    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    final selectedCard = _battleCards[index];

    setState(() {
      _showCardSelection = false;
    });

    await _resolveAttackCard(selectedCard);
  }

  Future<void> _resolveAttackCard(BattleCard card) async {
    if (!playerTurn || battleEnd) return;

    int damage = 0;
    String judgeText = '';

    switch (card.type) {
      case BattleCardType.fail:
        damage = 0;
        judgeText = '공격 실패!';
        break;
      case BattleCardType.lightAttack:
        damage = 15;
        judgeText = '약공격 적중!';
        break;
      case BattleCardType.attack:
        damage = 20;
        judgeText = '공격 적중!';
        break;
      case BattleCardType.heavyAttack:
        damage = 25;
        judgeText = '강공격 적중!';
        break;
    }

    setState(() {
      battleLog = judgeText;
    });

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    if (damage == 0) {
      setState(() {
        playerTurn = false;
        actionLock = false;
      });
      await enemyAttack();
      return;
    }

    await _playPlayerAttackMotion();
    if (!mounted) return;

    enemy.takeDamage(damage);

    setState(() {
      battleLog = '$judgeText ${enemy.name}에게 $damage 데미지.';
    });

    await _playEnemyHitMotion(damage);
    if (!mounted) return;

    if (enemy.isDead) {
      setState(() {
        battleLog = widget.config.winMessage;
        battleEnd = true;
        actionLock = false;
      });

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      Navigator.pop(
        context,
        BattleResult(
          outcome: BattleOutcome.win,
          remainHp: player.hp,
          battleId: widget.config.id,
          reward: _reward,
          usedItemIds: [],
        ),
      );
      return;
    }

    setState(() {
      playerTurn = false;
      actionLock = false;
    });

    await enemyAttack();
  }

  Future<void> enemyAttack() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || battleEnd) return;

    player.takeDamage(enemy.attack);

    setState(() {
      battleLog =
      '${enemy.name}의 공격. ${player.name}이(가) ${enemy.attack} 데미지를 입었다.';
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    if (player.isDead) {
      setState(() {
        battleLog = widget.config.loseMessage;
        battleEnd = true;
        actionLock = false;
      });

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      Navigator.pop(
        context,
        BattleResult(
          outcome: BattleOutcome.lose,
          remainHp: player.hp,
          battleId: widget.config.id,
          reward: BattleReward.empty(),
          usedItemIds: [],
        ),
      );
      return;
    }

    setState(() {
      playerTurn = true;
      actionLock = false;
      battleLog = '당신의 턴이다.';
    });
  }


  Widget _buildActionButton({
    required String text,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: SizedBox(
        height: 44,
        child: ElevatedButton(
          onPressed: (battleEnd || actionLock) ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black.withOpacity(0.58),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.black.withOpacity(0.30),
            disabledForegroundColor: Colors.white38,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withOpacity(0.16)),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnemyCharacter() {
    return SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: enemy.isDead ? 0.25 : 1,
            child: Image.asset(
              widget.config.enemyImage,
              width: 250,
              height: 250,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            top: 8,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 180),
              offset: showDamageText ? const Offset(0, -0.15) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: showDamageText ? 1 : 0,
                child: Text(
                  damageText,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        blurRadius: 10,
                        color: Colors.black,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCharacter() {
    return SizedBox(
      width: 250,
      height: 250,
      child: Image.asset(
        CharacterPaths.player,
        width: 250,
        height: 250,
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              widget.config.backgroundImage,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.28),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.18),
                    Colors.black.withOpacity(0.12),
                    Colors.black.withOpacity(0.20),
                    Colors.black.withOpacity(0.45),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '전투',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.topRight,
                    child: BattleHpBar(
                      label: enemy.name,
                      currentHp: enemy.hp,
                      maxHp: enemy.maxHp,
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final battleWidth = constraints.maxWidth;
                          final battleHeight = constraints.maxHeight;

                          final enemySize = battleWidth < 700 ? 180.0 : 250.0;
                          final playerSize = battleWidth < 700 ? 180.0 : 250.0;

                          final enemyTop = battleHeight * 0.05;
                          final enemyRight = battleWidth * 0.03 + enemyShakeX;

                          final playerLeft = battleWidth * 0.02 + playerOffsetX;
                          final playerBottom = battleHeight * 0.04;

                          final cardAreaWidth = battleWidth * 0.86;
                          final dimColor = Colors.black.withOpacity(0.30);

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: enemyTop,
                                right: enemyRight,
                                child: SizedBox(
                                  width: enemySize,
                                  height: enemySize,
                                  child: _buildEnemyCharacter(),
                                ),
                              ),

                              Positioned(
                                left: playerLeft,
                                bottom: playerBottom,
                                child: SizedBox(
                                  width: playerSize,
                                  height: playerSize,
                                  child: _buildPlayerCharacter(),
                                ),
                              ),

                              if (_showCardSelection)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: false,
                                    child: Container(
                                      color: Colors.black.withOpacity(0.20),
                                    ),
                                  ),
                                ),

                              if (_showCardSelection)
                                Align(
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: cardAreaWidth,
                                    child: BattleCardSelectRow(
                                      cards: _battleCards,
                                      selectedIndex: _selectedCardIndex,
                                      onSelect: onBattleCardSelected,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: BattleHpBar(
                      label: player.name,
                      currentHp: player.hp,
                      maxHp: player.maxHp,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 72),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Text(
                      battleLog,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildActionButton(
                        text: '공격',
                        onTap: onAttackPressed,
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        text: '방어',
                        onTap: onDefendPressed,
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        text: '도망',
                        onTap: widget.config.canEscape ? onEscapePressed : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}