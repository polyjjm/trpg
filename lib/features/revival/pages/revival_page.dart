import 'package:flutter/material.dart';

import '../../../core/monetization/admob_monetization_service.dart';
import '../../../core/state/game_state_scope.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 전투에서 패배했을 때(BattleOutcome.lose) 보여주는 부활 화면.
/// 광고를 끝까지 시청하면 HP를 일부 회복하고 이야기를 이어갈 수 있고,
/// 포기하면 라이브러리(메인 화면)로 돌아간다.
///
/// 화면 진입 시 리워드 광고를 미리 로드해 두어, '광고 보고 부활하기' 버튼을
/// 눌렀을 때 대기 시간 없이 바로 광고가 뜨도록 한다.
/// 디버그 빌드에서는 항상 구글 공식 테스트 리워드 광고가 표시된다(AdIds 참고).
class RevivalPage extends StatefulWidget {
  const RevivalPage({super.key});

  @override
  State<RevivalPage> createState() => _RevivalPageState();
}

class _RevivalPageState extends State<RevivalPage> {
  final AdMobMonetizationService _monetizationService = AdMobMonetizationService();
  bool _isShowingAd = false;

  @override
  void initState() {
    super.initState();
    _monetizationService.preloadRewardedAd();
  }

  Future<void> _handleWatchAd() async {
    setState(() => _isShowingAd = true);

    final earnedReward = await _monetizationService.showRewardedAd();

    if (!mounted) return;

    if (!earnedReward) {
      setState(() => _isShowingAd = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('광고를 끝까지 봐야 부활할 수 있어요.')),
      );
      return;
    }

    GameStateScope.of(context).revive();
    Navigator.pop(context, true);
  }

  void _handleGiveUp() {
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.heart_broken_rounded, size: 64, color: _gold),
              const SizedBox(height: 24),
              const Text(
                '쓰러졌습니다',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '광고를 보고 부활해 이야기를 계속 이어가거나,\n여기서 포기할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.white.withOpacity(0.75),
                ),
              ),
              const SizedBox(height: 44),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isShowingAd ? null : _handleWatchAd,
                  icon: _isShowingAd
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.play_circle_fill_rounded),
                  label: Text(_isShowingAd ? '광고 재생 중...' : '광고 보고 부활하기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: _isShowingAd ? null : _handleGiveUp,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.30)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '포기하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
