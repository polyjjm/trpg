import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/constants/asset_paths.dart';
import '../models/battle_config.dart';
import '../models/battle_result.dart';
import '../models/battle_reward.dart';
import '../models/battle_unit.dart';
import '../services/battle_service.dart';

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

  late BattleUnit player;
  late BattleUnit enemy;
  late BattleReward _reward;

  String battleLog = '';
  bool playerTurn = true;
  bool battleEnd = false;
  bool actionLock = false;

  double playerOffsetX = 0;
  double enemyShakeX = 0;

  bool showDamageText = false;
  String damageText = '';

  @override
  void initState() {
    super.initState();

    player = BattleUnit(
      name: '생존자',
      maxHp: 30,
      hp: 30,
      attack: 8,
    );

    enemy = _battleService.createEnemy(widget.config);
    _reward = _battleService.createReward(widget.config);

    battleLog = widget.config.startMessage;
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

  Future<void> playerAttack() async {
    if (!playerTurn || battleEnd || actionLock) return;

    setState(() {
      actionLock = true;
      battleLog = '${player.name}이(가) 공격 자세를 취했다.';
    });

    await _playPlayerAttackMotion();
    if (!mounted) return;

    enemy.takeDamage(player.attack);

    setState(() {
      battleLog = '${player.name}의 공격. ${enemy.name}에게 ${player.attack} 데미지.';
    });

    await _playEnemyHitMotion(player.attack);
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
    });

    await enemyAttack();
  }

  Future<void> enemyAttack() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || battleEnd) return;

    player.takeDamage(enemy.attack);

    setState(() {
      battleLog = '${enemy.name}의 공격. ${player.name}이(가) ${enemy.attack} 데미지를 입었다.';
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

  Future<void> defend() async {
    if (!playerTurn || battleEnd || actionLock) return;

    setState(() {
      actionLock = true;
      battleLog = '${player.name}이(가) 방어 태세를 취했다.';
      playerTurn = false;
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || battleEnd) return;

    final reducedDamage = (enemy.attack / 2).floor();
    player.takeDamage(reducedDamage);

    setState(() {
      battleLog = '${enemy.name}의 공격을 방어했다. ${reducedDamage} 데미지만 받았다.';
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

  Future<void> tryEscape() async {
    if (!playerTurn || battleEnd || actionLock) return;
    if (!widget.config.canEscape) return;

    setState(() {
      actionLock = true;
      battleLog =
      '도망을 시도했다... (${(widget.config.escapeChance * 100).toInt()}%)';
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final escaped = _battleService.tryEscape(widget.config);

    if (escaped) {
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
      battleLog = '도망에 실패했다!';
      playerTurn = false;
      actionLock = false;
    });

    await enemyAttack();
  }

  Widget _buildHpBar({
    required String name,
    required int hp,
    required int maxHp,
    required Alignment alignment,
  }) {
    final ratio = maxHp == 0 ? 0.0 : hp / maxHp;

    return Align(
      alignment: alignment,
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.48),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name HP $hp / $maxHp',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 12,
                backgroundColor: Colors.white.withOpacity(0.14),
              ),
            ),
          ],
        ),
      ),
    );
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
                  _buildHpBar(
                    name: enemy.name,
                    hp: enemy.hp,
                    maxHp: enemy.maxHp,
                    alignment: Alignment.topRight,
                  ),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(),
                          ),
                          Positioned(
                            top: 30,
                            right: 50 + enemyShakeX,
                            child: _buildEnemyCharacter(),
                          ),
                          Positioned(
                            left: 10 + playerOffsetX,
                            bottom: 20,
                            child: _buildPlayerCharacter(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildHpBar(
                    name: player.name,
                    hp: player.hp,
                    maxHp: player.maxHp,
                    alignment: Alignment.bottomLeft,
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
                        onTap: playerAttack,
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        text: '방어',
                        onTap: defend,
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        text: '도망',
                        onTap: widget.config.canEscape ? tryEscape : null,
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