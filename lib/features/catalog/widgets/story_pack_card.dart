import 'package:flutter/material.dart';

import '../models/genre_style.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);

/// 라이브러리에 표시되는 이야기 팩 카드. 작가가 표지를 골랐으면 그 이미지를,
/// 아니면 로고와 같은 코랄→앰버 브랜드 그라디언트 위에 장르 아이콘을 얹은
/// placeholder를 보여준다 — 표지가 없는 팩도 깨져 보이지 않게 하는 fallback이지,
/// 유일한 표현 방식이 아니다. 탭하면 전체 화면 상세 페이지로 들어간다(예전의
/// 작은 미리보기 시트는 없앴다 — StoryPackDetailPage 자체가 미리보기 역할까지
/// 겸한다).
class StoryPackCard extends StatelessWidget {
  final StoryPack pack;

  const StoryPackCard({super.key, required this.pack});

  @override
  Widget build(BuildContext context) {
    final genreStyle = genreStyleFor(pack.primaryGenre);
    final coverImageUrl = pack.coverImageUrl;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverImageUrl != null && coverImageUrl.isNotEmpty)
                    Image.network(
                      coverImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _CoverPlaceholder(genreStyle: genreStyle),
                    )
                  else
                    _CoverPlaceholder(genreStyle: genreStyle),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _GenreTag(style: genreStyle),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pack.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ivory,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  pack.isFree ? '무료' : '₩${pack.price}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.62)),
                ),
              ),
              Text(
                pack.format.label,
                style: TextStyle(fontSize: 10.5, color: _ivory.withOpacity(0.40), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 표지 이미지가 없거나(coverImageUrl == null) 로드에 실패했을 때 쓰는
/// fallback — 브랜드 그라디언트 위에 장르 아이콘.
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
          child: Icon(genreStyle.icon, color: Colors.white.withOpacity(0.92), size: 40),
        ),
      ],
    );
  }
}

class _GenreTag extends StatelessWidget {
  final GenreStyle style;

  const _GenreTag({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}
