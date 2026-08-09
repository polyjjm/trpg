import 'package:flutter/material.dart';

import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 라이브러리 그리드에 표시되는 이야기 팩 표지 카드.
/// 탭하면 [StoryPackDetailPage]로 이동한다.
class StoryPackCard extends StatelessWidget {
  final StoryPack pack;

  const StoryPackCard({super.key, required this.pack});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(pack.coverImage, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.55),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Text(
                      pack.format.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
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
          Text(
            pack.isFree ? '무료' : '₩${pack.price}',
            style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.62)),
          ),
        ],
      ),
    );
  }
}
