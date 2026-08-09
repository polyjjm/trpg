import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/ads/ad_ids.dart';
import '../../../core/state/game_state_scope.dart';
import '../../wallet/pages/charge_page.dart';
import '../data/notices.dart';
import '../data/story_packs.dart';
import '../widgets/notice_card.dart';
import '../widgets/story_pack_card.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 게임 진입 전 라이브러리(카탈로그) 화면 — 밀리의서재류 서재 앱처럼
/// 공지사항과 이야기 팩 표지 그리드를 보여주고, 검색으로 좁혀볼 수 있다.
/// 팩을 고르면 상세 화면으로 넘어간다. 로그인 직후 항상 이 화면으로 들어온다.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    final bannerAd = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _isBannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('배너 광고 로드 실패: $error');
          ad.dispose();
          _bannerAd = null;
        },
      ),
    );

    _bannerAd = bannerAd;
    bannerAd.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filteredPacks = query.isEmpty
        ? storyPacks
        : storyPacks
            .where((pack) =>
                pack.title.toLowerCase().contains(query) ||
                pack.authorName.toLowerCase().contains(query))
            .toList();

    final cashBalance = GameStateScope.of(context).cashBalance;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, cashBalance),
              const SizedBox(height: 20),
              _buildBannerAd(),
              _buildSearchField(),
              const SizedBox(height: 28),
              _buildSectionTitle('공지사항'),
              const SizedBox(height: 10),
              _buildNoticeRow(),
              const SizedBox(height: 28),
              _buildSectionTitle('스토리 둘러보기'),
              const SizedBox(height: 14),
              Expanded(
                child: filteredPacks.isEmpty
                    ? _buildEmptyResult()
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: filteredPacks.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.62,
                        ),
                        itemBuilder: (context, index) {
                          return StoryPackCard(pack: filteredPacks[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int cashBalance) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.14),
            shape: BoxShape.circle,
            border: Border.all(color: _gold.withOpacity(0.40)),
          ),
          child: const Icon(Icons.menu_book_rounded, color: _gold, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ZOMBIE ROAD 라이브러리',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: _ivory,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '오늘은 어떤 이야기를 만나볼까요?',
                style: TextStyle(fontSize: 12.5, color: _ivory.withOpacity(0.60)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildCashChip(context, cashBalance),
      ],
    );
  }

  Widget _buildCashChip(BuildContext context, int cashBalance) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChargePage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withOpacity(0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on_rounded, color: _gold, size: 16),
            const SizedBox(width: 4),
            Text(
              '$cashBalance',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _ivory,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '충전',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerAd() {
    final bannerAd = _bannerAd;
    if (!_isBannerLoaded || bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: SizedBox(
          width: bannerAd.size.width.toDouble(),
          height: bannerAd.size.height.toDouble(),
          child: AdWidget(ad: bannerAd),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '제목 또는 작가로 검색',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: _ivory.withOpacity(0.60), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: _ivory,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildNoticeRow() {
    if (notices.isEmpty) {
      return Text(
        '등록된 공지사항이 없습니다',
        style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.55)),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: notices.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => NoticeCard(notice: notices[index]),
      ),
    );
  }

  Widget _buildEmptyResult() {
    return Center(
      child: Text(
        '검색 결과가 없습니다',
        style: TextStyle(fontSize: 14, color: _ivory.withOpacity(0.55)),
      ),
    );
  }
}
