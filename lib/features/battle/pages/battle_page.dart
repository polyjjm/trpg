import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/state/game_state.dart';
import '../../../core/state/game_state_scope.dart';
import '../inventory/data/item_catalog.dart';
import '../inventory/models/item_effect_type.dart';
import '../inventory/models/item_model.dart';
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

  late GameState _gameState;
  late BattleUnit player;
  late List<BattleUnit> enemies;
  late BattleReward _reward;
  late List<BattleCard> _battleCards;
  late int _playerDefense;

  // 적 각각의 흔들림/데미지 텍스트 연출 상태. enemies와 같은 순서·길이를 유지한다.
  late List<double> _enemyShakeX;
  late List<bool> _showEnemyDamageText;
  late List<String> _enemyDamageText;

  // 다수 적 전투에서 공격 대상을 고를 때 쓰는 상태.
  bool _selectingTarget = false;
  Completer<int>? _targetCompleter;

  final List<String> _usedItemIds = [];
  int _attackBuffBonus = 0;
  double _escapeChanceBonus = 0;

  String battleLog = '';
  bool playerTurn = true;
  bool battleEnd = false;
  bool actionLock = false;

  double playerOffsetX = 0;
  double playerShakeX = 0;

  bool showPlayerDamageText = false;
  String playerDamageText = '';

  bool _showCardSelection = false;
  int? _selectedCardIndex;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    final gameState = GameStateScope.of(context);
    _gameState = gameState;

    player = BattleUnit(
      name: '생존자',
      maxHp: gameState.playerMaxHp,
      hp: gameState.playerHp,
      attack: gameState.playerAttack,
    );
    _playerDefense = gameState.playerDefense;

    enemies = _createEnemies(widget.config);
    _enemyShakeX = List.filled(enemies.length, 0.0);
    _showEnemyDamageText = List.filled(enemies.length, false);
    _enemyDamageText = List.filled(enemies.length, '');

    _reward = _createReward(widget.config, enemies.length);
    _battleCards = _battleService.getBattleCards();

    battleLog = widget.config.startMessage;
  }

  List<BattleUnit> _createEnemies(BattleConfig config) {
    return config.enemies.map((spawn) {
      final hp = _randomInRange(spawn.hpRange.min, spawn.hpRange.max);
      final attack = _randomInRange(spawn.attackRange.min, spawn.attackRange.max);

      return BattleUnit(
        name: spawn.name,
        maxHp: hp,
        hp: hp,
        attack: attack,
      );
    }).toList();
  }

  /// 적 한 마리당 드랍/경험치를 굴려서 합산한다 — 여러 마리를 잡을수록 보상도 커진다.
  BattleReward _createReward(BattleConfig config, int enemyCount) {
    final minCount = config.minDropCount;
    final maxCount = config.maxDropCount;

    final List<String> itemIds = [];
    int totalExp = 0;

    for (var i = 0; i < enemyCount; i++) {
      totalExp += _randomInRange(config.minExp, config.maxExp);

      int dropCount = minCount;
      if (maxCount > minCount) {
        dropCount = minCount + _random.nextInt(maxCount - minCount + 1);
      }

      final shuffled = [...config.dropItems]..shuffle(_random);
      var picked = 0;
      for (final item in shuffled) {
        if (picked >= dropCount) break;
        if (_random.nextDouble() <= item.chance) {
          itemIds.add(item.itemId);
          picked++;
        }
      }
    }

    return BattleReward(
      itemIds: itemIds,
      gold: 0,
      exp: totalExp,
    );
  }

  int _randomInRange(int min, int max) {
    if (max <= min) return min;
    return min + _random.nextInt(max - min + 1);
  }

  /// 방어력을 적용한 피해량. 최소 1의 피해는 항상 들어간다.
  int _mitigatedDamage(int rawAttack) => max(1, rawAttack - _playerDefense);

  bool get _allEnemiesDead => enemies.every((e) => e.isDead);

  /// 공격 대상을 정한다. 살아있는 적이 하나뿐이면 자동으로 그 적을 고르고(기존 1:1 전투와
  /// 동일한 흐름 유지), 여러 마리면 플레이어가 적 스프라이트를 탭할 때까지 기다린다.
  Future<int?> _selectTargetIndex() async {
    final livingIndexes = [
      for (var i = 0; i < enemies.length; i++)
        if (!enemies[i].isDead) i
    ];

    if (livingIndexes.isEmpty) return null;
    if (livingIndexes.length == 1) return livingIndexes.first;

    setState(() {
      battleLog = '공격할 대상을 선택한다.';
      _selectingTarget = true;
    });

    _targetCompleter = Completer<int>();
    final selected = await _targetCompleter!.future;

    if (mounted) {
      setState(() {
        _selectingTarget = false;
      });
    }

    return selected;
  }

  void _onEnemyTargetTap(int index) {
    if (!_selectingTarget) return;
    if (enemies[index].isDead) return;

    final completer = _targetCompleter;
    if (completer == null || completer.isCompleted) return;

    _targetCompleter = null;
    completer.complete(index);
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

  Future<void> _playEnemyHitMotion(int index, int damage) async {
    setState(() {
      _enemyDamageText[index] = '-$damage';
      _showEnemyDamageText[index] = true;
      _enemyShakeX[index] = -10;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      _enemyShakeX[index] = 10;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      _enemyShakeX[index] = -6;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      _enemyShakeX[index] = 0;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() {
      _showEnemyDamageText[index] = false;
    });
  }

  Future<void> _playPlayerHitMotion(int damage) async {
    setState(() {
      playerDamageText = '-$damage';
      showPlayerDamageText = true;
      playerShakeX = -10;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      playerShakeX = 10;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      playerShakeX = -6;
    });

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() {
      playerShakeX = 0;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() {
      showPlayerDamageText = false;
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

    for (final foe in enemies) {
      if (foe.isDead) continue;
      if (player.isDead) break;

      setState(() {
        battleLog = '${foe.name}이(가) 공격을 준비한다!';
      });

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted || battleEnd) return;

      final reducedDamage = (_mitigatedDamage(foe.attack) / 2).floor();
      if (reducedDamage > 0) {
        player.takeDamage(reducedDamage);
      }

      setState(() {
        battleLog =
        '${foe.name}의 공격! ${player.name}이(가) 방어로 피해를 줄여 $reducedDamage 데미지를 입었다.';
      });

      if (reducedDamage > 0) {
        await _playPlayerHitMotion(reducedDamage);
        if (!mounted) return;
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
      }

      if (player.isDead) break;
    }

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
          usedItemIds: _usedItemIds,
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

    final escapeChance =
        (widget.config.escapeChance + _escapeChanceBonus).clamp(0.0, 1.0);
    final escapeSuccess = _random.nextDouble() <= escapeChance;

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
          usedItemIds: _usedItemIds,
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

    final effectiveAttack = player.attack + _attackBuffBonus;

    int damage = 0;
    String judgeText = '';

    switch (card.type) {
      case BattleCardType.fail:
        damage = 0;
        judgeText = '공격 실패!';
        break;
      case BattleCardType.lightAttack:
        damage = (effectiveAttack * 0.8).round();
        judgeText = '약공격 적중!';
        break;
      case BattleCardType.attack:
        damage = (effectiveAttack * 1.0).round();
        judgeText = '공격 적중!';
        break;
      case BattleCardType.heavyAttack:
        damage = (effectiveAttack * 1.4).round();
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

    final targetIndex = await _selectTargetIndex();
    if (!mounted) return;
    if (targetIndex == null) {
      // 살아있는 적이 없다 — 승리 처리가 다른 경로로 이미 끝났을 상황이라 방어적으로만 처리.
      setState(() {
        playerTurn = false;
        actionLock = false;
      });
      return;
    }

    await _playPlayerAttackMotion();
    if (!mounted) return;

    final target = enemies[targetIndex];
    target.takeDamage(damage);

    setState(() {
      battleLog = '$judgeText ${target.name}에게 $damage 데미지.';
    });

    await _playEnemyHitMotion(targetIndex, damage);
    if (!mounted) return;

    if (_allEnemiesDead) {
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
          usedItemIds: _usedItemIds,
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

  /// 살아있는 적들이 순서대로 플레이어를 공격한다.
  Future<void> enemyAttack() async {
    for (final foe in enemies) {
      if (foe.isDead) continue;
      if (player.isDead) break;

      setState(() {
        battleLog = '${foe.name}이(가) 공격을 준비한다!';
      });

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted || battleEnd) return;

      final damage = _mitigatedDamage(foe.attack);
      player.takeDamage(damage);

      setState(() {
        battleLog = '${foe.name}의 공격! ${player.name}이(가) $damage 데미지를 입었다.';
      });

      await _playPlayerHitMotion(damage);
      if (!mounted) return;

      if (player.isDead) break;
    }

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
          usedItemIds: _usedItemIds,
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

  Future<void> onItemPressed() async {
    if (!playerTurn || battleEnd || actionLock) return;

    final usableItems = <MapEntry<String, ItemModel>>[];
    _gameState.inventory.forEach((itemId, count) {
      if (count <= 0) return;
      final item = itemCatalog[itemId];
      if (item != null && item.battleUsable) {
        usableItems.add(MapEntry(itemId, item));
      }
    });

    if (usableItems.isEmpty) {
      setState(() {
        battleLog = '전투 중 사용할 수 있는 아이템이 없다.';
      });
      return;
    }

    setState(() {
      actionLock = true;
    });

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
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

    if (!mounted) return;

    if (selectedItemId == null) {
      setState(() {
        actionLock = false;
      });
      return;
    }

    await _useItem(selectedItemId);
  }

  Future<void> _useItem(String itemId) async {
    final item = itemCatalog[itemId];
    if (item == null) return;

    setState(() {
      actionLock = true;
    });

    _gameState.removeItem(itemId);
    _usedItemIds.add(itemId);

    String logText;
    switch (item.effectType) {
      case ItemEffectType.heal:
        final healed = min(item.value, player.maxHp - player.hp);
        player.heal(item.value);
        logText = '${item.name}을(를) 사용해 체력을 $healed 회복했다.';
        break;
      case ItemEffectType.damage:
        final targetIndex = await _selectTargetIndex();
        if (!mounted) return;
        if (targetIndex != null) {
          final target = enemies[targetIndex];
          target.takeDamage(item.value);
          logText = '${item.name}을(를) 사용해 ${target.name}에게 ${item.value}의 피해를 입혔다.';
        } else {
          logText = '${item.name}을(를) 사용했지만 대상이 없었다.';
        }
        break;
      case ItemEffectType.buff:
        _attackBuffBonus += item.value;
        logText = '${item.name}을(를) 사용해 이번 전투의 공격력이 올랐다.';
        break;
      case ItemEffectType.escapeBoost:
        _escapeChanceBonus += 0.2;
        logText = '${item.name}을(를) 사용해 이번 전투의 도망 확률이 올랐다.';
        break;
    }

    setState(() {
      battleLog = logText;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    if (item.effectType == ItemEffectType.damage && _allEnemiesDead) {
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
          usedItemIds: _usedItemIds,
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

  Widget _buildEnemyCharacter(int index, double size) {
    final foe = enemies[index];
    final spawn = widget.config.enemies[index];
    final isTargetable = _selectingTarget && !foe.isDead;

    return GestureDetector(
      onTap: () => _onEnemyTargetTap(index),
      child: Transform.translate(
        offset: Offset(_enemyShakeX[index], 0),
        child: Container(
          decoration: isTargetable
              ? BoxDecoration(
                  border: Border.all(color: Colors.amberAccent, width: 3),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: foe.isDead ? 0.25 : 1,
                  child: Image.asset(
                    spawn.image,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  top: 8,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 180),
                    offset: _showEnemyDamageText[index]
                        ? const Offset(0, -0.15)
                        : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _showEnemyDamageText[index] ? 1 : 0,
                      child: Text(
                        _enemyDamageText[index],
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
          ),
        ),
      ),
    );
  }

  Widget _buildEnemyHpBars() {
    if (enemies.length == 1) {
      final foe = enemies.first;
      return Align(
        alignment: Alignment.topRight,
        child: BattleHpBar(label: foe.name, currentHp: foe.hp, maxHp: foe.maxHp),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < enemies.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
            child: BattleHpBar(
              label: enemies[i].name,
              currentHp: enemies[i].hp,
              maxHp: enemies[i].maxHp,
              width: 150,
            ),
          ),
      ],
    );
  }

  Widget _buildPlayerCharacter() {
    return SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Image.asset(
            CharacterPaths.player,
            width: 250,
            height: 250,
            fit: BoxFit.contain,
          ),
          Positioned(
            top: 8,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 180),
              offset: showPlayerDamageText ? const Offset(0, -0.15) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: showPlayerDamageText ? 1 : 0,
                child: Text(
                  playerDamageText,
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
                  _buildEnemyHpBars(),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final battleWidth = constraints.maxWidth;
                          final battleHeight = constraints.maxHeight;

                          final enemySize = enemies.length <= 1
                              ? (battleWidth < 700 ? 180.0 : 250.0)
                              : (battleWidth < 700 ? 110.0 : 160.0);
                          final playerSize = battleWidth < 700 ? 180.0 : 250.0;

                          final enemyTop = battleHeight * 0.05;

                          final playerLeft =
                              battleWidth * 0.02 + playerOffsetX + playerShakeX;
                          final playerBottom = battleHeight * 0.04;

                          final cardAreaWidth = battleWidth * 0.86;

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (enemies.length == 1)
                                Positioned(
                                  top: enemyTop,
                                  right: battleWidth * 0.03,
                                  child: SizedBox(
                                    width: enemySize,
                                    height: enemySize,
                                    child: _buildEnemyCharacter(0, enemySize),
                                  ),
                                )
                              else
                                Positioned(
                                  top: enemyTop,
                                  left: battleWidth * 0.05,
                                  right: battleWidth * 0.05,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      for (var i = 0; i < enemies.length; i++)
                                        SizedBox(
                                          width: enemySize,
                                          height: enemySize,
                                          child: _buildEnemyCharacter(i, enemySize),
                                        ),
                                    ],
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
                        text: '아이템',
                        onTap: onItemPressed,
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
