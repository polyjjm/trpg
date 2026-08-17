import 'package:flutter/material.dart';

import '../models/genre_style.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 카드를 탭하면 뜨는 가벼운 미리보기 시트 — 표지/제목/작가/장르/짧은 설명과
/// 액션 버튼 하나만 보여준다.
///
/// 무료 팩은 "읽기 시작"을 누르면 기존 StoryPackDetailPage(소유 여부·진행
/// 상황을 실제로 처리하는 화면)로 들어간다 — 이미 잘 동작하는 흐름이라
/// 그대로 재사용한다. 유료 팩은 "결제하기"가 뜨는데, 결제 기능 자체가 아직
/// 없어서 스텁(안내 스낵바)만 띄운다.
Future<void> showStoryPackPreviewSheet(BuildContext context, StoryPack pack) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _StoryPackPreviewSheet(pack: pack),
  );
}

class _StoryPackPreviewSheet extends StatelessWidget {
  final StoryPack pack;

  const _StoryPackPreviewSheet({required this.pack});

  void _handlePrimaryAction(BuildContext context) {
    if (pack.isFree) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
      );
      return;
    }

    // 결제 기능은 아직 없다 — 스텁.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('결제 기능은 아직 준비 중이에요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final genreStyle = genreStyleFor(pack.primaryGenre);
    final coverImageUrl = pack.coverImageUrl;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: coverImageUrl != null && coverImageUrl.isNotEmpty
                      ? Image.network(
                          coverImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _CoverPlaceholder(genreStyle: genreStyle),
                        )
                      : _CoverPlaceholder(genreStyle: genreStyle),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: genreStyle.color.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      genreStyle.label,
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pack.format.label,
                    style: TextStyle(fontSize: 11, color: _ivory.withOpacity(0.45), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                pack.title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ivory),
              ),
              const SizedBox(height: 4),
              Text(
                pack.authorName,
                style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.65)),
              ),
              const SizedBox(height: 14),
              Text(
                pack.description,
                style: TextStyle(fontSize: 13.5, height: 1.55, color: Colors.white.withOpacity(0.85)),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _handlePrimaryAction(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    pack.isFree ? '읽기 시작' : '결제하기',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// StoryPackCard의 것과 같은 fallback — 표지 이미지가 없거나 로드에 실패하면
/// 브랜드 그라디언트 위에 장르 아이콘을 보여준다.
class _CoverPlaceholder extends StatelessWidget {
  final GenreStyle genreStyle;

  const _CoverPlaceholder({required this.genreStyle});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6B4A), Color(0xFFFFB648)],
            ),
          ),
        ),
        Center(
          child: Icon(genreStyle.icon, color: Colors.white.withOpacity(0.92), size: 56),
        ),
      ],
    );
  }
}
