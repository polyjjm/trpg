import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/state/game_state.dart';
import '../../../core/state/game_state_scope.dart';
import '../../../core/state/reading_progress_repository.dart';
import '../data/story_pack_repository.dart';
import '../models/story_pack.dart';
import '../widgets/story_cover_card.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

enum _LibraryFilter { all, inProgress, interactive, linear }

extension on _LibraryFilter {
  String get label => switch (this) {
    _LibraryFilter.all => '전체',
    _LibraryFilter.inProgress => '읽는 중',
    _LibraryFilter.interactive => '인터랙티브',
    _LibraryFilter.linear => '일반소설',
  };
}

/// 하단 탭의 "내 서재" — 소유(오늘은 유료 팩이 없어 사실상 모든 무료 팩이
/// 여기 포함된다, StoryPackDetailPage의 owned 판정과 같은 기준) + 읽는 중 +
/// 완료한 팩을 모아 보여준다. 진행 상황은 새 추적 소스를 만들지 않고
/// GameState.progressFor()/ReadingProgressRepository를 그대로 재사용한다.
class MyLibraryTab extends StatefulWidget {
  const MyLibraryTab({super.key});

  @override
  State<MyLibraryTab> createState() => _MyLibraryTabState();
}

class _MyLibraryTabState extends State<MyLibraryTab> {
  final StoryPackRepository _packRepository = StoryPackRepository();
  late final Stream<List<StoryPack>> _packsStream = _packRepository.watchVisiblePacks();
  final ReadingProgressRepository _progressRepository = ReadingProgressRepository();

  _LibraryFilter _filter = _LibraryFilter.all;
  final Set<String> _requestedProgressPackIds = {};

  /// 팩 목록을 받을 때마다, 이번 세션에 리더를 아직 한 번도 안 연 팩들의
  /// 진행 상황을 Firestore에서 미리 불러와 GameState에 채워 둔다 — 안 그러면
  /// 이번 세션에 실제로 읽은 팩만 진행률 바/완료 배지가 보인다(내 서재는
  /// 세션과 무관하게 "지금까지의 내 진행 상황"을 보여줘야 하는 화면이라서).
  /// 이미 요청한 팩은 다시 요청하지 않는다.
  void _bulkLoadProgress(GameState gameState, String? uid, List<StoryPack> packs) {
    if (uid == null) return;
    for (final pack in packs) {
      if (_requestedProgressPackIds.contains(pack.id)) continue;
      if (gameState.progressFor(pack.id) != null) continue;
      _requestedProgressPackIds.add(pack.id);
      unawaited(_loadOne(gameState, uid, pack.id));
    }
  }

  Future<void> _loadOne(GameState gameState, String uid, String packId) async {
    try {
      final progress = await _progressRepository.load(uid, packId);
      if (!mounted || progress == null) return;
      gameState.seedPackProgress(packId, progress);
    } catch (e) {
      debugPrint('내 서재 진행 상황 불러오기 실패($packId): $e');
    }
  }

  bool _inMyLibrary(StoryPack pack, GameState gameState) {
    return pack.isFree || gameState.ownsPack(pack.id) || gameState.progressFor(pack.id) != null;
  }

  List<StoryPack> _applyFilter(List<StoryPack> packs, GameState gameState) {
    final base = packs.where((p) => _inMyLibrary(p, gameState)).toList();
    switch (_filter) {
      case _LibraryFilter.all:
        return base;
      case _LibraryFilter.inProgress:
        return base.where((p) {
          final progress = gameState.progressFor(p.id);
          return progress != null && !progress.completed;
        }).toList();
      case _LibraryFilter.interactive:
        return base.where((p) => p.format == StoryPackFormat.interactive).toList();
      case _LibraryFilter.linear:
        return base.where((p) => p.format == StoryPackFormat.linear).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = GameStateScope.of(context);
    final uid = AuthScope.of(context).userId;

    // 콘텐츠 최대 폭 캡은 없다 — 홈 탭과 마찬가지로 브라우저 실제 폭
    // 그대로 꽉 채운다. crossAxisCount는 여전히 LayoutBuilder의 실제 폭
    // 기준으로 고르므로, 초광폭 화면에서는 카드가 더 늘어나는 대신 같은
    // 6열이 폭에 맞춰 넓어진다.
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '내 서재',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ivory),
              ),
              const SizedBox(height: 16),
              _buildFilterRow(),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<StoryPack>>(
                  stream: _packsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '서재를 불러오지 못했어요',
                          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
                        ),
                      );
                    }

                    final packs = snapshot.data ?? const <StoryPack>[];
                    _bulkLoadProgress(gameState, uid, packs);
                    final visible = _applyFilter(packs, gameState);

                    if (visible.isEmpty) {
                      return Center(
                        child: Text(
                          uid == null ? '로그인하면 내 서재가 채워져요' : '아직 이 조건에 맞는 이야기가 없어요',
                          style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
                        ),
                      );
                    }

                    // StoryCoverCard + storyCoverGridDelegate — 홈 탭
                    // 장르 그리드(home_tab.dart._buildGenreGrid)와
                    // 완전히 같은 카드 위젯·같은 그리드 배치 함수를
                    // 쓴다. 예전엔 내 서재가 자체 카드(_LibraryGridCard)
                    // 와 자체 childAspectRatio를 따로 들고 있어서,
                    // 숫자를 맞춰놔도 카드 내부 구성이 달라 표지 비율이
                    // 계속 미묘하게 어긋났다 — 위젯 자체를 공유해
                    // 구조적으로 그럴 일이 없게 한다.
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = constraints.maxWidth >= storyGridWideBreakpoint ? 6 : 4;
                        return GridView.builder(
                          padding: const EdgeInsets.only(bottom: 20),
                          itemCount: visible.length,
                          gridDelegate: storyCoverGridDelegate(crossAxisCount: crossAxisCount),
                          // showPriceRow는 일부러 안 끈다(기본값 true) —
                          // 홈 탭 장르 그리드가 showGenreTag만 끄고
                          // showPriceRow는 그대로 두는 것과 똑같이
                          // 맞춰야 한다. 예전에 여기서만
                          // showPriceRow: false를 줬던 게 실제 크기
                          // 차이의 원인이었다 — 같은 childAspectRatio라도
                          // 카드 안 텍스트 줄 수가 다르면(1줄 vs 2줄)
                          // 표지가 차지하는 비율이 달라져 "위젯을
                          // 공유해도 다르게 보이는" 결과가 났다.
                          itemBuilder: (context, index) => StoryCoverCard(
                            pack: visible[index],
                            showGenreTag: false,
                            progress: gameState.progressFor(visible[index].id),
                          ),
                        );
                      },
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

  Widget _buildFilterRow() {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _LibraryFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _LibraryFilter.values[index];
          final selected = filter == _filter;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => _filter = filter),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _gold : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected ? _gold : Colors.white.withOpacity(0.14)),
              ),
              child: Text(
                filter.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.black : _ivory.withOpacity(0.75),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
