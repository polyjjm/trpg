import 'package:flutter/material.dart';
import 'widgets/loading.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'features/story/widgets/story_page.dart';

void main() {
  runApp(const MyApp());
}

// 앱 시작점
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zombie Story Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'NotoSansKR',
      ),
      home: const MainPage(),
    );
  }
}

// 메인 화면
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    if (kIsWeb) {
      // ignore: undefined_prefixed_name
      final loader = html.document.getElementById('app-loading');
      if (loader != null) {
        loader.remove();
      }
    }

    await Future.delayed(const Duration(milliseconds: 1400));

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  void _showLoading() {
    setState(() {
      _isLoading = true;
    });
  }

  void _hideLoading() {
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _handleMenuAction(String label) async {
    _showLoading();

    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    _hideLoading();

    debugPrint('$label 클릭');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 페이지는 다음 단계에서 연결할 예정입니다.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(
            child: Image.asset(
              'assets/images/main.png',
              fit: BoxFit.cover,
            ),
          ),

          // 전체 어두운 오버레이
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.42),
            ),
          ),

          // 위쪽은 조금 투명, 아래쪽은 더 무겁게
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.10),
                    Colors.black.withOpacity(0.22),
                    Colors.black.withOpacity(0.58),
                    Colors.black.withOpacity(0.88),
                  ],
                  stops: const [0.0, 0.28, 0.65, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.28),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: Text(
                          '폐허가 된 도시, 살아남은 선택들',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.82),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          _handleMenuAction('상단 설정');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.28),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: Colors.white.withOpacity(0.92),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // 메인 카피
                  Text(
                    'ZOMBIE ROAD',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.8,
                      color: Colors.white.withOpacity(0.96),
                      height: 1.0,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Container(
                    width: 230,
                    height: 2,
                    color: const Color(0xFFF0E68C).withOpacity(0.9),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    '무너진 거리에서\n내일을 고를 수 있을까.',
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.94),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    '선택은 기록이 되고, 기록은 생존이 된다.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.white.withOpacity(0.70),
                    ),
                  ),

                  const SizedBox(height: 34),

                  // 짧은 설명 박스
                  Container(
                    width: 280,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.26),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 18,
                          color: Colors.white.withOpacity(0.78),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '스토리 선택형 생존 게임\n탐색, 전투, 아이템, 확률 이벤트가 이어집니다.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: Colors.white.withOpacity(0.74),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 38),

                  // 하단 메뉴 카드들
                  Row(
                    children: [
                      Expanded(
                        flex: 14,
                        child: _buildPrimaryMenuCard(
                          title: '새 게임',
                          subtitle: '폐허가 된 도시로 들어갑니다',
                          icon: Icons.play_arrow_rounded,
                          onTap: () async {
                            _showLoading();

                            await Future.delayed(const Duration(milliseconds: 800));

                            if (!mounted) return;

                            _hideLoading();

                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const StoryPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 10,
                        child: Column(
                          children: [
                            _buildSideMenuCard(
                              title: '이어하기',
                              icon: Icons.history_rounded,
                              onTap: () {
                                _handleMenuAction('이어하기');
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildSideMenuCard(
                              title: '기록',
                              icon: Icons.menu_book_rounded,
                              onTap: () {
                                _handleMenuAction('기록');
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 하단 보조 메뉴
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildBottomIconButton(
                          icon: Icons.collections_bookmark_outlined,
                          label: '도감',
                          onTap: () {
                            _handleMenuAction('도감');
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildBottomIconButton(
                          icon: Icons.settings_outlined,
                          label: '설정',
                          onTap: () {
                            _handleMenuAction('설정');
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildBottomIconButton(
                          icon: Icons.campaign_outlined,
                          label: '공지',
                          onTap: () {
                            _handleMenuAction('공지');
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildBottomIconButton(
                          icon: Icons.info_outline_rounded,
                          label: '정보',
                          onTap: () {
                            _handleMenuAction('정보');
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Center(
                    child: Text(
                      'ver 0.0.1',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.40),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // loading.dart 사용
          if (_isLoading) const Loading(message: '세상을 불러오는 중...'),
        ],
      ),
    );
  }

  Widget _buildPrimaryMenuCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 132,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.34),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFF0E68C).withOpacity(0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 28,
              color: const Color(0xFFF0E68C),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFFF0E68C),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white.withOpacity(0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideMenuCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withOpacity(0.10),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.white.withOpacity(0.88),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.white.withOpacity(0.82),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.3,
                color: Colors.white.withOpacity(0.76),
              ),
            ),
          ],
        ),
      ),
    );
  }
}