import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/audio/audio_service.dart';
import '../../../core/audio/system_sfx.dart';
import '../../../core/constants/asset_paths.dart';
import '../../../core/state/game_state.dart';
import '../../../core/state/game_state_scope.dart';
import '../../battle/inventory/data/item_catalog.dart';
import '../data/barter_offers.dart';
import '../models/barter_offer.dart';
import '../widgets/coin_flip_display.dart';

enum _MerchantView { hub, barter, coinFlip }

class MerchantPage extends StatefulWidget {
  const MerchantPage({super.key});

  @override
  State<MerchantPage> createState() => _MerchantPageState();
}

class _MerchantPageState extends State<MerchantPage> {
  final Random _random = Random();

  late GameState _gameState;
  bool _initialized = false;

  _MerchantView _view = _MerchantView.hub;
  String? _statusMessage;

  // 동전 던지기 상태
  String? _wagerItemId;
  bool _isFlipping = false;
  bool _flipDisplayHeads = true;
  bool? _didWin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    _gameState = GameStateScope.of(context);
  }

  BarterOffer? _offerFor(String itemId) {
    for (final offer in barterOffers) {
      if (offer.giveItemId == itemId) return offer;
    }
    return null;
  }

  void _goToHub() {
    setState(() {
      _view = _MerchantView.hub;
      _wagerItemId = null;
      _isFlipping = false;
      _didWin = null;
    });
  }

  void _executeBarter(String giveItemId) {
    final offer = _offerFor(giveItemId);
    if (offer == null) return;

    final removed = _gameState.removeItem(giveItemId, 1);
    if (!removed) return;
    _gameState.addItem(offer.receiveItemId, 1);
    AudioService.instance.playSfx(SystemSfx.itemPickup.assetPath);

    final giveName = itemCatalog[giveItemId]?.name ?? giveItemId;
    final receiveName =
        itemCatalog[offer.receiveItemId]?.name ?? offer.receiveItemId;

    setState(() {
      _statusMessage = '$giveName을(를) 건네고 $receiveName을(를) 받았다.';
    });
  }

  Future<void> _callAndFlip(bool callHeads) async {
    final itemId = _wagerItemId;
    if (itemId == null || _isFlipping) return;

    setState(() {
      _isFlipping = true;
      _didWin = null;
    });

    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(milliseconds: 110));
      if (!mounted) return;
      setState(() {
        _flipDisplayHeads = !_flipDisplayHeads;
      });
    }

    final resultHeads = _random.nextBool();
    final win = resultHeads == callHeads;
    final itemName = itemCatalog[itemId]?.name ?? itemId;

    if (win) {
      _gameState.addItem(itemId, 1);
      AudioService.instance.playSfx(SystemSfx.itemPickup.assetPath);
    } else {
      _gameState.removeItem(itemId, 1);
    }

    if (!mounted) return;

    setState(() {
      _isFlipping = false;
      _flipDisplayHeads = resultHeads;
      _didWin = win;
      _statusMessage = win
          ? '동전 맞추기 성공! $itemName을(를) 하나 더 얻었다.'
          : '동전 맞추기 실패... $itemName을(를) 잃었다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            // TODO: 상인 전용 배경 이미지 애셋 필요 — 우선 스토리 배경을 재사용한다.
            child: Image.asset(
              BackgroundPaths.chapter1Bg,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '떠돌이 상인',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_view) {
      case _MerchantView.hub:
        return _buildHub();
      case _MerchantView.barter:
        return _buildBarter();
      case _MerchantView.coinFlip:
        return _buildCoinFlip();
    }
  }

  Widget _buildHub() {
    final hasItems = _gameState.inventory.values.any((count) => count > 0);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '"어이, 살아있었나. 물건 좀 보고 가겠나?"',
            style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (_statusMessage != null) ...[
            _buildStatusBanner(_statusMessage!),
            const SizedBox(height: 20),
          ],
          _buildMenuButton(
            text: '물물교환',
            subtitle: '가진 아이템을 다른 아이템과 바꾼다.',
            onTap: () => setState(() {
              _view = _MerchantView.barter;
              _statusMessage = null;
            }),
          ),
          const SizedBox(height: 12),
          _buildMenuButton(
            text: '동전 던지기 내기',
            subtitle: hasItems
                ? '아이템을 걸고 앞/뒤를 맞추면 하나 더 받고, 틀리면 잃는다.'
                : '걸 수 있는 아이템이 없다.',
            onTap: hasItems
                ? () => setState(() {
                      _view = _MerchantView.coinFlip;
                      _statusMessage = null;
                    })
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBarter() {
    final offers = <MapEntry<String, BarterOffer>>[];
    _gameState.inventory.forEach((itemId, count) {
      if (count <= 0) return;
      final offer = _offerFor(itemId);
      if (offer != null) offers.add(MapEntry(itemId, offer));
    });

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBackToHubButton(),
          const SizedBox(height: 8),
          if (_statusMessage != null) ...[
            _buildStatusBanner(_statusMessage!),
            const SizedBox(height: 16),
          ],
          if (offers.isEmpty)
            const Text(
              '교환할 수 있는 아이템이 없다.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            )
          else
            for (final entry in offers) ...[
              _buildBarterTile(entry.key, entry.value),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildBarterTile(String giveItemId, BarterOffer offer) {
    final giveName = itemCatalog[giveItemId]?.name ?? giveItemId;
    final receiveName = itemCatalog[offer.receiveItemId]?.name ?? offer.receiveItemId;
    final count = _gameState.inventory[giveItemId] ?? 0;

    return _buildMenuButton(
      text: '$giveName x$count  →  $receiveName',
      subtitle: '탭하면 1개를 교환한다.',
      onTap: () => _executeBarter(giveItemId),
    );
  }

  Widget _buildCoinFlip() {
    if (_wagerItemId == null) {
      return _buildCoinFlipItemPicker();
    }
    if (_didWin == null) {
      return _buildCoinFlipCallStep();
    }
    return _buildCoinFlipResultStep();
  }

  Widget _buildCoinFlipItemPicker() {
    final items = _gameState.inventory.entries.where((e) => e.value > 0).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBackToHubButton(),
          const SizedBox(height: 8),
          const Text(
            '걸 아이템을 선택한다.',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text('걸 수 있는 아이템이 없다.', style: TextStyle(color: Colors.white70))
          else
            for (final entry in items) ...[
              _buildMenuButton(
                text: '${itemCatalog[entry.key]?.name ?? entry.key} x${entry.value}',
                subtitle: '이 아이템을 걸고 동전 던지기를 한다.',
                onTap: () => setState(() {
                  _wagerItemId = entry.key;
                }),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildCoinFlipCallStep() {
    final itemName = itemCatalog[_wagerItemId]?.name ?? _wagerItemId!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _isFlipping ? null : () => setState(() => _wagerItemId = null),
          icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
          label: const Text('아이템 다시 선택', style: TextStyle(color: Colors.white70)),
        ),
        const SizedBox(height: 8),
        Text(
          '$itemName을(를) 걸었다. 앞면일까, 뒷면일까?',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 24),
        Center(
          child: CoinFlipDisplay(isFlipping: _isFlipping, headsShown: _flipDisplayHeads),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildMenuButton(
                text: '앞면',
                onTap: _isFlipping ? null : () => _callAndFlip(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMenuButton(
                text: '뒷면',
                onTap: _isFlipping ? null : () => _callAndFlip(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoinFlipResultStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: CoinFlipDisplay(isFlipping: false, headsShown: _flipDisplayHeads),
        ),
        const SizedBox(height: 20),
        if (_statusMessage != null) _buildStatusBanner(_statusMessage!),
        const SizedBox(height: 20),
        _buildMenuButton(
          text: '확인',
          onTap: _goToHub,
        ),
      ],
    );
  }

  Widget _buildBackToHubButton() {
    return TextButton.icon(
      onPressed: _goToHub,
      icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
      label: const Text('상인 메뉴로', style: TextStyle(color: Colors.white70)),
    );
  }

  Widget _buildStatusBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
    );
  }

  Widget _buildMenuButton({
    required String text,
    String? subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(enabled ? 0.55 : 0.30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(enabled ? 0.20 : 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white24,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
